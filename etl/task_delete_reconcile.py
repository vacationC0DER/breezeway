#!/usr/bin/env python3
"""
Nightly delete-reconcile backstop for breezeway.tasks.

WHY: the task-deleted webhook is the ONLY delete path for breezeway.tasks — every
ETL path is upsert-only (ON CONFLICT DO UPDATE/NOTHING), so a *dropped* delete
webhook leaves a phantom task that lingers forever and keeps paying out through
the HK reconciliation MV (ops.mv_checkout_clean_match reads breezeway_fdw.tasks).

WHAT: re-fetch the live task list per property from the Breezeway /task LIST API to
get cheap *candidates* (in our DB, absent from the list). The list endpoint omits
completed/older tasks, so 'absent from the list' is NOT proof of deletion — VERIFIED:
list-missing tasks return 200 on direct GET. Each candidate is therefore confirmed
with a direct GET /task/{id}; only a 404 is authoritative. A candidate that 404s on
two consecutive runs (confirm-twice) is hard-deleted and logged.

SAFETY RAILS:
  - Per-property gating: a property whose fetch fails (incl. a 422 bad-request) is
    excluded — its tasks are never touched — but other properties still reconcile.
  - Never acts on an empty pull (0 live tasks → suspect, region skipped).
  - Deletion requires a direct GET /task 404 (not mere list-absence), on 2 successive
    runs (webhook_missing_strikes >= 2). Any 200 resets the counter.
  - Windowed to the pay-period-relevant range [today - past_days, today + future_days]
    (default -35..+45) — where a phantom clean would actually pay out, and where
    candidate counts are small. Settled/old tasks are ignored.
  - Every delete is copied to breezeway.task_reconcile_deletes (full row jsonb).

USAGE:
  python3 etl/task_delete_reconcile.py all [--dry-run] [--past-days 35] [--future-days 45]
  python3 etl/task_delete_reconcile.py nashville --dry-run
"""
import sys
import os
import argparse
import logging
from datetime import datetime, timedelta, timezone

_here = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(_here)
sys.path.insert(0, parent_dir)
sys.path.insert(0, os.path.join(parent_dir, "shared"))

import requests  # noqa: E402
from psycopg2.extras import RealDictCursor  # noqa: E402
from etl.etl_base import api_request_with_retry  # noqa: E402
from etl.config import API_CONFIG, DATABASE_CONFIG, get_all_regions  # noqa: E402
from auth_manager import TokenManager  # noqa: E402
from database import DatabaseManager  # noqa: E402

SCHEMA = DATABASE_CONFIG["schema"]
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("task_delete_reconcile")


def fetch_live_task_ids(region_code, conn):
    """Return (live_task_ids:set, ok_home_ids:set). A property whose full pagination
    fails (any error, incl. a 422 bad-request) is EXCLUDED from ok_home_ids so its
    tasks are never struck — but other properties still reconcile. Per-property
    gating: one permanently-bad property can't block the whole region, and we never
    delete a task whose property we couldn't enumerate."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"SELECT property_id, reference_external_property_id "
            f"FROM {SCHEMA}.properties WHERE region_code = %s",
            (region_code,),
        )
        properties = cur.fetchall()

    token_mgr = TokenManager(region_code, db_conn=conn)
    token = token_mgr.get_valid_token()
    headers = {"accept": "application/json", "Authorization": f"JWT {token}"}

    live = set()
    ok_home_ids = set()
    failed = 0
    for prop in properties:
        home_id = prop["property_id"]
        ref = prop["reference_external_property_id"] or ""
        prop_ids = set()
        prop_ok = True
        page = 1
        while True:
            url = (
                f"{API_CONFIG['base_url']}/task?limit={API_CONFIG['page_size']}"
                f"&page={page}&home_id={home_id}&reference_property_id={ref}"
            )
            try:
                resp = api_request_with_retry(url, headers)
            except Exception as e:  # noqa: BLE001
                log.warning(f"[{region_code}] property home_id={home_id} EXCLUDED (fetch failed p{page}): {e}")
                prop_ok = False
                failed += 1
                break
            tasks = resp.json().get("results", [])
            if not tasks:
                break
            for t in tasks:
                tid = str(t.get("id", ""))
                if tid:
                    prop_ids.add(tid)
            if len(tasks) < API_CONFIG["page_size"]:
                break
            page += 1
        if prop_ok:
            ok_home_ids.add(str(home_id))
            live |= prop_ids
    if failed:
        log.info(f"[{region_code}] {failed} property(ies) excluded (fetch error); "
                 f"{len(ok_home_ids)} reconciled")
    return live, ok_home_ids


def probe_task(tid, headers):
    """Direct GET /task/{id}. A 404 is the ONLY authoritative deletion signal — the
    /task LIST endpoint omits completed/older tasks, so 'absent from the list' is NOT
    proof of deletion (verified: list-missing tasks return 200 on direct GET).
    Returns 'deleted' (404), 'present' (2xx), or 'unknown' (transient/other)."""
    url = f"{API_CONFIG['base_url']}/task/{tid}"
    for _ in range(3):
        try:
            r = requests.get(url, headers=headers, timeout=30)
        except Exception:  # noqa: BLE001
            continue
        if r.status_code == 404:
            return "deleted"
        if 200 <= r.status_code < 300:
            return "present"
        if r.status_code in (429, 500, 502, 503, 504):
            continue
        return "unknown"  # 401/403/422 etc — don't infer deletion
    return "unknown"


def reconcile_region(region_code, conn, past_days, future_days, dry_run):
    live, ok_home_ids = fetch_live_task_ids(region_code, conn)
    if not ok_home_ids:
        log.warning(f"[{region_code}] SKIP — no property fetched successfully (guard)")
        return
    if not live:
        log.warning(f"[{region_code}] SKIP — 0 live tasks across fetched properties (suspect; guard)")
        return

    today = datetime.now(timezone.utc).date()
    lo = today - timedelta(days=past_days)
    hi = today + timedelta(days=future_days)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        # Deletion is scoped to the pay-period-relevant window (recent + near-future),
        # where a phantom clean would actually pay out. Only tasks whose property we
        # successfully enumerated this run are eligible.
        cur.execute(
            f"SELECT task_id, task_name, scheduled_date, webhook_missing_strikes "
            f"FROM {SCHEMA}.tasks "
            f"WHERE region_code = %s AND home_id = ANY(%s) "
            f"AND scheduled_date BETWEEN %s AND %s",
            (region_code, list(ok_home_ids), lo, hi),
        )
        db_rows = cur.fetchall()

    present_in_list = [r["task_id"] for r in db_rows if r["task_id"] in live]
    candidates = [r for r in db_rows if r["task_id"] not in live]
    log.info(
        f"[{region_code}] window=[{lo}..{hi}] eligible={len(db_rows)} "
        f"in-list={len(present_in_list)} list-missing candidates={len(candidates)} "
        f"— confirming each via GET /task/id"
    )

    token_mgr = TokenManager(region_code, db_conn=conn)
    headers = {"accept": "application/json", "Authorization": f"JWT {token_mgr.get_valid_token()}"}

    confirmed_deleted, confirmed_present, unknown = [], [], 0
    for r in candidates:
        verdict = probe_task(r["task_id"], headers)
        if verdict == "deleted":
            confirmed_deleted.append(r)
        elif verdict == "present":
            confirmed_present.append(r)
        else:
            unknown += 1

    to_delete = [r for r in confirmed_deleted if (r["webhook_missing_strikes"] or 0) + 1 >= 2]
    log.info(
        f"[{region_code}] confirmed_deleted(404)={len(confirmed_deleted)} "
        f"present(200)={len(confirmed_present)} unknown={unknown} "
        f"delete_now(confirm-twice)={len(to_delete)} dry_run={dry_run}"
    )
    for r in confirmed_deleted:
        log.info(
            f"[{region_code}] {'WOULD ' if dry_run else ''}confirm-deleted "
            f"task_id={r['task_id']} name={r['task_name']!r} sched={r['scheduled_date']} "
            f"strikes->{(r['webhook_missing_strikes'] or 0) + 1}"
        )
    if dry_run:
        return

    reset_ids = present_in_list + [r["task_id"] for r in confirmed_present]
    strike_ids = [r["task_id"] for r in confirmed_deleted]
    del_ids = [r["task_id"] for r in to_delete]
    with conn.cursor() as cur:
        if reset_ids:
            cur.execute(
                f"UPDATE {SCHEMA}.tasks "
                f"SET webhook_missing_strikes = 0, webhook_missing_since = NULL "
                f"WHERE region_code = %s AND task_id = ANY(%s)",
                (region_code, reset_ids),
            )
        if strike_ids:
            cur.execute(
                f"UPDATE {SCHEMA}.tasks "
                f"SET webhook_missing_strikes = webhook_missing_strikes + 1, "
                f"    webhook_missing_since = COALESCE(webhook_missing_since, now()) "
                f"WHERE region_code = %s AND task_id = ANY(%s)",
                (region_code, strike_ids),
            )
        if del_ids:
            cur.execute(
                f"INSERT INTO {SCHEMA}.task_reconcile_deletes "
                f"(region_code, task_id, task_name, scheduled_date, reason, task_row) "
                f"SELECT region_code, task_id, task_name, scheduled_date, "
                f"       'confirm-twice: GET /task 404 on 2 successive runs', to_jsonb(t) "
                f"FROM {SCHEMA}.tasks t "
                f"WHERE t.region_code = %s AND t.task_id = ANY(%s)",
                (region_code, del_ids),
            )
            cur.execute(
                f"DELETE FROM {SCHEMA}.tasks "
                f"WHERE region_code = %s AND task_id = ANY(%s)",
                (region_code, del_ids),
            )
    conn.commit()
    log.info(
        f"[{region_code}] committed — reset={len(reset_ids)} struck={len(strike_ids)} "
        f"deleted={len(del_ids)}"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("region", help="region_code or 'all'")
    ap.add_argument("--dry-run", action="store_true", help="log only; no strikes/deletes")
    ap.add_argument("--past-days", type=int, default=35, help="how far back to reconcile (pay-period buffer)")
    ap.add_argument("--future-days", type=int, default=45, help="how far forward to reconcile")
    args = ap.parse_args()

    regions = get_all_regions() if args.region == "all" else [args.region]
    conn = DatabaseManager.get_connection()
    try:
        for reg in regions:
            try:
                reconcile_region(reg, conn, args.past_days, args.future_days, args.dry_run)
            except Exception as e:  # noqa: BLE001
                conn.rollback()
                log.error(f"[{reg}] ERROR: {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()

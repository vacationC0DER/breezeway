#!/usr/bin/env python3
"""
property_lifecycle_reconcile.py
===============================
Sweep lifecycle drift between the Breezeway API and the breezeway.properties
mirror.

Why it exists: the regular ETL drops non-active records at transform
(ENTITY_CONFIGS['properties']['transform_filter_status'] = 'active') and
property_status is webhook-owned (no_update_columns), so a unit retired in
Breezeway freezes in the mirror as 'active' with its last external id — a
"ghost". 176 ghosts existed on 2026-07-06; the visible symptom was the
"Music City A" Connection Health false positive (stale row said active/no-id,
plus Music City B/C still held Guesty ids that now belong to the live
"2. Music City" units).

Per region:
  1. GET the full property list (the list endpoint DOES return inactive units).
  2. Lifecycle drift is corrected: API says inactive/deleted but mirror says
     otherwise -> update; mirror says inactive/deleted but API reactivated ->
     update. Operational statuses (clean/dirty/occupied/...) remain
     webhook-owned — this script never writes an operational-to-operational
     transition.
  3. reference_external_property_id drift is corrected (including clearing) so
     a stale Guesty id can't collide with the live unit that owns it now.
  4. Mirror rows absent from a COMPLETE API list are marked 'deleted'.
  5. synced_at/updated_at are bumped so bz_property_dim_supabase_push.py picks
     the rows up on its next incremental run.

Usage:
    python3 etl/property_lifecycle_reconcile.py all
    python3 etl/property_lifecycle_reconcile.py nashville --dry-run
"""

import sys
import os

# Match run_etl.py path setup so `etl.*`, `database`, `auth_manager` import.
_current_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_current_dir)
sys.path.insert(0, _parent_dir)
sys.path.insert(0, os.path.join(_parent_dir, 'shared'))

import argparse
import logging

import requests

from auth_manager import TokenManager
from database import DatabaseManager
from etl.config import get_all_regions, DATABASE_CONFIG

SRC_SCHEMA = DATABASE_CONFIG['schema']  # 'breezeway'
API_BASE = 'https://api.breezeway.io/public/inventory/v1/property'
LIFECYCLE = {'inactive', 'deleted'}
HTTP_TIMEOUT = 30
MAX_PAGES = 200  # 20k properties/region ceiling (breckenridge token sees >5k)

logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('property_lifecycle_reconcile')


def fetch_api_properties(region):
    """Full property list for a region: {property_id(str): (status, ext_id)}.

    Returns (mapping, complete). complete=False means pagination aborted —
    callers must NOT infer deletions from an incomplete list.
    """
    token = TokenManager(region).get_valid_token()
    hdr = {'Authorization': f'JWT {token}'}
    out, page = {}, 1
    while page <= MAX_PAGES:
        r = requests.get(API_BASE, headers=hdr,
                         params={'limit': 100, 'page': page}, timeout=HTTP_TIMEOUT)
        if r.status_code >= 300:
            logger.error(f"[{region}] list page {page} -> {r.status_code} {r.text[:200]}")
            return out, False
        rows = (r.json() or {}).get('results') or []
        for p in rows:
            out[str(p.get('id'))] = (
                str(p.get('status') or ''),
                str(p.get('reference_external_property_id') or ''),
            )
        if len(rows) < 100:
            return out, True
        page += 1
    logger.error(f"[{region}] exceeded {MAX_PAGES} pages — treating list as incomplete")
    return out, False


def run_region(conn, region, dry):
    api, complete = fetch_api_properties(region)
    if not api:
        logger.warning(f"[{region}] API returned no properties — skipping")
        return {'status': 0, 'ext_id': 0, 'deleted': 0}

    with conn.cursor() as cur:
        cur.execute(f"""
            SELECT property_id, property_status, reference_external_property_id
            FROM {SRC_SCHEMA}.properties WHERE region_code = %s
        """, (region,))
        mirror = cur.fetchall()

    changes = {'status': 0, 'ext_id': 0, 'deleted': 0}
    updates = []  # (new_status_or_None, new_ext_or_None, property_id)
    for property_id, m_status, m_ext in mirror:
        m_status = str(m_status or '')
        m_ext = str(m_ext or '')
        hit = api.get(str(property_id))
        if hit is None:
            # Hard-deleted in Breezeway. Only trust a COMPLETE list.
            if complete and m_status != 'deleted':
                updates.append(('deleted', None, property_id))
                changes['deleted'] += 1
            continue
        a_status, a_ext = hit
        new_status = None
        # Lifecycle transitions only — operational statuses stay webhook-owned.
        if a_status != m_status and (a_status in LIFECYCLE or m_status in LIFECYCLE):
            new_status = a_status
            changes['status'] += 1
        new_ext = a_ext if a_ext != m_ext else None
        if new_ext is not None:
            changes['ext_id'] += 1
        if new_status is not None or new_ext is not None:
            updates.append((new_status, new_ext, property_id))

    for new_status, new_ext, property_id in updates:
        sets = ['synced_at = now()', 'updated_at = now()']
        params = []
        if new_status is not None:
            sets.insert(0, 'property_status = %s')
            params.append(new_status)
        if new_ext is not None:
            sets.insert(-2, 'reference_external_property_id = %s')
            params.append(new_ext)
        params.extend([property_id, region])
        if dry:
            logger.info(f"[{region}] DRY property {property_id}: "
                        f"status->{new_status or '(keep)'} ext->{new_ext if new_ext is not None else '(keep)'}")
        else:
            with conn.cursor() as cur:
                cur.execute(f"""
                    UPDATE {SRC_SCHEMA}.properties
                    SET {', '.join(sets)}
                    WHERE property_id = %s AND region_code = %s
                """, params)
    if not dry:
        conn.commit()
    logger.info(f"[{region}] api={len(api)} mirror={len(mirror)} complete={complete} "
                f"status_fixed={changes['status']} ext_fixed={changes['ext_id']} "
                f"marked_deleted={changes['deleted']}{' (dry-run)' if dry else ''}")
    return changes


def main():
    p = argparse.ArgumentParser(description='Reconcile Breezeway property lifecycle into the mirror')
    p.add_argument('region', help="region code or 'all'")
    p.add_argument('--dry-run', action='store_true')
    args = p.parse_args()

    regions = get_all_regions() if args.region == 'all' else [args.region]
    conn = DatabaseManager.get_connection()
    logger.info(f"Connected to {conn.info.dbname} as {conn.info.user}")

    exit_code = 0
    totals = {'status': 0, 'ext_id': 0, 'deleted': 0}
    for region in regions:
        try:
            c = run_region(conn, region, args.dry_run)
            for k in totals:
                totals[k] += c[k]
        except Exception as e:  # noqa: BLE001
            logger.error(f"[{region}] FAILED: {e}", exc_info=True)
            conn.rollback()
            exit_code = 1
    logger.info(f"DONE: status_fixed={totals['status']} ext_fixed={totals['ext_id']} "
                f"marked_deleted={totals['deleted']}")
    sys.exit(exit_code)


if __name__ == '__main__':
    main()

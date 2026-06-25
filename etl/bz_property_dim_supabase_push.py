#!/usr/bin/env python3
"""
bz_property_dim_supabase_push.py
================================
Push breezeway.properties (the authoritative Breezeway property dimension: address,
region, Guesty external id) to the VR Goals Supabase table tasks.bz_property_dim, via
a service_role PostgREST upsert (Content-Profile: tasks). Multitenant: client_id is
resolved server-side by the public.bz_set_client_id_from_region trigger
(region_code -> tasks.bz_region_client_map) — we never send client_id.

This is the missing half of the Breezeway↔Guesty connection-health report: Supabase
previously had no independent Breezeway-side address/region (bz_property_status is
webhook-driven and sparse). With this dimension synced, tasks.v_bz_guesty_connection_health
can flag units filed under the wrong Breezeway company (the missed-inspection bug).

Incremental by source synced_at watermark, tracked in breezeway.supabase_push_log
(table_name='bz_property_dim'). --full ignores the watermark (complete refresh).

Usage:
    python3 etl/bz_property_dim_supabase_push.py all
    python3 etl/bz_property_dim_supabase_push.py austin --full
    python3 etl/bz_property_dim_supabase_push.py all --full --dry-run
    python3 etl/bz_property_dim_supabase_push.py austin --full --limit 50 --dry-run
"""

import sys
import os

# Match run_etl.py path setup so `etl.*`, `database` import.
_current_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_current_dir)
sys.path.insert(0, _parent_dir)
sys.path.insert(0, os.path.join(_parent_dir, 'shared'))

import argparse
import json
import logging
from datetime import datetime, date, time, timezone
from decimal import Decimal

import requests
from psycopg2.extras import RealDictCursor

from dotenv import dotenv_values

from database import DatabaseManager
from etl.config import get_all_regions, DATABASE_CONFIG

SRC_SCHEMA = DATABASE_CONFIG['schema']          # 'breezeway'
TARGET_TABLE = 'bz_property_dim'
CONFLICT = 'region_code,breezeway_property_id'
BATCH = 500
HTTP_TIMEOUT = 30

_ENV = dotenv_values(os.path.join(_parent_dir, '.env'))
SUPABASE_URL = (_ENV.get('SUPABASE_URL') or os.environ.get('SUPABASE_URL') or '').rstrip('/')
SUPABASE_KEY = (_ENV.get('SUPABASE_SERVICE_ROLE_KEY')
                or os.environ.get('SUPABASE_SERVICE_ROLE_KEY') or '')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)
logger = logging.getLogger('PropDimPush')

# Source columns (breezeway.properties) -> target columns (tasks.bz_property_dim).
# Source col on the left of RENAME; 1:1 where not renamed.
COLS = [
    'region_code', 'property_id', 'reference_external_property_id', 'reference_company_id',
    'property_name', 'property_status', 'property_address1', 'property_address2',
    'property_city', 'property_state', 'property_zipcode',
    'latitude_numeric', 'longitude_numeric', 'bedrooms', 'bathrooms', 'synced_at',
]
RENAME = {
    'property_id': 'breezeway_property_id',
    'reference_external_property_id': 'guesty_listing_id',
    'latitude_numeric': 'latitude',
    'longitude_numeric': 'longitude',
    'synced_at': 'source_synced_at',
}
# id-ish columns forced to text to match the target schema.
TEXT_COLS = {'breezeway_property_id', 'guesty_listing_id', 'reference_company_id',
             'property_zipcode'}


def _ser(v):
    if v is None:
        return None
    if isinstance(v, (datetime, date, time)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    return v


def ensure_push_log(conn):
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS breezeway.supabase_push_log (
                table_name     text NOT NULL,
                region_code    text NOT NULL,
                last_pushed_at timestamptz,
                rows_pushed    bigint NOT NULL DEFAULT 0,
                updated_at     timestamptz NOT NULL DEFAULT now(),
                PRIMARY KEY (table_name, region_code)
            )
        """)
    conn.commit()


def get_watermark(conn, region):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT last_pushed_at FROM breezeway.supabase_push_log
            WHERE table_name = %s AND region_code = %s
        """, (TARGET_TABLE, region))
        row = cur.fetchone()
    return row[0] if row else None


def set_watermark(conn, region, ts, rows_pushed):
    if ts is None:
        return
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO breezeway.supabase_push_log
                (table_name, region_code, last_pushed_at, rows_pushed, updated_at)
            VALUES (%s, %s, %s, %s, now())
            ON CONFLICT (table_name, region_code) DO UPDATE SET
                last_pushed_at = GREATEST(EXCLUDED.last_pushed_at, supabase_push_log.last_pushed_at),
                rows_pushed    = supabase_push_log.rows_pushed + EXCLUDED.rows_pushed,
                updated_at     = now()
        """, (TARGET_TABLE, region, ts, rows_pushed))
    conn.commit()


def to_payload(src_row):
    out = {}
    for c in COLS:
        out[RENAME.get(c, c)] = _ser(src_row[c])
    for k in TEXT_COLS:
        if out.get(k) is not None:
            out[k] = str(out[k])
    return out


def push_batch(rows, dry):
    if dry:
        logger.info(f"[dry-run] would POST {len(rows)} rows")
        return True
    url = f"{SUPABASE_URL}/rest/v1/{TARGET_TABLE}?on_conflict={CONFLICT}"
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {SUPABASE_KEY}',
        'Content-Type': 'application/json',
        'Content-Profile': 'tasks',
        'Prefer': 'resolution=merge-duplicates,return=minimal',
    }
    resp = requests.post(url, data=json.dumps(rows, default=str),
                         headers=headers, timeout=HTTP_TIMEOUT)
    if resp.status_code >= 300:
        logger.error(f"POST failed [{resp.status_code}]: {resp.text[:400]}")
        return False
    return True


def run_region(conn, region, full, limit, dry):
    wm = None if full else get_watermark(conn, region)
    where = "region_code = %s"
    params = [region]
    if wm is not None:
        where += " AND synced_at > %s"
        params.append(wm)
    sql = f"""
        SELECT {', '.join(COLS)}
        FROM {SRC_SCHEMA}.properties
        WHERE {where}
        ORDER BY synced_at
    """
    if limit:
        sql += f" LIMIT {int(limit)}"

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        src_rows = cur.fetchall()

    total = len(src_rows)
    if total == 0:
        logger.info(f"[{region}] nothing new (watermark={wm})")
        return {'pushed': 0, 'failed': 0, 'watermark': wm}

    pushed = failed = 0
    max_synced = wm
    for i in range(0, total, BATCH):
        chunk = src_rows[i:i + BATCH]
        payload = [to_payload(r) for r in chunk]
        if push_batch(payload, dry):
            pushed += len(chunk)
            for r in chunk:
                if r['synced_at'] and (max_synced is None or r['synced_at'] > max_synced):
                    max_synced = r['synced_at']
        else:
            failed += len(chunk)
        logger.info(f"[{region}] {min(i + BATCH, total)}/{total} (pushed={pushed} failed={failed})")

    if not dry and failed == 0:
        set_watermark(conn, region, max_synced, pushed)
    return {'pushed': pushed, 'failed': failed, 'watermark': max_synced}


def main():
    p = argparse.ArgumentParser(description='Push breezeway.properties -> Supabase tasks.bz_property_dim')
    p.add_argument('region', help="region code or 'all'")
    p.add_argument('--full', action='store_true', help='ignore watermark; push all rows for region')
    p.add_argument('--limit', type=int, help='max source rows (testing)')
    p.add_argument('--dry-run', action='store_true', help='build payloads but do not POST')
    args = p.parse_args()

    if not SUPABASE_URL or not SUPABASE_KEY:
        logger.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set in .env — aborting")
        sys.exit(2)

    regions = get_all_regions() if args.region == 'all' else [args.region]
    conn = DatabaseManager.get_connection()
    logger.info(f"Connected to {conn.info.dbname} as {conn.info.user}; target={SUPABASE_URL}")
    ensure_push_log(conn)

    overall = {}
    exit_code = 0
    for region in regions:
        try:
            overall[region] = run_region(conn, region, args.full, args.limit, args.dry_run)
            if overall[region]['failed']:
                exit_code = 1
        except Exception as e:  # noqa: BLE001
            logger.error(f"[{region}] FAILED: {e}", exc_info=True)
            conn.rollback()
            exit_code = 1

    total_pushed = sum(r['pushed'] for r in overall.values())
    total_failed = sum(r['failed'] for r in overall.values())
    logger.info(f"DONE: pushed={total_pushed} failed={total_failed} across {len(overall)} region(s)")
    sys.exit(exit_code)


if __name__ == '__main__':
    main()

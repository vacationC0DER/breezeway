#!/usr/bin/env python3
"""
Fast parallel task sync - parents only, no child records
Fetches linked_reservation_id and other missing fields efficiently
"""
import sys
sys.path.insert(0, "/root/Breezeway/shared")
sys.path.insert(0, "/root/Breezeway/etl")

import concurrent.futures
import logging
from datetime import datetime
from database import DatabaseManager
from auth_manager import TokenManager
from config import DATABASE_CONFIG, ENTITY_CONFIGS
import requests
from psycopg2.extras import RealDictCursor, execute_values

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(message)s")
log = logging.getLogger(__name__)

REGIONS = ["nashville", "austin", "smoky", "hilton_head", "breckenridge", "sea_ranch", "mammoth", "hill_country"]
API_BASE = "https://api.breezeway.io/public/inventory/v1"
MAX_WORKERS = 8  # Parallel API calls

def get_properties(region):
    """Get all properties for a region"""
    db = DatabaseManager()
    conn = db.get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(f"""
        SELECT property_id, reference_external_property_id
        FROM {DATABASE_CONFIG['schema']}.properties
        WHERE region_code = %s
    """, (region,))
    props = cur.fetchall()
    cur.close()
    return props

def fetch_tasks_for_property(args):
    """Fetch all tasks for a single property (called in parallel)"""
    region, prop, token = args
    home_id = prop["property_id"]
    ref_id = prop["reference_external_property_id"] or ""
    headers = {"accept": "application/json", "Authorization": f"JWT {token}"}
    
    tasks = []
    page = 1
    while True:
        url = f"{API_BASE}/task?limit=100&page={page}&home_id={home_id}&reference_property_id={ref_id}"
        try:
            resp = requests.get(url, headers=headers, timeout=30)
            if resp.status_code == 422:
                break
            resp.raise_for_status()
            batch = resp.json().get("results", [])
            if not batch:
                break
            tasks.extend(batch)
            if len(batch) < 100:
                break
            page += 1
        except Exception as e:
            break
    return tasks

def fetch_region(region):
    """Fetch all tasks for a region using parallel property calls"""
    log.info(f"[{region}] Starting...")
    
    props = get_properties(region)
    log.info(f"[{region}] {len(props)} properties")
    
    token_mgr = TokenManager(region)
    token = token_mgr.get_valid_token()
    
    # Parallel fetch across properties
    args = [(region, p, token) for p in props]
    all_tasks = []
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        results = executor.map(fetch_tasks_for_property, args)
        for batch in results:
            all_tasks.extend(batch)
    
    log.info(f"[{region}] Extracted {len(all_tasks)} tasks")
    return region, all_tasks

def transform(tasks, region):
    """Transform tasks to DB schema"""
    config = ENTITY_CONFIGS["tasks"]
    transformed = []
    
    for task in tasks:
        rec = {"region_code": region}
        
        # Direct fields
        for api_field, db_col in config["fields_mapping"].items():
            rec[db_col] = task.get(api_field)
        
        # Nested fields (linked_reservation, etc.)
        for parent_field, nested in config.get("nested_fields", {}).items():
            parent_val = task.get(parent_field, {})
            if isinstance(parent_val, dict):
                for nested_field, db_col in nested.items():
                    rec[db_col] = parent_val.get(nested_field)
        
        rec["synced_at"] = datetime.now()
        # Clean numeric fields
        import re
        for field in ["rate_paid", "estimated_rate", "total_cost", "itemized_cost"]:
            val = rec.get(field)
            if val and isinstance(val, str):
                match = re.search(r"[\d.]+", val)
                rec[field] = float(match.group()) if match else None
            elif val == "":
                rec[field] = None
        transformed.append(rec)
    
    return transformed

def load(records):
    """Bulk upsert all records"""
    if not records:
        return 0
    
    # Deduplicate
    seen = set()
    unique = []
    for r in records:
        key = (r.get("task_id"), r.get("region_code"))
        if key not in seen:
            seen.add(key)
            unique.append(r)
    
    log.info(f"Loading {len(unique)} unique tasks...")
    
    db = DatabaseManager()
    conn = db.get_connection()
    cur = conn.cursor()
    
    # Get all possible columns from config
    config = ENTITY_CONFIGS["tasks"]
    columns = ["region_code"]
    columns.extend(config["fields_mapping"].values())
    for nested in config.get("nested_fields", {}).values():
        columns.extend(nested.values())
    columns.append("synced_at")
    table = f"{DATABASE_CONFIG['schema']}.tasks"
    
    cols_str = ", ".join(columns)
    conflict = "task_id, region_code"
    update = ", ".join([f"{c} = EXCLUDED.{c}" for c in columns if c not in ["task_id", "region_code", "created_at"]])
    
    query = f"INSERT INTO {table} ({cols_str}) VALUES %s ON CONFLICT ({conflict}) DO UPDATE SET {update}"
    values = [tuple(r.get(c) for c in columns) for r in unique]
    
    execute_values(cur, query, values, page_size=1000)
    conn.commit()
    cur.close()
    
    return len(unique)

def resolve_fks():
    """Resolve reservation_pk from linked_reservation_id"""
    log.info("Resolving FK links...")
    db = DatabaseManager()
    conn = db.get_connection()
    cur = conn.cursor()
    
    cur.execute(f"""
        UPDATE {DATABASE_CONFIG['schema']}.tasks t
        SET reservation_pk = r.id
        FROM {DATABASE_CONFIG['schema']}.reservations r
        WHERE t.linked_reservation_id::varchar = r.reservation_id
          AND t.region_code = r.region_code
          AND t.reservation_pk IS NULL
          AND t.linked_reservation_id IS NOT NULL
    """)
    
    count = cur.rowcount
    conn.commit()
    cur.close()
    log.info(f"Resolved {count} FK links")
    return count

def main():
    start = datetime.now()
    log.info(f"=== FAST PARALLEL SYNC - {len(REGIONS)} regions ===")
    
    # Parallel extraction across regions
    all_records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(fetch_region, r): r for r in REGIONS}
        for future in concurrent.futures.as_completed(futures):
            try:
                region, tasks = future.result()
                transformed = transform(tasks, region)
                all_records.extend(transformed)
                log.info(f"[{region}] Transformed {len(transformed)} records")
            except Exception as e:
                log.error(f"Failed: {e}")
    
    # Bulk load
    loaded = load(all_records)
    
    # FK resolution
    fk_count = resolve_fks()
    
    duration = (datetime.now() - start).total_seconds()
    log.info(f"=== COMPLETE: {loaded} tasks, {fk_count} FKs, {duration:.0f}s ===")

if __name__ == "__main__":
    main()

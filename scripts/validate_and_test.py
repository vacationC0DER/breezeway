#!/usr/bin/env python3
"""Quick validation and single-property test before full ETL run"""
import sys
sys.path.insert(0, "/root/Breezeway/shared")
sys.path.insert(0, "/root/Breezeway/etl")

from config import ENTITY_CONFIGS, DATABASE_CONFIG
from auth_manager import TokenManager
from database import DatabaseManager
import requests
import psycopg2
from psycopg2.extras import RealDictCursor

def validate_schema():
    """Check all config columns exist in database"""
    print("=== VALIDATING SCHEMA ===")
    db = DatabaseManager()
    conn = db.get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    errors = []
    for entity, config in ENTITY_CONFIGS.items():
        table = config["table_name"]
        
        # Get actual columns
        cur.execute(f"""
            SELECT column_name, data_type, is_nullable 
            FROM information_schema.columns 
            WHERE table_schema = %s AND table_name = %s
        """, (DATABASE_CONFIG["schema"], table))
        db_columns = {r["column_name"]: r for r in cur.fetchall()}
        
        # Check fields_mapping
        for api_field, db_col in config.get("fields_mapping", {}).items():
            if db_col not in db_columns:
                errors.append(f"{entity}.{db_col} - column missing from {table}")
        
        # Check nested_fields
        for parent, nested in config.get("nested_fields", {}).items():
            for api_field, db_col in nested.items():
                if db_col not in db_columns:
                    errors.append(f"{entity}.{db_col} (from {parent}.{api_field}) - column missing from {table}")
    
    cur.close()
    
    if errors:
        print("ERRORS FOUND:")
        for e in errors:
            print(f"  - {e}")
        return False
    print("✓ All columns exist")
    return True

def test_single_property(region="hill_country"):
    """Test ETL with single property"""
    print(f"\n=== TESTING SINGLE PROPERTY ({region}) ===")
    
    db = DatabaseManager()
    conn = db.get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    # Get one property with tasks
    cur.execute(f"""
        SELECT p.property_id, p.reference_external_property_id, COUNT(t.id) as task_count
        FROM {DATABASE_CONFIG["schema"]}.properties p
        LEFT JOIN {DATABASE_CONFIG["schema"]}.tasks t ON t.home_id = p.property_id AND t.region_code = p.region_code
        WHERE p.region_code = %s AND p.reference_external_property_id IS NOT NULL
        GROUP BY p.property_id, p.reference_external_property_id
        HAVING COUNT(t.id) > 0
        ORDER BY task_count DESC
        LIMIT 1
    """, (region,))
    prop = cur.fetchone()
    
    if not prop:
        print(f"No properties with tasks found for {region}")
        return False
    
    print(f"Testing property {prop["property_id"]} ({prop["task_count"]} existing tasks)")
    
    # Fetch from API
    token_mgr = TokenManager(region)
    token = token_mgr.get_valid_token()
    
    resp = requests.get(
        f"https://api.breezeway.io/public/inventory/v1/task?limit=5&page=1&home_id={prop["property_id"]}&reference_property_id={prop["reference_external_property_id"]}",
        headers={"accept": "application/json", "Authorization": f"JWT {token}"},
        timeout=30
    )
    
    if resp.status_code != 200:
        print(f"API error: {resp.status_code}")
        return False
    
    tasks = resp.json().get("results", [])
    print(f"Fetched {len(tasks)} tasks from API")
    
    if tasks:
        t = tasks[0]
        print(f"Sample task keys: {list(t.keys())[:15]}...")
        lr = t.get("linked_reservation")
        if lr:
            print(f"linked_reservation: {lr}")
        supplies = t.get("supplies", [])
        if supplies:
            print(f"supplies[0]: {supplies[0]}")
    
    print("✓ API test passed")
    return True

def run_mini_etl(region="hill_country"):
    """Run ETL for single property only"""
    print(f"\n=== MINI ETL TEST ({region}) ===")
    from etl_base import BreezewayETL
    
    db = DatabaseManager()
    conn = db.get_connection()
    
    # Temporarily patch to only process 1 property
    etl = BreezewayETL(region, "tasks", conn)
    
    # Override _extract_tasks to limit to 1 property
    original_extract = etl._extract_tasks
    def limited_extract():
        records = original_extract()
        # Only keep first 50 records for testing
        return records[:50] if records else []
    
    etl._extract_tasks = limited_extract
    
    try:
        etl.run()
        print("✓ Mini ETL completed successfully")
        return True
    except Exception as e:
        print(f"✗ Mini ETL failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    region = sys.argv[1] if len(sys.argv) > 1 else "hill_country"
    
    if not validate_schema():
        sys.exit(1)
    
    if not test_single_property(region):
        sys.exit(1)
    
    if not run_mini_etl(region):
        sys.exit(1)
    
    print("\n=== ALL TESTS PASSED - Safe to run full ETL ===")

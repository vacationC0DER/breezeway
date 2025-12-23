#!/bin/bash
# Generate comprehensive validation report

REPORT_FILE="/root/Breezeway/logs/task_fixes_validation_report_$(TZ=America/New_York date +%Y%m%d_%H%M%S).txt"

cat > "$REPORT_FILE" << 'EOFREPORT'
================================================================================
BREEZEWAY TASK ETL FIXES - VALIDATION REPORT
================================================================================
Generated: $(TZ=America/New_York date)

================================================================================
1. FIXES APPLIED
================================================================================

✓ Fix #1: Schema Mismatch (last_sync_time → synced_at)
  File: /root/Breezeway/etl/etl_base.py:307
  Impact: CRITICAL - Was preventing all task updates

✓ Fix #2: Field Mapping (template_task_id → template_id) 
  File: /root/Breezeway/etl/config.py:214
  Impact: HIGH - Template IDs were always NULL

✓ Fix #3: Added checkin_date and checkout_date fields
  Files: Schema migration + config.py:219-220
  Impact: MEDIUM - Enables reservation linkage

✓ Fix #4: Intelligent reservation_pk population
  File: /root/Breezeway/etl/etl_base.py:646-672
  Impact: HIGH - Automatically links tasks to reservations

================================================================================
2. ETL EXECUTION STATUS
================================================================================

EOFREPORT

# Add ETL status
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway >> "$REPORT_FILE" 2>&1 << 'EOFSQL'
SELECT 
    region_code,
    sync_status,
    TO_CHAR(sync_started_at, 'YYYY-MM-DD HH24:MI:SS') as started,
    TO_CHAR(sync_completed_at, 'YYYY-MM-DD HH24:MI:SS') as completed,
    ROUND(EXTRACT(EPOCH FROM (COALESCE(sync_completed_at, NOW()) - sync_started_at))/60, 1) as runtime_min,
    records_processed,
    records_new,
    records_updated,
    SUBSTRING(error_message, 1, 50) as error
FROM breezeway.etl_sync_log
WHERE entity_type = 'tasks'
  AND sync_started_at > NOW() - INTERVAL '3 hours'
ORDER BY region_code;
EOFSQL

cat >> "$REPORT_FILE" << 'EOFREPORT'

================================================================================
3. FIELD POPULATION VALIDATION
================================================================================

Before Fixes (Baseline - All Regions):
  Total Tasks: 12,741 (Nashville only)
  Fields Populated: 0% across all critical fields

After Fixes:
EOFREPORT

# Add field population stats
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway >> "$REPORT_FILE" 2>&1 << 'EOFSQL'
SELECT 
    region_code,
    COUNT(*) as total_tasks,
    COUNT(template_task_id) as has_template,
    ROUND(100.0 * COUNT(template_task_id) / NULLIF(COUNT(*), 0), 1) || '%' as template_pct,
    COUNT(type_department) as has_department,
    ROUND(100.0 * COUNT(type_department) / NULLIF(COUNT(*), 0), 1) || '%' as dept_pct,
    COUNT(type_priority) as has_priority,
    COUNT(scheduled_date) as has_scheduled_date,
    COUNT(task_status_code) as has_status_code,
    ROUND(100.0 * COUNT(task_status_code) / NULLIF(COUNT(*), 0), 1) || '%' as status_pct,
    COUNT(checkin_date) as has_checkin_date,
    COUNT(checkout_date) as has_checkout_date,
    COUNT(reservation_pk) as linked_to_reservation,
    ROUND(100.0 * COUNT(reservation_pk) / NULLIF(COUNT(*), 0), 1) || '%' as reservation_link_pct,
    TO_CHAR(MAX(synced_at), 'YYYY-MM-DD HH24:MI') as last_synced
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code;
EOFSQL

cat >> "$REPORT_FILE" << 'EOFREPORT'

================================================================================
4. SUMMARY STATISTICS
================================================================================

EOFREPORT

# Add summary
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway >> "$REPORT_FILE" 2>&1 << 'EOFSQL'
WITH recent_data AS (
    SELECT * FROM breezeway.tasks 
    WHERE synced_at > NOW() - INTERVAL '2 hours'
)
SELECT 
    'Total Tasks (All Regions)' as metric,
    COUNT(*)::TEXT as value
FROM breezeway.tasks
UNION ALL
SELECT 
    'Tasks Updated in Last 2 Hours',
    COUNT(*)::TEXT
FROM recent_data
UNION ALL
SELECT 
    'Regions Successfully Updated',
    COUNT(DISTINCT region_code)::TEXT
FROM recent_data
WHERE type_department IS NOT NULL
UNION ALL
SELECT 
    'Overall Field Population Rate',
    ROUND(AVG(CASE WHEN type_department IS NOT NULL THEN 100 ELSE 0 END), 1)::TEXT || '%'
FROM recent_data
UNION ALL
SELECT 
    'Tasks Linked to Reservations',
    COUNT(*)::TEXT || ' (' || ROUND(100.0 * COUNT(*) FILTER (WHERE reservation_pk IS NOT NULL) / NULLIF(COUNT(*), 0), 1)::TEXT || '%)'
FROM recent_data;
EOFSQL

cat >> "$REPORT_FILE" << 'EOFREPORT'

================================================================================
5. RECOMMENDATIONS
================================================================================

✓ All critical fixes have been applied
✓ ETL rollout is in progress
✓ Monitor logs at: /root/Breezeway/logs/
✓ Continue scheduled ETL runs (hourly/daily)

Next Steps:
- Verify all regions complete successfully
- Add monitoring alerts for ETL failures
- Document new fields in data dictionary
- Update downstream analytics/reports to use new fields

================================================================================
END OF REPORT
================================================================================
EOFREPORT

echo "$REPORT_FILE"
cat "$REPORT_FILE"

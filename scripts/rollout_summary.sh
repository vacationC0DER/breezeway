#!/bin/bash
# Quick rollout summary

echo "=== ROLLOUT SUMMARY ==="
echo ""

# Count by status
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway << 'EOFSQL'
SELECT 
    sync_status,
    COUNT(*) as regions,
    STRING_AGG(region_code, ', ' ORDER BY region_code) as region_list
FROM breezeway.etl_sync_log
WHERE entity_type = 'tasks'
  AND sync_started_at > NOW() - INTERVAL '2 hours'
GROUP BY sync_status
ORDER BY 
    CASE sync_status 
        WHEN 'success' THEN 1 
        WHEN 'running' THEN 2 
        ELSE 3 
    END;
EOFSQL

echo ""
echo "=== FIELD POPULATION STATUS ==="
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway << 'EOFSQL'
SELECT 
    region_code,
    COUNT(*) as total_tasks,
    ROUND(100.0 * COUNT(type_department) / NULLIF(COUNT(*), 0), 1) as pct_has_department,
    ROUND(100.0 * COUNT(template_task_id) / NULLIF(COUNT(*), 0), 1) as pct_has_template,
    ROUND(100.0 * COUNT(task_status_code) / NULLIF(COUNT(*), 0), 1) as pct_has_status,
    ROUND(100.0 * COUNT(reservation_pk) / NULLIF(COUNT(*), 0), 1) as pct_linked_to_reservation
FROM breezeway.tasks
WHERE synced_at > NOW() - INTERVAL '2 hours'
GROUP BY region_code
ORDER BY region_code;
EOFSQL

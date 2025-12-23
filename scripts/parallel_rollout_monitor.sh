#!/bin/bash
# Parallel rollout monitoring dashboard

clear
echo "================================================================================"
echo "PARALLEL ETL ROLLOUT - REAL-TIME STATUS"
echo "================================================================================"
echo "Time: $(TZ=America/New_York date)"
echo ""

# Count processes
RUNNING=$(ps aux | grep "etl/run_etl.py.*tasks" | grep -v grep | grep -E "(nashville|austin|smoky|hilton_head|breckenridge|sea_ranch|mammoth|hill_country)" | wc -l)
echo "Active ETL Processes: $RUNNING/8"
echo ""

# Individual region status
echo "Region Status:"
echo "--------------------------------------------------------------------------------"
printf "%-15s %-12s %-12s %-15s %s\n" "REGION" "STATUS" "RUNTIME" "PROCESSED" "PROGRESS"
echo "--------------------------------------------------------------------------------"

for region in nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country; do
    # Check if process running
    if ps aux | grep "etl/run_etl.py $region tasks" | grep -v grep > /dev/null; then
        PROCESS_STATUS="🟢 Running"
    else
        PROCESS_STATUS="🔴 Stopped"
    fi
    
    # Get DB status
    DB_INFO=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -A -F'|' -c "
        SELECT 
            sync_status,
            ROUND(EXTRACT(EPOCH FROM (NOW() - sync_started_at))/60, 1),
            records_processed
        FROM breezeway.etl_sync_log
        WHERE entity_type = 'tasks' AND region_code = '$region'
        ORDER BY sync_started_at DESC LIMIT 1;
    " 2>/dev/null)
    
    if [ -n "$DB_INFO" ]; then
        STATUS=$(echo "$DB_INFO" | cut -d'|' -f1)
        RUNTIME=$(echo "$DB_INFO" | cut -d'|' -f2)
        PROCESSED=$(echo "$DB_INFO" | cut -d'|' -f3)
        
        case $STATUS in
            "running") STATUS_ICON="⏳" ;;
            "success") STATUS_ICON="✅" ;;
            "failed") STATUS_ICON="❌" ;;
            *) STATUS_ICON="⚪" ;;
        esac
        
        printf "%-15s %-12s %-12s %-15s %s\n" "$region" "$STATUS_ICON $STATUS" "${RUNTIME}m" "$PROCESSED" "$PROCESS_STATUS"
    else
        printf "%-15s %-12s %-12s %-15s %s\n" "$region" "⚪ pending" "-" "-" "$PROCESS_STATUS"
    fi
done

echo "--------------------------------------------------------------------------------"
echo ""

# Summary stats
echo "Summary Statistics:"
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
    SELECT 
        '  Total Running: ' || COUNT(*) FILTER (WHERE sync_status = 'running') || ' regions',
        '  Total Completed: ' || COUNT(*) FILTER (WHERE sync_status = 'success') || ' regions',
        '  Total Failed: ' || COUNT(*) FILTER (WHERE sync_status = 'failed') || ' regions'
    FROM breezeway.etl_sync_log
    WHERE entity_type = 'tasks'
      AND sync_started_at > NOW() - INTERVAL '2 hours'
    LIMIT 1;
" 2>/dev/null | tr '|' '\n'

echo ""
echo "Records Updated:"
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
    SELECT '  ' || COUNT(*) || ' tasks synced in last 30 minutes'
    FROM breezeway.tasks
    WHERE synced_at > NOW() - INTERVAL '30 minutes';
" 2>/dev/null

echo ""
echo "Field Population (Recent Updates):"
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
    SELECT 
        '  template_task_id: ' || COUNT(template_task_id) || '/' || COUNT(*) || ' (' || ROUND(100.0 * COUNT(template_task_id) / NULLIF(COUNT(*), 0), 1) || '%)',
        '  type_department: ' || COUNT(type_department) || '/' || COUNT(*) || ' (' || ROUND(100.0 * COUNT(type_department) / NULLIF(COUNT(*), 0), 1) || '%)',
        '  task_status_code: ' || COUNT(task_status_code) || '/' || COUNT(*) || ' (' || ROUND(100.0 * COUNT(task_status_code) / NULLIF(COUNT(*), 0), 1) || '%)',
        '  reservation_pk: ' || COUNT(reservation_pk) || '/' || COUNT(*) || ' (' || ROUND(100.0 * COUNT(reservation_pk) / NULLIF(COUNT(*), 0), 1) || '%)'
    FROM breezeway.tasks
    WHERE synced_at > NOW() - INTERVAL '30 minutes'
    LIMIT 1;
" 2>/dev/null | tr '|' '\n'

echo ""
echo "================================================================================"
echo "Refresh: watch -n 30 /root/Breezeway/scripts/parallel_rollout_monitor.sh"
echo "================================================================================"

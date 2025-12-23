#!/bin/bash
# Real-time rollout status checker

echo "===================================================="
echo "Task ETL Rollout Status - $(TZ=America/New_York date)"
echo "===================================================="
echo ""

# Check Nashville (original)
echo "Nashville (original ETL run):"
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
SELECT '  Status: ' || sync_status || ' | Runtime: ' || 
       ROUND(EXTRACT(EPOCH FROM (NOW() - sync_started_at))/60, 1) || ' min | Records: ' || 
       records_processed || ' processed, ' || records_new || ' new, ' || records_updated || ' updated'
FROM breezeway.etl_sync_log 
WHERE region_code = 'nashville' AND entity_type = 'tasks'
ORDER BY sync_started_at DESC LIMIT 1;
" 2>/dev/null

echo ""
echo "Other Regions (rollout script):"

# Check all other regions
for region in austin smoky hilton_head breckenridge sea_ranch mammoth hill_country; do
    STATUS=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
    SELECT sync_status FROM breezeway.etl_sync_log 
    WHERE region_code = '$region' AND entity_type = 'tasks'
    ORDER BY sync_started_at DESC LIMIT 1;
    " 2>/dev/null | xargs)
    
    if [ -z "$STATUS" ]; then
        echo "  $region: Not started yet"
    elif [ "$STATUS" = "running" ]; then
        RUNTIME=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
        SELECT ROUND(EXTRACT(EPOCH FROM (NOW() - sync_started_at))/60, 1)
        FROM breezeway.etl_sync_log 
        WHERE region_code = '$region' AND entity_type = 'tasks'
        ORDER BY sync_started_at DESC LIMIT 1;
        " 2>/dev/null | xargs)
        echo "  $region: ⏳ Running ($RUNTIME min)"
    elif [ "$STATUS" = "success" ]; then
        STATS=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
        SELECT records_processed || ' processed, ' || records_new || ' new, ' || records_updated || ' updated'
        FROM breezeway.etl_sync_log 
        WHERE region_code = '$region' AND entity_type = 'tasks'
        ORDER BY sync_started_at DESC LIMIT 1;
        " 2>/dev/null | xargs)
        echo "  $region: ✓ Success ($STATS)"
    else
        echo "  $region: ✗ Failed"
    fi
done

echo ""
echo "Active ETL Processes:"
ps aux | grep "run_etl.py.*tasks" | grep -v grep | awk '{print "  " $12 " " $13 " " $14 " (PID: " $2 ")"}'

echo ""
echo "Recent Log Tail:"
tail -10 /tmp/rollout_progress.log 2>/dev/null | sed 's/^/  /'

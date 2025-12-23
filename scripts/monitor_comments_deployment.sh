#!/bin/bash
# ============================================================================
# Task Comments Deployment Monitor
# ============================================================================
# Monitors the deployment of task comments across all 8 regions

echo "========================================================================"
echo "TASK COMMENTS DEPLOYMENT - MONITORING"
echo "Started: $(date)"
echo "========================================================================"

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"

echo ""
echo "=== PROCESS STATUS ==="
for region in $REGIONS; do
    if pgrep -f "python3 etl/run_etl.py $region tasks" > /dev/null; then
        echo "✓ $region: RUNNING"
    else
        echo "✗ $region: STOPPED/COMPLETE"
    fi
done

echo ""
echo "=== TASK COMMENTS COUNT PER REGION ==="
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "
SELECT
    COALESCE(region_code, 'TOTAL') as region,
    COUNT(*) as comments
FROM breezeway.task_comments
GROUP BY ROLLUP(region_code)
ORDER BY region_code NULLS LAST;
"

echo ""
echo "=== LOG FILE SIZES ==="
ls -lh /tmp/*_tasks_with_comments.log 2>/dev/null | awk '{print $9, $5}' || echo "No log files found yet"

echo ""
echo "=== RECENT LOG ACTIVITY (Last 5 lines per region) ==="
for region in $REGIONS; do
    logfile="/tmp/${region}_tasks_with_comments.log"
    if [ -f "$logfile" ]; then
        echo ""
        echo "--- $region ---"
        tail -5 "$logfile" | grep -E "(Fetching|Transform|Load|Complete|comment)" | head -3
    fi
done

echo ""
echo "========================================================================"
echo "To see full logs: tail -f /tmp/*_tasks_with_comments.log"
echo "To check again: /root/Breezeway/scripts/monitor_comments_deployment.sh"
echo "========================================================================"

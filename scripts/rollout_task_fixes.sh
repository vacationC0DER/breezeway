#!/bin/bash
# Rollout script for task ETL fixes across all regions
# Created: 2025-11-05

LOG_DIR="/root/Breezeway/logs"
TIMESTAMP=$(TZ=America/New_York date +%Y%m%d_%H%M%S)
ROLLOUT_LOG="$LOG_DIR/rollout_task_fixes_$TIMESTAMP.log"

echo "=================================================" | tee -a "$ROLLOUT_LOG"
echo "Task ETL Fixes Rollout - Started at $(TZ=America/New_York date)" | tee -a "$ROLLOUT_LOG"
echo "=================================================" | tee -a "$ROLLOUT_LOG"
echo "" | tee -a "$ROLLOUT_LOG"

# Define all regions
REGIONS=("austin" "smoky" "hilton_head" "breckenridge" "sea_ranch" "mammoth" "hill_country")

# Track results
SUCCESSFUL=0
FAILED=0
declare -a FAILED_REGIONS

cd /root/Breezeway

for region in "${REGIONS[@]}"; do
    echo "=== Processing $region ===" | tee -a "$ROLLOUT_LOG"
    echo "Started: $(TZ=America/New_York date)" | tee -a "$ROLLOUT_LOG"
    
    # Run ETL
    if timeout 1800 python3 etl/run_etl.py "$region" tasks >> "$ROLLOUT_LOG" 2>&1; then
        echo "✓ SUCCESS: $region tasks ETL completed" | tee -a "$ROLLOUT_LOG"
        ((SUCCESSFUL++))
        
        # Quick verification
        RECORDS=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c \
            "SELECT COUNT(*) FROM breezeway.tasks WHERE region_code='$region' AND synced_at > NOW() - INTERVAL '1 hour';" 2>/dev/null | xargs)
        
        POPULATED=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c \
            "SELECT COUNT(*) FROM breezeway.tasks WHERE region_code='$region' AND type_department IS NOT NULL AND synced_at > NOW() - INTERVAL '1 hour';" 2>/dev/null | xargs)
        
        echo "  Records synced: $RECORDS" | tee -a "$ROLLOUT_LOG"
        echo "  Fields populated: $POPULATED" | tee -a "$ROLLOUT_LOG"
    else
        echo "✗ FAILED: $region tasks ETL failed" | tee -a "$ROLLOUT_LOG"
        ((FAILED++))
        FAILED_REGIONS+=("$region")
    fi
    
    echo "Completed: $(TZ=America/New_York date)" | tee -a "$ROLLOUT_LOG"
    echo "" | tee -a "$ROLLOUT_LOG"
done

# Summary
echo "=================================================" | tee -a "$ROLLOUT_LOG"
echo "Rollout Summary" | tee -a "$ROLLOUT_LOG"
echo "=================================================" | tee -a "$ROLLOUT_LOG"
echo "Successful: $SUCCESSFUL" | tee -a "$ROLLOUT_LOG"
echo "Failed: $FAILED" | tee -a "$ROLLOUT_LOG"

if [ $FAILED -gt 0 ]; then
    echo "Failed regions: ${FAILED_REGIONS[*]}" | tee -a "$ROLLOUT_LOG"
fi

echo "" | tee -a "$ROLLOUT_LOG"
echo "Completed at: $(TZ=America/New_York date)" | tee -a "$ROLLOUT_LOG"
echo "Full log: $ROLLOUT_LOG" | tee -a "$ROLLOUT_LOG"

# Generate validation report
echo "" | tee -a "$ROLLOUT_LOG"
echo "=== Field Population Report ===" | tee -a "$ROLLOUT_LOG"
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway >> "$ROLLOUT_LOG" 2>&1 << 'EOFSQL'
SELECT 
    region_code,
    COUNT(*) as total_tasks,
    COUNT(template_task_id) as has_template,
    COUNT(type_department) as has_department,
    COUNT(type_priority) as has_priority,
    COUNT(scheduled_date) as has_scheduled_date,
    COUNT(task_status_code) as has_status_code,
    COUNT(checkin_date) as has_checkin_date,
    COUNT(checkout_date) as has_checkout_date,
    COUNT(reservation_pk) as linked_to_reservation,
    MAX(synced_at) as last_synced
FROM breezeway.tasks
WHERE synced_at > NOW() - INTERVAL '2 hours'
GROUP BY region_code
ORDER BY region_code;
EOFSQL

echo "" | tee -a "$ROLLOUT_LOG"
exit $FAILED

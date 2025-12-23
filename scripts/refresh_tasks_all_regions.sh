#!/bin/bash
# Refresh tasks for all regions to populate new fields
# This will also extract task_tags and requirements

PROJECT_DIR="/root/Breezeway"
LOG_DIR="/root/Breezeway/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=========================================================================="
echo "TASKS REFRESH - ALL REGIONS"
echo "Started at: $(date)"
echo "=========================================================================="
echo ""

# All 8 regions
REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"

# Run tasks ETL for all regions in parallel
for region in $REGIONS; do
    echo "Starting: $region / tasks"
    nohup python3 $PROJECT_DIR/etl/run_etl.py $region tasks \
        > $LOG_DIR/tasks_refresh_${region}_${TIMESTAMP}.log 2>&1 &
done

echo ""
echo "All tasks ETL jobs started in background"
echo "Monitor progress with:"
echo "  tail -f $LOG_DIR/tasks_refresh_*_${TIMESTAMP}.log"
echo ""
echo "Check completion with:"
echo "  ps aux | grep 'python3.*run_etl.py.*tasks'"

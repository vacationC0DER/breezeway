#!/bin/bash
echo "Monitoring ETL completion - checking every 2 minutes"
echo "Started: $(date)"
echo ""

while true; do
    sleep 120
    
    echo "=== Status Check: $(TZ=America/New_York date) ==="
    
    # Check for completed regions
    completed=$(grep -l "Sync completed" /root/Breezeway/logs/etl_*_fixed.log 2>/dev/null | wc -l)
    echo "Completed regions: $completed / 8"
    
    # Show recently completed
    grep "Sync completed" /root/Breezeway/logs/etl_*_fixed.log 2>/dev/null | tail -3
    
    # Check running processes
    running=$(ps aux | grep "python3 etl/run_etl.py" | grep "tasks" | grep -v grep | wc -l)
    echo "Running ETL processes: $running"
    
    if [ $completed -eq 8 ]; then
        echo ""
        echo "✅ ALL REGIONS COMPLETED!"
        break
    fi
    
    echo ""
done

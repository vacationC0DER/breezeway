#!/bin/bash
echo "Monitoring Tasks ETL with Fixed Mappings - Started $(date)"
echo ""

while true; do
    sleep 120
    
    echo "=== $(TZ=America/New_York date '+%Y-%m-%d %H:%M:%S') ===" 
    
    # Check completion
    completed=$(grep -c "Sync completed" /root/Breezeway/logs/etl_*_tasks_fixed.log 2>/dev/null || echo "0")
    echo "Regions completed: $completed / 8"
    
    # Check active processes
    active=$(ps aux | grep "python3 etl/run_etl.py" | grep tasks | grep -v grep | wc -l)
    echo "Active processes: $active"
    
    echo ""
    
    if [ "$completed" -eq 8 ]; then
        echo "✅ ALL 8 REGIONS COMPLETE!"
        echo ""
        echo "Checking task_id population..."
        PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway << 'EOSQL'
SELECT 'task_assignments with task_id:' as metric, COUNT(NULLIF(task_id, '')) FROM breezeway.task_assignments
UNION ALL
SELECT 'task_photos with task_id:', COUNT(NULLIF(task_id, '')) FROM breezeway.task_photos;
EOSQL
        break
    fi
done

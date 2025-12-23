#!/bin/bash
echo "Monitoring Tasks ETL - Started $(date)"
echo ""

while true; do
    sleep 180  # Check every 3 minutes
    
    echo "=== $(TZ=America/New_York date '+%Y-%m-%d %H:%M:%S') ==="
    
    # Check completion
    completed=$(grep -c "Sync completed" /root/Breezeway/logs/etl_*_tasks_final.log 2>/dev/null || echo "0")
    echo "Regions completed: $completed / 8"
    
    # Check active processes
    active=$(ps aux | grep "python3 etl/run_etl.py" | grep tasks | grep -v grep | wc -l)
    echo "Active processes: $active / 8"
    
    # Check tasks in database
    tasks_count=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "SELECT COUNT(*) FROM breezeway.tasks;" 2>/dev/null | tr -d ' ')
    echo "Tasks in database: $tasks_count"
    
    # Check requirements in database
    req_count=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "SELECT COUNT(*) FROM breezeway.task_requirements;" 2>/dev/null | tr -d ' ')
    echo "Requirements in database: $req_count"
    
    # Check if any regions are fetching requirements (sign of progress)
    req_fetching=$(grep -c "Fetched.*requirements.*via API" /root/Breezeway/logs/etl_*_tasks_final.log 2>/dev/null || echo "0")
    if [ "$req_fetching" -gt 0 ]; then
        echo "Regions fetching requirements: $req_fetching / 8"
    fi
    
    echo ""
    
    if [ "$completed" -eq 8 ]; then
        echo "✅ ALL 8 REGIONS COMPLETE!"
        break
    fi
done

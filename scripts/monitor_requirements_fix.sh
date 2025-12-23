#!/bin/bash
echo "Monitoring Requirements Fix - Started $(date)"
echo ""

while true; do
    sleep 120
    
    echo "=== $(TZ=America/New_York date +%H:%M:%S) ==="
    
    # Check completion
    completed=$(grep -c "Sync completed" /root/Breezeway/logs/etl_*_requirements_fix.log 2>/dev/null || echo "0")
    echo "Completed: $completed / 8 regions"
    
    # Check requirements fetched
    fetched=$(grep "Fetched.*requirements.*via API" /root/Breezeway/logs/etl_*_requirements_fix.log 2>/dev/null | wc -l)
    echo "Regions that fetched requirements: $fetched / 8"
    
    # Check database count
    req_count=$(PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -t -c "SELECT COUNT(*) FROM breezeway.task_requirements;" 2>/dev/null | tr -d ' ')
    echo "Requirements in database: $req_count"
    
    echo ""
    
    if [ "$completed" -eq 8 ]; then
        echo "✅ ALL COMPLETE!"
        break
    fi
done

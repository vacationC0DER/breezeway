#!/bin/bash
echo "==================================================="
echo "Full ETL Monitoring - Started $(TZ=America/New_York date '+%Y-%m-%d %H:%M:%S')"
echo "==================================================="
echo ""

while true; do
    echo "=== $(TZ=America/New_York date '+%Y-%m-%d %H:%M:%S') ==="
    echo ""
    
    # Properties
    prop_done=$(grep -c "Sync completed" logs/etl_*_properties_active.log 2>/dev/null || echo "0")
    echo "Properties:    $prop_done / 8 complete"
    
    # Tasks  
    tasks_done=$(grep -c "Sync completed" logs/etl_*_tasks_fixed.log 2>/dev/null || echo "0")
    echo "Tasks:         $tasks_done / 8 complete"
    
    # People
    people_done=$(grep -c "Sync completed" logs/etl_*_people_full.log 2>/dev/null || echo "0")
    echo "People:        $people_done / 8 complete"
    
    # Reservations
    res_done=$(grep -c "Sync completed" logs/etl_*_reservations_full.log 2>/dev/null || echo "0")
    echo "Reservations:  $res_done / 8 complete"
    
    # Tags
    tags_done=$(grep -c "Sync completed" logs/etl_*_tags_full.log 2>/dev/null || echo "0")
    echo "Tags:          $tags_done / 8 complete"
    
    # Supplies
    sup_done=$(grep -c "Sync completed" logs/etl_*_supplies_full.log 2>/dev/null || echo "0")
    echo "Supplies:      $sup_done / 8 complete"
    
    echo ""
    total_done=$((prop_done + tasks_done + people_done + res_done + tags_done + sup_done))
    echo "Total Progress: $total_done / 48 entity-regions complete"
    
    # Active processes
    active=$(ps aux | grep "python3 etl/run_etl.py" | grep -v grep | wc -l)
    echo "Active ETL processes: $active"
    
    echo ""
    
    if [ "$total_done" -eq 48 ]; then
        echo "========================================="
        echo "✅ ALL ETL PROCESSES COMPLETE!"
        echo "========================================="
        break
    fi
    
    sleep 60
done

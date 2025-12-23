#!/bin/bash
# ============================================================================
# ETL Log Monitoring Script
# ============================================================================
# Usage: ./check_etl_logs.sh [hourly|daily|all]
# Shows recent ETL runs and status

LOG_DIR="/root/Breezeway/logs"

show_hourly() {
    echo "=========================================================================="
    echo "HOURLY ETL LOGS (Properties & Reservations)"
    echo "=========================================================================="

    latest_hourly=$(ls -t "$LOG_DIR"/hourly_etl_*.log 2>/dev/null | head -1)

    if [ -n "$latest_hourly" ]; then
        echo "Latest log: $latest_hourly"
        echo ""
        echo "Last 30 lines:"
        tail -30 "$latest_hourly"
        echo ""
        echo "Success count:"
        grep -c "✓ SUCCESS" "$latest_hourly" || echo "0"
        echo "Failure count:"
        grep -c "✗ FAILED" "$latest_hourly" || echo "0"
    else
        echo "No hourly logs found"
    fi
}

show_daily() {
    echo "=========================================================================="
    echo "DAILY ETL LOGS (Tasks)"
    echo "=========================================================================="

    latest_daily=$(ls -t "$LOG_DIR"/daily_etl_*.log 2>/dev/null | head -1)

    if [ -n "$latest_daily" ]; then
        echo "Latest log: $latest_daily"
        echo ""
        echo "Last 30 lines:"
        tail -30 "$latest_daily"
        echo ""
        echo "Success count:"
        grep -c "✓ SUCCESS" "$latest_daily" || echo "0"
        echo "Failure count:"
        grep -c "✗ FAILED" "$latest_daily" || echo "0"
    else
        echo "No daily logs found"
    fi
}

show_cron() {
    echo "=========================================================================="
    echo "CRON EXECUTION LOGS"
    echo "=========================================================================="

    if [ -f "$LOG_DIR/cron_hourly.log" ]; then
        echo "Hourly cron log (last 20 lines):"
        tail -20 "$LOG_DIR/cron_hourly.log"
        echo ""
    fi

    if [ -f "$LOG_DIR/cron_daily.log" ]; then
        echo "Daily cron log (last 20 lines):"
        tail -20 "$LOG_DIR/cron_daily.log"
        echo ""
    fi
}

show_summary() {
    echo "=========================================================================="
    echo "ETL SUMMARY - TODAY"
    echo "=========================================================================="

    TODAY=$(date +%Y%m%d)

    echo "Hourly ETL runs today:"
    if [ -f "$LOG_DIR/hourly_etl_${TODAY}.log" ]; then
        grep -c "HOURLY ETL START" "$LOG_DIR/hourly_etl_${TODAY}.log" || echo "0"
    else
        echo "0"
    fi

    echo "Daily ETL runs today:"
    if [ -f "$LOG_DIR/daily_etl_${TODAY}.log" ]; then
        grep -c "DAILY ETL START" "$LOG_DIR/daily_etl_${TODAY}.log" || echo "0"
    else
        echo "0"
    fi

    echo ""
    echo "Log files:"
    ls -lh "$LOG_DIR"/*.log 2>/dev/null | tail -10 || echo "No logs found"
}

case "${1:-all}" in
    hourly)
        show_hourly
        ;;
    daily)
        show_daily
        ;;
    cron)
        show_cron
        ;;
    summary)
        show_summary
        ;;
    all)
        show_summary
        echo ""
        show_hourly
        echo ""
        show_daily
        echo ""
        show_cron
        ;;
    *)
        echo "Usage: $0 [hourly|daily|cron|summary|all]"
        exit 1
        ;;
esac

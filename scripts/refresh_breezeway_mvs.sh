#!/bin/bash
# Refresh all materialized views in breezeway.* schema.
# Added 2026-05-13: previously no automated refresh was wired up.
# Non-concurrent because none of the MVs have unique indexes; all are <1MB so brief AccessExclusive is acceptable.

LOG_FILE="/root/Breezeway/logs/mv_refresh.log"
START=$(date +%s)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] MV refresh starting" >> "$LOG_FILE"

sudo -u postgres psql -d breezeway -v ON_ERROR_STOP=0 <<'SQL' 2>>"$LOG_FILE"
\timing on
REFRESH MATERIALIZED VIEW breezeway.mv_daily_turnover_board;
REFRESH MATERIALIZED VIEW breezeway.mv_department_sla_tracker;
REFRESH MATERIALIZED VIEW breezeway.mv_housekeeping_schedule_performance;
REFRESH MATERIALIZED VIEW breezeway.mv_inspection_compliance;
REFRESH MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_operational_alerts;
REFRESH MATERIALIZED VIEW breezeway.mv_priority_response_times;
REFRESH MATERIALIZED VIEW breezeway.mv_property_dashboard;
REFRESH MATERIALIZED VIEW breezeway.mv_regional_dashboard;
REFRESH MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_seasonal_demand_patterns;
REFRESH MATERIALIZED VIEW breezeway.mv_task_completion_metrics;
REFRESH MATERIALIZED VIEW breezeway.mv_task_tags_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_efficiency_ranking;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_housekeeping;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_inspection;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_maintenance;
SQL

DURATION=$(($(date +%s) - START))
echo "[$(date '+%Y-%m-%d %H:%M:%S')] MV refresh complete (${DURATION}s)" >> "$LOG_FILE"

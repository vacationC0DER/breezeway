-- ============================================================================
-- Migration 026: Replace DATE_TRUNC/DATE with time_bucket() in Views
-- Date: 2026-03-02
-- Purpose: Phase 2 of TimescaleDB integration
--   Drop-in replacement of DATE_TRUNC/DATE grouping with time_bucket()
--   in materialized view definitions.
--
-- Views recreated:
--   1. mv_reservation_turnaround_analysis  (DATE_TRUNC('week') → time_bucket)
--   2. mv_monthly_trend_analysis           (DATE_TRUNC('month') → time_bucket)
--   3. mv_weekly_operational_snapshot       (DATE_TRUNC('week') → time_bucket)
--   4. mv_regional_dashboard               (DATE() → time_bucket in daily_tasks CTE)
--
-- Requires: Migration 025 (timescaledb extension)
--
-- Verification:
--   After running, execute: SELECT breezeway.refresh_dashboard_views();
--   Compare row counts to pre-migration values.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. mv_reservation_turnaround_analysis
--    DATE_TRUNC('week', checkout_date) → time_bucket('1 week', checkout_date)
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_reservation_turnaround_analysis CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis AS
SELECT
    r.region_code,
    time_bucket('1 week', r.checkout_date)::date as week_of,

    -- Reservation Volume
    COUNT(DISTINCT r.id) as reservations,

    -- Tasks linked to reservations
    COUNT(t.id) as linked_tasks,
    COUNT(CASE WHEN t.type_department = 'housekeeping' THEN 1 END) as housekeeping_tasks,
    COUNT(CASE WHEN t.type_department = 'inspection' THEN 1 END) as inspection_tasks,

    -- Completion before next check-in
    COUNT(CASE WHEN t.task_status_stage = 'finished' THEN 1 END) as completed_tasks,
    ROUND(COUNT(CASE WHEN t.task_status_stage = 'finished' THEN 1 END)::numeric /
          NULLIF(COUNT(t.id), 0) * 100, 1) as task_completion_rate,

    -- Average turnaround
    ROUND(AVG(CASE WHEN t.task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at))/3600 END)::numeric, 1) as avg_hours_turnaround,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.reservations r
LEFT JOIN breezeway.tasks t ON t.reservation_pk = r.id
WHERE r.reservation_status = 'active'
  AND r.checkout_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY r.region_code, time_bucket('1 week', r.checkout_date)
ORDER BY r.region_code, week_of DESC
WITH NO DATA;


-- ============================================================================
-- 2. mv_monthly_trend_analysis
--    DATE_TRUNC('month', created_at) → time_bucket('1 month', created_at)
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_monthly_trend_analysis CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis AS
SELECT
    time_bucket('1 month', created_at)::date as month,
    region_code,
    type_department,

    -- Volume
    COUNT(*) as tasks_created,
    COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) as tasks_completed,

    -- Completion Rate
    ROUND(COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END)::numeric /
          NULLIF(COUNT(*), 0) * 100, 1) as completion_rate,

    -- Timing
    ROUND(AVG(CASE WHEN task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END)::numeric, 1) as avg_hours_to_complete,

    -- Priority Distribution
    COUNT(CASE WHEN type_priority = 'urgent' THEN 1 END) as urgent_tasks,
    COUNT(CASE WHEN type_priority = 'high' THEN 1 END) as high_priority_tasks,

    -- Workers
    COUNT(DISTINCT finished_by_id) as unique_workers,

    -- Month-over-Month Change
    LAG(COUNT(*)) OVER (PARTITION BY region_code, type_department ORDER BY time_bucket('1 month', created_at)) as prev_month_tasks,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE created_at >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY time_bucket('1 month', created_at), region_code, type_department
ORDER BY month DESC, region_code, type_department
WITH NO DATA;


-- ============================================================================
-- 3. mv_weekly_operational_snapshot
--    DATE_TRUNC('week', CURRENT_DATE) → time_bucket('1 week', CURRENT_DATE)
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_weekly_operational_snapshot CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot AS
SELECT
    time_bucket('1 week', CURRENT_DATE)::date as week_start,
    region_code,

    -- This Week's Volume
    COUNT(CASE WHEN created_at >= time_bucket('1 week', CURRENT_DATE) THEN 1 END) as tasks_created_this_week,
    COUNT(CASE WHEN finished_at >= time_bucket('1 week', CURRENT_DATE) THEN 1 END) as tasks_completed_this_week,

    -- Last Week's Volume (for comparison)
    COUNT(CASE WHEN created_at >= time_bucket('1 week', CURRENT_DATE) - INTERVAL '7 days'
               AND created_at < time_bucket('1 week', CURRENT_DATE) THEN 1 END) as tasks_created_last_week,
    COUNT(CASE WHEN finished_at >= time_bucket('1 week', CURRENT_DATE) - INTERVAL '7 days'
               AND finished_at < time_bucket('1 week', CURRENT_DATE) THEN 1 END) as tasks_completed_last_week,

    -- Current Backlog
    COUNT(CASE WHEN task_status_stage IN ('new', 'in_progress') THEN 1 END) as current_backlog,

    -- Urgency
    COUNT(CASE WHEN task_status_stage IN ('new', 'in_progress')
               AND type_priority IN ('urgent', 'high') THEN 1 END) as urgent_high_backlog,

    -- Department Breakdown This Week
    COUNT(CASE WHEN type_department = 'housekeeping'
               AND created_at >= time_bucket('1 week', CURRENT_DATE) THEN 1 END) as housekeeping_this_week,
    COUNT(CASE WHEN type_department = 'inspection'
               AND created_at >= time_bucket('1 week', CURRENT_DATE) THEN 1 END) as inspection_this_week,
    COUNT(CASE WHEN type_department = 'maintenance'
               AND created_at >= time_bucket('1 week', CURRENT_DATE) THEN 1 END) as maintenance_this_week,

    -- Active Workers This Week
    COUNT(DISTINCT CASE WHEN finished_at >= time_bucket('1 week', CURRENT_DATE)
                        THEN finished_by_id END) as active_workers_this_week,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code
WITH NO DATA;


-- ============================================================================
-- 4. mv_regional_dashboard (from migration 024)
--    DATE(created_at) → time_bucket('1 day', created_at)::date in daily_tasks CTE
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_regional_dashboard CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_regional_dashboard AS
WITH regional_tasks AS (
    SELECT
        t.region_code,
        COUNT(*) AS total_tasks,
        COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) AS completed_tasks,
        COUNT(CASE WHEN task_status_stage = 'new' THEN 1 END) AS backlog,
        COUNT(CASE WHEN task_status_stage = 'in_progress' THEN 1 END) AS in_progress,
        AVG(CASE WHEN task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (finished_at - created_at)) / 3600 END)::numeric(10,1) AS avg_hours_to_complete,
        AVG(CASE WHEN task_status_stage = 'finished' AND started_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (finished_at - started_at)) / 60 END)::numeric(10,1) AS avg_minutes_active_work,
        COUNT(DISTINCT finished_by_id) AS unique_workers
    FROM breezeway.tasks t
    WHERE t.created_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY t.region_code
),
regional_properties AS (
    SELECT
        region_code,
        COUNT(*) AS property_count
    FROM breezeway.properties
    WHERE property_status = 'active'
    GROUP BY region_code
),
regional_reservations AS (
    SELECT
        region_code,
        COUNT(*) AS active_reservations,
        COUNT(CASE WHEN checkin_date >= CURRENT_DATE THEN 1 END) AS upcoming_reservations
    FROM breezeway.reservations
    WHERE reservation_status = 'active'
    GROUP BY region_code
),
-- Workload distribution (30-day daily averages) - using time_bucket
daily_tasks AS (
    SELECT
        region_code,
        time_bucket('1 day', created_at)::date AS task_date,
        COUNT(*) AS tasks_created,
        COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) AS tasks_completed
    FROM breezeway.tasks
    WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY region_code, time_bucket('1 day', created_at)
),
workload_stats AS (
    SELECT
        region_code,
        ROUND(AVG(tasks_created)::numeric, 1) AS avg_daily_tasks_created,
        ROUND(AVG(tasks_completed)::numeric, 1) AS avg_daily_tasks_completed,
        MAX(tasks_created) AS peak_daily_tasks,
        ROUND(STDDEV(tasks_created)::numeric, 1) AS stddev_daily_tasks,
        (SELECT task_date FROM daily_tasks dt2
         WHERE dt2.region_code = dt.region_code
         ORDER BY tasks_created DESC LIMIT 1) AS busiest_day
    FROM daily_tasks dt
    GROUP BY region_code
),
-- Backlog aging (folded from mv_task_backlog_aging, aggregated per region)
backlog_aging AS (
    SELECT
        region_code,
        COUNT(CASE WHEN CURRENT_DATE - created_at::date <= 1 THEN 1 END) AS backlog_age_0_1d,
        COUNT(CASE WHEN CURRENT_DATE - created_at::date BETWEEN 2 AND 3 THEN 1 END) AS backlog_age_2_3d,
        COUNT(CASE WHEN CURRENT_DATE - created_at::date BETWEEN 4 AND 7 THEN 1 END) AS backlog_age_4_7d,
        COUNT(CASE WHEN CURRENT_DATE - created_at::date BETWEEN 8 AND 14 THEN 1 END) AS backlog_age_8_14d,
        COUNT(CASE WHEN CURRENT_DATE - created_at::date BETWEEN 15 AND 30 THEN 1 END) AS backlog_age_15_30d,
        COUNT(CASE WHEN CURRENT_DATE - created_at::date > 30 THEN 1 END) AS backlog_age_over_30d,
        COUNT(*) AS total_backlog_tasks,
        ROUND(AVG(CURRENT_DATE - created_at::date)::numeric, 1) AS avg_backlog_age_days,
        MAX(CURRENT_DATE - created_at::date) AS max_backlog_age_days,
        MIN(created_at) AS oldest_backlog_task_created
    FROM breezeway.tasks
    WHERE task_status_stage IN ('new', 'in_progress')
    GROUP BY region_code
)
SELECT
    r.region_code,
    r.region_name,

    -- Performance scorecard
    COALESCE(rp.property_count, 0) AS properties,
    COALESCE(rt.total_tasks, 0) AS tasks_90d,
    COALESCE(rt.completed_tasks, 0) AS completed_90d,
    COALESCE(rt.backlog, 0) AS current_backlog,
    COALESCE(rt.in_progress, 0) AS in_progress,
    ROUND(COALESCE(rt.completed_tasks, 0)::numeric / NULLIF(COALESCE(rt.total_tasks, 0), 0) * 100, 1) AS completion_rate_pct,
    rt.avg_hours_to_complete,
    rt.avg_minutes_active_work,
    COALESCE(rt.unique_workers, 0) AS active_workers,
    COALESCE(rr.active_reservations, 0) AS reservations,
    COALESCE(rr.upcoming_reservations, 0) AS upcoming_reservations,
    ROUND(COALESCE(rt.total_tasks, 0)::numeric / NULLIF(COALESCE(rp.property_count, 0), 0), 1) AS tasks_per_property_90d,

    -- Workload distribution (30d)
    COALESCE(ws.avg_daily_tasks_created, 0) AS avg_daily_tasks_created,
    COALESCE(ws.avg_daily_tasks_completed, 0) AS avg_daily_tasks_completed,
    COALESCE(ws.peak_daily_tasks, 0) AS peak_daily_tasks,
    ws.stddev_daily_tasks,
    ws.busiest_day,
    ROUND(COALESCE(ws.avg_daily_tasks_created, 0)::numeric /
          NULLIF(COALESCE(rp.property_count, 0), 0), 2) AS tasks_per_property_per_day,
    ROUND(COALESCE(ws.avg_daily_tasks_created, 0)::numeric /
          NULLIF(COALESCE(rt.unique_workers, 0), 0), 2) AS tasks_per_worker_per_day,

    -- Backlog aging buckets
    COALESCE(ba.backlog_age_0_1d, 0) AS backlog_age_0_1d,
    COALESCE(ba.backlog_age_2_3d, 0) AS backlog_age_2_3d,
    COALESCE(ba.backlog_age_4_7d, 0) AS backlog_age_4_7d,
    COALESCE(ba.backlog_age_8_14d, 0) AS backlog_age_8_14d,
    COALESCE(ba.backlog_age_15_30d, 0) AS backlog_age_15_30d,
    COALESCE(ba.backlog_age_over_30d, 0) AS backlog_age_over_30d,
    COALESCE(ba.total_backlog_tasks, 0) AS total_backlog_tasks,
    ba.avg_backlog_age_days,
    ba.max_backlog_age_days,
    ba.oldest_backlog_task_created,

    CURRENT_TIMESTAMP AS refreshed_at
FROM breezeway.regions r
LEFT JOIN regional_tasks rt ON r.region_code = rt.region_code
LEFT JOIN regional_properties rp ON r.region_code = rp.region_code
LEFT JOIN regional_reservations rr ON r.region_code = rr.region_code
LEFT JOIN workload_stats ws ON r.region_code = ws.region_code
LEFT JOIN backlog_aging ba ON r.region_code = ba.region_code
WHERE r.is_active = true
ORDER BY rt.total_tasks DESC NULLS LAST
WITH NO DATA;


-- ============================================================================
-- Refresh recreated views
-- ============================================================================
REFRESH MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;
REFRESH MATERIALIZED VIEW breezeway.mv_regional_dashboard;


-- ============================================================================
-- Recreate indexes on recreated views
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_mv_monthly_trend_month ON breezeway.mv_monthly_trend_analysis(month DESC);
CREATE INDEX IF NOT EXISTS idx_mv_regional_dashboard_region ON breezeway.mv_regional_dashboard(region_code);


-- ============================================================================
-- Re-grant permissions
-- ============================================================================
GRANT SELECT ON breezeway.mv_reservation_turnaround_analysis TO breezeway;
GRANT SELECT ON breezeway.mv_monthly_trend_analysis TO breezeway;
GRANT SELECT ON breezeway.mv_weekly_operational_snapshot TO breezeway;
GRANT SELECT ON breezeway.mv_regional_dashboard TO breezeway;

COMMIT;

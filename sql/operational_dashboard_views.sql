-- ============================================================================
-- BREEZEWAY OPERATIONAL DASHBOARD MATERIALIZED VIEWS
-- Created: 2025-12-17
-- Purpose: Top 20 operational analytics views for portfolio management
-- ============================================================================

-- Drop existing views if they exist
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_portfolio_executive_summary CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_regional_performance_scorecard CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_worker_leaderboard_housekeeping CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_worker_leaderboard_inspection CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_worker_leaderboard_maintenance CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_task_completion_metrics CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_task_backlog_aging CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_task_density CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_operational_health CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_reservation_turnaround_analysis CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_monthly_trend_analysis CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_weekly_operational_snapshot CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_priority_response_times CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_task_tags_analysis CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_worker_efficiency_ranking CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_regional_workload_distribution CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_seasonal_demand_patterns CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_maintenance_burden CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_data_quality_scorecard CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_operational_alerts CASCADE;


-- ============================================================================
-- VIEW 1: PORTFOLIO EXECUTIVE SUMMARY
-- Purpose: C-level overview of entire portfolio health
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_portfolio_executive_summary AS
SELECT
    -- Portfolio Size
    (SELECT COUNT(*) FROM breezeway.properties WHERE property_status = 'active') as total_properties,
    (SELECT COUNT(*) FROM breezeway.regions WHERE is_active = true) as total_regions,
    (SELECT COUNT(DISTINCT finished_by_id) FROM breezeway.tasks WHERE finished_by_id IS NOT NULL) as total_active_workers,

    -- Task Volume (Last 30 Days)
    (SELECT COUNT(*) FROM breezeway.tasks WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') as tasks_last_30_days,
    (SELECT COUNT(*) FROM breezeway.tasks WHERE task_status_stage = 'finished' AND finished_at >= CURRENT_DATE - INTERVAL '30 days') as completed_last_30_days,
    (SELECT COUNT(*) FROM breezeway.tasks WHERE task_status_stage = 'new') as current_backlog,
    (SELECT COUNT(*) FROM breezeway.tasks WHERE task_status_stage = 'in_progress') as in_progress,

    -- Completion Rate
    ROUND(
        (SELECT COUNT(*)::numeric FROM breezeway.tasks WHERE task_status_stage = 'finished' AND finished_at >= CURRENT_DATE - INTERVAL '30 days') /
        NULLIF((SELECT COUNT(*)::numeric FROM breezeway.tasks WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'), 0) * 100, 1
    ) as completion_rate_30d_pct,

    -- Average Turnaround (Hours)
    ROUND(
        (SELECT AVG(EXTRACT(EPOCH FROM (finished_at - created_at))/3600)::numeric
         FROM breezeway.tasks
         WHERE task_status_stage = 'finished' AND finished_at >= CURRENT_DATE - INTERVAL '30 days'), 1
    ) as avg_turnaround_hours_30d,

    -- Reservation Coverage
    (SELECT COUNT(*) FROM breezeway.reservations WHERE reservation_status = 'active' AND checkin_date >= CURRENT_DATE) as upcoming_reservations,
    (SELECT COUNT(*) FROM breezeway.reservations WHERE reservation_status = 'active' AND checkin_date = CURRENT_DATE) as checkins_today,
    (SELECT COUNT(*) FROM breezeway.reservations WHERE reservation_status = 'active' AND checkout_date = CURRENT_DATE) as checkouts_today,

    -- Department Breakdown
    (SELECT COUNT(*) FROM breezeway.tasks WHERE type_department = 'housekeeping' AND task_status_stage = 'new') as housekeeping_backlog,
    (SELECT COUNT(*) FROM breezeway.tasks WHERE type_department = 'inspection' AND task_status_stage = 'new') as inspection_backlog,
    (SELECT COUNT(*) FROM breezeway.tasks WHERE type_department = 'maintenance' AND task_status_stage = 'new') as maintenance_backlog,

    CURRENT_TIMESTAMP as refreshed_at
WITH NO DATA;


-- ============================================================================
-- VIEW 2: REGIONAL PERFORMANCE SCORECARD
-- Purpose: Compare operational metrics across all 8 regions
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_regional_performance_scorecard AS
WITH regional_tasks AS (
    SELECT
        t.region_code,
        COUNT(*) as total_tasks,
        COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) as completed_tasks,
        COUNT(CASE WHEN task_status_stage = 'new' THEN 1 END) as backlog,
        COUNT(CASE WHEN task_status_stage = 'in_progress' THEN 1 END) as in_progress,
        AVG(CASE WHEN task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END)::numeric(10,1) as avg_hours_to_complete,
        AVG(CASE WHEN task_status_stage = 'finished' AND started_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (finished_at - started_at))/60 END)::numeric(10,1) as avg_minutes_active_work,
        COUNT(DISTINCT finished_by_id) as unique_workers
    FROM breezeway.tasks t
    WHERE t.created_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY t.region_code
),
regional_properties AS (
    SELECT
        region_code,
        COUNT(*) as property_count
    FROM breezeway.properties
    WHERE property_status = 'active'
    GROUP BY region_code
),
regional_reservations AS (
    SELECT
        region_code,
        COUNT(*) as active_reservations,
        COUNT(CASE WHEN checkin_date >= CURRENT_DATE THEN 1 END) as upcoming_reservations
    FROM breezeway.reservations
    WHERE reservation_status = 'active'
    GROUP BY region_code
)
SELECT
    r.region_code,
    r.region_name,
    COALESCE(rp.property_count, 0) as properties,
    COALESCE(rt.total_tasks, 0) as tasks_90d,
    COALESCE(rt.completed_tasks, 0) as completed_90d,
    COALESCE(rt.backlog, 0) as current_backlog,
    ROUND(COALESCE(rt.completed_tasks, 0)::numeric / NULLIF(COALESCE(rt.total_tasks, 0), 0) * 100, 1) as completion_rate_pct,
    rt.avg_hours_to_complete,
    rt.avg_minutes_active_work,
    COALESCE(rt.unique_workers, 0) as active_workers,
    COALESCE(rr.active_reservations, 0) as reservations,
    COALESCE(rr.upcoming_reservations, 0) as upcoming_reservations,
    ROUND(COALESCE(rt.total_tasks, 0)::numeric / NULLIF(COALESCE(rp.property_count, 0), 0), 1) as tasks_per_property_90d,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.regions r
LEFT JOIN regional_tasks rt ON r.region_code = rt.region_code
LEFT JOIN regional_properties rp ON r.region_code = rp.region_code
LEFT JOIN regional_reservations rr ON r.region_code = rr.region_code
WHERE r.is_active = true
ORDER BY rt.total_tasks DESC NULLS LAST
WITH NO DATA;


-- ============================================================================
-- VIEW 3: WORKER LEADERBOARD - HOUSEKEEPING (Best Cleaners)
-- Purpose: Rank housekeeping staff by volume, speed, and efficiency
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_worker_leaderboard_housekeeping AS
SELECT
    finished_by_name as worker_name,
    finished_by_id as worker_id,
    region_code,
    COUNT(*) as tasks_completed_90d,
    COUNT(CASE WHEN finished_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as tasks_completed_30d,
    COUNT(CASE WHEN finished_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as tasks_completed_7d,

    -- Speed Metrics
    ROUND(AVG(EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as avg_minutes_active,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as median_minutes_active,
    ROUND(AVG(EXTRACT(EPOCH FROM (finished_at - created_at))/3600)::numeric, 1) as avg_hours_total_turnaround,

    -- Consistency (Std Dev of completion time)
    ROUND(STDDEV(EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as stddev_minutes_active,

    -- First and last task dates
    MIN(finished_at)::date as first_task_date,
    MAX(finished_at)::date as last_task_date,

    -- Activity span
    (MAX(finished_at)::date - MIN(finished_at)::date) as active_days_span,

    -- Tasks per active day (productivity)
    ROUND(COUNT(*)::numeric / NULLIF(GREATEST((MAX(finished_at)::date - MIN(finished_at)::date), 1), 0), 2) as tasks_per_day,

    -- Rank
    DENSE_RANK() OVER (PARTITION BY region_code ORDER BY COUNT(*) DESC) as regional_rank,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as global_rank,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE
    type_department = 'housekeeping'
    AND task_status_stage = 'finished'
    AND finished_by_name IS NOT NULL
    AND finished_by_name != ''
    AND finished_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY finished_by_name, finished_by_id, region_code
HAVING COUNT(*) >= 5  -- Minimum 5 tasks to be ranked
ORDER BY tasks_completed_90d DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 4: WORKER LEADERBOARD - INSPECTION (Best Inspectors)
-- Purpose: Rank inspection staff by volume, thoroughness, and speed
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_worker_leaderboard_inspection AS
SELECT
    finished_by_name as worker_name,
    finished_by_id as worker_id,
    region_code,
    COUNT(*) as tasks_completed_90d,
    COUNT(CASE WHEN finished_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as tasks_completed_30d,
    COUNT(CASE WHEN finished_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as tasks_completed_7d,

    -- Speed Metrics
    ROUND(AVG(EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as avg_minutes_active,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as median_minutes_active,
    ROUND(AVG(EXTRACT(EPOCH FROM (finished_at - created_at))/3600)::numeric, 1) as avg_hours_total_turnaround,

    -- Consistency
    ROUND(STDDEV(EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as stddev_minutes_active,

    -- Dates
    MIN(finished_at)::date as first_task_date,
    MAX(finished_at)::date as last_task_date,
    (MAX(finished_at)::date - MIN(finished_at)::date) as active_days_span,
    ROUND(COUNT(*)::numeric / NULLIF(GREATEST((MAX(finished_at)::date - MIN(finished_at)::date), 1), 0), 2) as tasks_per_day,

    -- Rank
    DENSE_RANK() OVER (PARTITION BY region_code ORDER BY COUNT(*) DESC) as regional_rank,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as global_rank,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE
    type_department = 'inspection'
    AND task_status_stage = 'finished'
    AND finished_by_name IS NOT NULL
    AND finished_by_name != ''
    AND finished_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY finished_by_name, finished_by_id, region_code
HAVING COUNT(*) >= 5
ORDER BY tasks_completed_90d DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 5: WORKER LEADERBOARD - MAINTENANCE
-- Purpose: Rank maintenance staff by volume, complexity handling, and response
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_worker_leaderboard_maintenance AS
SELECT
    finished_by_name as worker_name,
    finished_by_id as worker_id,
    region_code,
    COUNT(*) as tasks_completed_90d,
    COUNT(CASE WHEN finished_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as tasks_completed_30d,
    COUNT(CASE WHEN finished_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as tasks_completed_7d,

    -- Priority Breakdown
    COUNT(CASE WHEN type_priority = 'urgent' THEN 1 END) as urgent_tasks_90d,
    COUNT(CASE WHEN type_priority = 'high' THEN 1 END) as high_priority_tasks_90d,
    COUNT(CASE WHEN type_priority = 'normal' THEN 1 END) as normal_tasks_90d,

    -- Speed Metrics
    ROUND(AVG(EXTRACT(EPOCH FROM (finished_at - started_at))/60)::numeric, 1) as avg_minutes_active,
    ROUND(AVG(EXTRACT(EPOCH FROM (finished_at - created_at))/3600)::numeric, 1) as avg_hours_total_turnaround,

    -- Urgent Response Time (Hours from creation to finish for urgent tasks)
    ROUND(AVG(CASE WHEN type_priority = 'urgent'
        THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END)::numeric, 1) as avg_urgent_response_hours,

    -- Activity
    MIN(finished_at)::date as first_task_date,
    MAX(finished_at)::date as last_task_date,
    ROUND(COUNT(*)::numeric / NULLIF(GREATEST((MAX(finished_at)::date - MIN(finished_at)::date), 1), 0), 2) as tasks_per_day,

    -- Rank
    DENSE_RANK() OVER (PARTITION BY region_code ORDER BY COUNT(*) DESC) as regional_rank,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as global_rank,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE
    type_department = 'maintenance'
    AND task_status_stage = 'finished'
    AND finished_by_name IS NOT NULL
    AND finished_by_name != ''
    AND finished_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY finished_by_name, finished_by_id, region_code
HAVING COUNT(*) >= 5
ORDER BY tasks_completed_90d DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 6: TASK COMPLETION METRICS BY DEPARTMENT
-- Purpose: Detailed completion statistics segmented by department
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_task_completion_metrics AS
SELECT
    region_code,
    type_department,

    -- Volume
    COUNT(*) as total_tasks_90d,
    COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) as completed_90d,
    COUNT(CASE WHEN task_status_stage = 'new' THEN 1 END) as pending,
    COUNT(CASE WHEN task_status_stage = 'in_progress' THEN 1 END) as in_progress,

    -- Completion Rate
    ROUND(COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END)::numeric /
          NULLIF(COUNT(*), 0) * 100, 1) as completion_rate_pct,

    -- Timing Metrics (for completed tasks)
    ROUND(AVG(CASE WHEN task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END)::numeric, 1) as avg_hours_to_complete,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY CASE WHEN task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END
    )::numeric, 1) as median_hours_to_complete,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY CASE WHEN task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END
    )::numeric, 1) as p90_hours_to_complete,

    -- Active Work Time
    ROUND(AVG(CASE WHEN task_status_stage = 'finished' AND started_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (finished_at - started_at))/60 END)::numeric, 1) as avg_minutes_active_work,

    -- Same Day Completion
    COUNT(CASE WHEN task_status_stage = 'finished'
        AND DATE(finished_at) = DATE(created_at) THEN 1 END) as same_day_completions,
    ROUND(COUNT(CASE WHEN task_status_stage = 'finished'
        AND DATE(finished_at) = DATE(created_at) THEN 1 END)::numeric /
        NULLIF(COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END), 0) * 100, 1) as same_day_rate_pct,

    -- Workers
    COUNT(DISTINCT finished_by_id) as unique_workers,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY region_code, type_department
ORDER BY region_code, type_department
WITH NO DATA;


-- ============================================================================
-- VIEW 7: TASK BACKLOG AGING ANALYSIS
-- Purpose: Identify stale tasks and aging distribution
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_task_backlog_aging AS
SELECT
    region_code,
    type_department,
    type_priority,

    -- Aging Buckets
    COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) <= 1 THEN 1 END) as age_0_1_days,
    COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 2 AND 3 THEN 1 END) as age_2_3_days,
    COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 4 AND 7 THEN 1 END) as age_4_7_days,
    COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 8 AND 14 THEN 1 END) as age_8_14_days,
    COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 15 AND 30 THEN 1 END) as age_15_30_days,
    COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) > 30 THEN 1 END) as age_over_30_days,

    -- Total Backlog
    COUNT(*) as total_backlog,

    -- Average Age
    ROUND(AVG(CURRENT_DATE - DATE(created_at))::numeric, 1) as avg_age_days,
    MAX(CURRENT_DATE - DATE(created_at)) as max_age_days,

    -- Oldest Task
    MIN(created_at) as oldest_task_created,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE task_status_stage IN ('new', 'in_progress')
GROUP BY region_code, type_department, type_priority
ORDER BY region_code, type_department,
    CASE type_priority
        WHEN 'urgent' THEN 1
        WHEN 'high' THEN 2
        WHEN 'normal' THEN 3
        WHEN 'watch' THEN 4
        WHEN 'low' THEN 5
        ELSE 6
    END
WITH NO DATA;


-- ============================================================================
-- VIEW 8: PROPERTY TASK DENSITY
-- Purpose: Identify properties with high task volume (problem properties)
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_property_task_density AS
SELECT
    p.id as property_pk,
    p.property_id,
    p.property_name,
    p.region_code,
    p.property_city,

    -- Task Counts
    COUNT(t.id) as total_tasks_all_time,
    COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as tasks_90d,
    COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as tasks_30d,
    COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as tasks_7d,

    -- Department Breakdown
    COUNT(CASE WHEN t.type_department = 'maintenance' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as maintenance_tasks_90d,
    COUNT(CASE WHEN t.type_department = 'housekeeping' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as housekeeping_tasks_90d,
    COUNT(CASE WHEN t.type_department = 'inspection' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as inspection_tasks_90d,

    -- Priority Breakdown
    COUNT(CASE WHEN t.type_priority IN ('urgent', 'high') AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as urgent_high_tasks_90d,

    -- Current Backlog
    COUNT(CASE WHEN t.task_status_stage IN ('new', 'in_progress') THEN 1 END) as current_backlog,

    -- Completion Metrics
    ROUND(AVG(CASE WHEN t.task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at))/3600 END)::numeric, 1) as avg_hours_to_complete,

    -- Reservation Link
    (SELECT COUNT(*) FROM breezeway.reservations r
     WHERE r.property_pk = p.id AND r.reservation_status = 'active') as active_reservations,

    -- Rank by Task Volume
    DENSE_RANK() OVER (PARTITION BY p.region_code ORDER BY COUNT(t.id) DESC) as regional_task_rank,
    DENSE_RANK() OVER (ORDER BY COUNT(t.id) DESC) as global_task_rank,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.properties p
LEFT JOIN breezeway.tasks t ON t.property_pk = p.id
WHERE p.property_status = 'active'
GROUP BY p.id, p.property_id, p.property_name, p.region_code, p.property_city
ORDER BY total_tasks_all_time DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 9: PROPERTY OPERATIONAL HEALTH SCORE
-- Purpose: Composite health score for each property
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_property_operational_health AS
WITH property_metrics AS (
    SELECT
        p.id as property_pk,
        p.property_id,
        p.property_name,
        p.region_code,

        -- Task metrics
        COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as tasks_90d,
        COUNT(CASE WHEN t.task_status_stage IN ('new', 'in_progress') THEN 1 END) as backlog,
        COUNT(CASE WHEN t.type_priority IN ('urgent', 'high') AND t.task_status_stage IN ('new', 'in_progress') THEN 1 END) as urgent_backlog,

        -- Completion rate
        ROUND(COUNT(CASE WHEN t.task_status_stage = 'finished' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END)::numeric /
              NULLIF(COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END), 0) * 100, 1) as completion_rate,

        -- Average turnaround
        AVG(CASE WHEN t.task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at))/3600 END) as avg_turnaround_hours
    FROM breezeway.properties p
    LEFT JOIN breezeway.tasks t ON t.property_pk = p.id
    WHERE p.property_status = 'active'
    GROUP BY p.id, p.property_id, p.property_name, p.region_code
),
regional_avgs AS (
    SELECT
        region_code,
        AVG(tasks_90d) as avg_tasks,
        AVG(completion_rate) as avg_completion_rate,
        AVG(avg_turnaround_hours) as avg_turnaround
    FROM property_metrics
    GROUP BY region_code
)
SELECT
    pm.property_pk,
    pm.property_id,
    pm.property_name,
    pm.region_code,
    pm.tasks_90d,
    pm.backlog,
    pm.urgent_backlog,
    pm.completion_rate,
    ROUND(pm.avg_turnaround_hours::numeric, 1) as avg_turnaround_hours,

    -- Health Score Components (0-100 scale)
    -- Lower backlog is better
    GREATEST(0, 100 - (pm.backlog * 10)) as backlog_score,
    -- Higher completion rate is better
    COALESCE(pm.completion_rate, 50) as completion_score,
    -- No urgent backlog is better
    CASE WHEN pm.urgent_backlog = 0 THEN 100
         WHEN pm.urgent_backlog <= 2 THEN 70
         ELSE 40 END as urgency_score,
    -- Faster turnaround is better (relative to regional average)
    CASE WHEN pm.avg_turnaround_hours IS NULL THEN 50
         WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) THEN 80
         WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) * 1.5 THEN 60
         ELSE 40 END as turnaround_score,

    -- Composite Health Score (weighted average)
    ROUND((
        GREATEST(0, 100 - (pm.backlog * 10)) * 0.25 +
        COALESCE(pm.completion_rate, 50) * 0.35 +
        (CASE WHEN pm.urgent_backlog = 0 THEN 100 WHEN pm.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
        (CASE WHEN pm.avg_turnaround_hours IS NULL THEN 50
              WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) THEN 80
              WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) * 1.5 THEN 60
              ELSE 40 END) * 0.15
    )::numeric, 1) as health_score,

    -- Health Status
    CASE
        WHEN (GREATEST(0, 100 - (pm.backlog * 10)) * 0.25 +
              COALESCE(pm.completion_rate, 50) * 0.35 +
              (CASE WHEN pm.urgent_backlog = 0 THEN 100 WHEN pm.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
              (CASE WHEN pm.avg_turnaround_hours IS NULL THEN 50
                    WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) THEN 80
                    ELSE 40 END) * 0.15) >= 80 THEN 'Excellent'
        WHEN (GREATEST(0, 100 - (pm.backlog * 10)) * 0.25 +
              COALESCE(pm.completion_rate, 50) * 0.35 +
              (CASE WHEN pm.urgent_backlog = 0 THEN 100 WHEN pm.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
              (CASE WHEN pm.avg_turnaround_hours IS NULL THEN 50
                    WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) THEN 80
                    ELSE 40 END) * 0.15) >= 65 THEN 'Good'
        WHEN (GREATEST(0, 100 - (pm.backlog * 10)) * 0.25 +
              COALESCE(pm.completion_rate, 50) * 0.35 +
              (CASE WHEN pm.urgent_backlog = 0 THEN 100 WHEN pm.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
              (CASE WHEN pm.avg_turnaround_hours IS NULL THEN 50
                    WHEN pm.avg_turnaround_hours <= COALESCE(ra.avg_turnaround, 200) THEN 80
                    ELSE 40 END) * 0.15) >= 50 THEN 'Fair'
        ELSE 'Needs Attention'
    END as health_status,

    CURRENT_TIMESTAMP as refreshed_at
FROM property_metrics pm
LEFT JOIN regional_avgs ra ON pm.region_code = ra.region_code
ORDER BY health_score DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 10: RESERVATION TURNAROUND ANALYSIS
-- Purpose: Analyze task performance around check-in/check-out
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis AS
SELECT
    r.region_code,
    DATE_TRUNC('week', r.checkout_date)::date as week_of,

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
GROUP BY r.region_code, DATE_TRUNC('week', r.checkout_date)
ORDER BY r.region_code, week_of DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 11: MONTHLY TREND ANALYSIS
-- Purpose: Track operational trends over time
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis AS
SELECT
    DATE_TRUNC('month', created_at)::date as month,
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

    -- Month-over-Month Change (calculated in application layer)
    LAG(COUNT(*)) OVER (PARTITION BY region_code, type_department ORDER BY DATE_TRUNC('month', created_at)) as prev_month_tasks,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE created_at >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', created_at), region_code, type_department
ORDER BY month DESC, region_code, type_department
WITH NO DATA;


-- ============================================================================
-- VIEW 12: WEEKLY OPERATIONAL SNAPSHOT
-- Purpose: Quick weekly operational summary for standup meetings
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot AS
SELECT
    DATE_TRUNC('week', CURRENT_DATE)::date as week_start,
    region_code,

    -- This Week's Volume
    COUNT(CASE WHEN created_at >= DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as tasks_created_this_week,
    COUNT(CASE WHEN finished_at >= DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as tasks_completed_this_week,

    -- Last Week's Volume (for comparison)
    COUNT(CASE WHEN created_at >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '7 days'
               AND created_at < DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as tasks_created_last_week,
    COUNT(CASE WHEN finished_at >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '7 days'
               AND finished_at < DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as tasks_completed_last_week,

    -- Current Backlog
    COUNT(CASE WHEN task_status_stage IN ('new', 'in_progress') THEN 1 END) as current_backlog,

    -- Urgency
    COUNT(CASE WHEN task_status_stage IN ('new', 'in_progress')
               AND type_priority IN ('urgent', 'high') THEN 1 END) as urgent_high_backlog,

    -- Department Breakdown This Week
    COUNT(CASE WHEN type_department = 'housekeeping'
               AND created_at >= DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as housekeeping_this_week,
    COUNT(CASE WHEN type_department = 'inspection'
               AND created_at >= DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as inspection_this_week,
    COUNT(CASE WHEN type_department = 'maintenance'
               AND created_at >= DATE_TRUNC('week', CURRENT_DATE) THEN 1 END) as maintenance_this_week,

    -- Active Workers This Week
    COUNT(DISTINCT CASE WHEN finished_at >= DATE_TRUNC('week', CURRENT_DATE)
                        THEN finished_by_id END) as active_workers_this_week,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code
WITH NO DATA;


-- ============================================================================
-- VIEW 13: PRIORITY RESPONSE TIMES
-- Purpose: Track response times by priority level
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_priority_response_times AS
SELECT
    region_code,
    type_department,
    type_priority,

    -- Volume
    COUNT(*) as total_tasks_90d,
    COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) as completed,

    -- Response Time Metrics (hours from creation to start)
    ROUND(AVG(CASE WHEN started_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (started_at - created_at))/3600 END)::numeric, 1) as avg_hours_to_start,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY CASE WHEN started_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (started_at - created_at))/3600 END
    )::numeric, 1) as median_hours_to_start,

    -- Resolution Time Metrics
    ROUND(AVG(CASE WHEN task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END)::numeric, 1) as avg_hours_to_resolve,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY CASE WHEN task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END
    )::numeric, 1) as median_hours_to_resolve,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY CASE WHEN task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (finished_at - created_at))/3600 END
    )::numeric, 1) as p90_hours_to_resolve,

    -- SLA-like metrics
    COUNT(CASE WHEN task_status_stage = 'finished'
               AND EXTRACT(EPOCH FROM (finished_at - created_at))/3600 <= 24 THEN 1 END) as resolved_within_24h,
    COUNT(CASE WHEN task_status_stage = 'finished'
               AND EXTRACT(EPOCH FROM (finished_at - created_at))/3600 <= 48 THEN 1 END) as resolved_within_48h,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY region_code, type_department, type_priority
ORDER BY region_code, type_department,
    CASE type_priority
        WHEN 'urgent' THEN 1
        WHEN 'high' THEN 2
        WHEN 'normal' THEN 3
        WHEN 'watch' THEN 4
        WHEN 'low' THEN 5
        ELSE 6
    END
WITH NO DATA;


-- ============================================================================
-- VIEW 14: TASK TAGS ANALYSIS
-- Purpose: Understand task categorization and patterns
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_task_tags_analysis AS
SELECT
    t.tag_name,
    t.region_code,

    -- Usage
    COUNT(tt.task_pk) as tagged_tasks_all_time,
    COUNT(CASE WHEN tk.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as tagged_tasks_90d,

    -- Department Distribution
    COUNT(CASE WHEN tk.type_department = 'maintenance' THEN 1 END) as maintenance_tasks,
    COUNT(CASE WHEN tk.type_department = 'housekeeping' THEN 1 END) as housekeeping_tasks,
    COUNT(CASE WHEN tk.type_department = 'inspection' THEN 1 END) as inspection_tasks,

    -- Completion
    COUNT(CASE WHEN tk.task_status_stage = 'finished' THEN 1 END) as completed_tasks,
    ROUND(COUNT(CASE WHEN tk.task_status_stage = 'finished' THEN 1 END)::numeric /
          NULLIF(COUNT(tt.task_pk), 0) * 100, 1) as completion_rate,

    -- Average Resolution Time
    ROUND(AVG(CASE WHEN tk.task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (tk.finished_at - tk.created_at))/3600 END)::numeric, 1) as avg_hours_to_complete,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tags t
LEFT JOIN breezeway.task_tags tt ON t.id = tt.tag_pk
LEFT JOIN breezeway.tasks tk ON tt.task_pk = tk.id
GROUP BY t.tag_name, t.region_code
HAVING COUNT(tt.task_pk) > 0
ORDER BY tagged_tasks_all_time DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 15: WORKER EFFICIENCY RANKING (Cross-Department)
-- Purpose: Compare workers across all departments
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_worker_efficiency_ranking AS
WITH worker_stats AS (
    SELECT
        finished_by_name as worker_name,
        finished_by_id as worker_id,
        region_code,

        -- Department versatility
        COUNT(DISTINCT type_department) as departments_worked,

        -- Volume
        COUNT(*) as total_tasks_90d,
        COUNT(CASE WHEN type_department = 'housekeeping' THEN 1 END) as housekeeping_count,
        COUNT(CASE WHEN type_department = 'inspection' THEN 1 END) as inspection_count,
        COUNT(CASE WHEN type_department = 'maintenance' THEN 1 END) as maintenance_count,

        -- Urgency Handling
        COUNT(CASE WHEN type_priority IN ('urgent', 'high') THEN 1 END) as urgent_high_tasks,

        -- Speed
        AVG(CASE WHEN started_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (finished_at - started_at))/60 END) as avg_minutes_active,
        AVG(EXTRACT(EPOCH FROM (finished_at - created_at))/3600) as avg_hours_total,

        -- Consistency
        STDDEV(EXTRACT(EPOCH FROM (finished_at - started_at))/60) as stddev_minutes,

        -- Activity Span
        MAX(finished_at)::date - MIN(finished_at)::date as days_active

    FROM breezeway.tasks
    WHERE task_status_stage = 'finished'
      AND finished_by_name IS NOT NULL
      AND finished_by_name != ''
      AND finished_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY finished_by_name, finished_by_id, region_code
    HAVING COUNT(*) >= 10  -- Minimum tasks for meaningful stats
)
SELECT
    worker_name,
    worker_id,
    region_code,
    departments_worked,
    total_tasks_90d,
    housekeeping_count,
    inspection_count,
    maintenance_count,
    urgent_high_tasks,
    ROUND(avg_minutes_active::numeric, 1) as avg_minutes_active,
    ROUND(avg_hours_total::numeric, 1) as avg_hours_total,
    ROUND(stddev_minutes::numeric, 1) as consistency_stddev,
    days_active,

    -- Productivity Score (tasks per active day)
    ROUND(total_tasks_90d::numeric / NULLIF(GREATEST(days_active, 1), 0), 2) as tasks_per_day,

    -- Efficiency Score (inverse of average time, normalized)
    ROUND(100 / (1 + COALESCE(avg_minutes_active, 60) / 60)::numeric, 1) as efficiency_score,

    -- Versatility Score
    CASE departments_worked
        WHEN 3 THEN 100
        WHEN 2 THEN 70
        ELSE 40
    END as versatility_score,

    -- Overall Rank
    DENSE_RANK() OVER (ORDER BY total_tasks_90d DESC) as volume_rank,
    DENSE_RANK() OVER (ORDER BY avg_minutes_active ASC NULLS LAST) as speed_rank,

    CURRENT_TIMESTAMP as refreshed_at
FROM worker_stats
ORDER BY total_tasks_90d DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 16: REGIONAL WORKLOAD DISTRIBUTION
-- Purpose: Balance workload insights across regions
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_regional_workload_distribution AS
WITH daily_tasks AS (
    SELECT
        region_code,
        DATE(created_at) as task_date,
        COUNT(*) as tasks_created,
        COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) as tasks_completed
    FROM breezeway.tasks
    WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY region_code, DATE(created_at)
)
SELECT
    region_code,

    -- Average Daily Volume
    ROUND(AVG(tasks_created)::numeric, 1) as avg_daily_tasks_created,
    ROUND(AVG(tasks_completed)::numeric, 1) as avg_daily_tasks_completed,

    -- Peak Day
    MAX(tasks_created) as peak_daily_tasks,

    -- Variability
    ROUND(STDDEV(tasks_created)::numeric, 1) as stddev_daily_tasks,

    -- Day with highest volume
    (SELECT task_date FROM daily_tasks dt2
     WHERE dt2.region_code = dt.region_code
     ORDER BY tasks_created DESC LIMIT 1) as busiest_day,

    -- Properties and workers
    (SELECT COUNT(*) FROM breezeway.properties p
     WHERE p.region_code = dt.region_code AND p.property_status = 'active') as property_count,
    (SELECT COUNT(DISTINCT finished_by_id) FROM breezeway.tasks t
     WHERE t.region_code = dt.region_code
       AND t.finished_at >= CURRENT_DATE - INTERVAL '30 days') as active_workers_30d,

    -- Tasks per property per day
    ROUND(AVG(tasks_created)::numeric /
          NULLIF((SELECT COUNT(*) FROM breezeway.properties p
                  WHERE p.region_code = dt.region_code AND p.property_status = 'active'), 0), 2) as tasks_per_property_per_day,

    -- Tasks per worker per day
    ROUND(AVG(tasks_created)::numeric /
          NULLIF((SELECT COUNT(DISTINCT finished_by_id) FROM breezeway.tasks t
                  WHERE t.region_code = dt.region_code
                    AND t.finished_at >= CURRENT_DATE - INTERVAL '30 days'), 0), 2) as tasks_per_worker_per_day,

    CURRENT_TIMESTAMP as refreshed_at
FROM daily_tasks dt
GROUP BY region_code
ORDER BY avg_daily_tasks_created DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 17: SEASONAL DEMAND PATTERNS
-- Purpose: Identify seasonal trends for capacity planning
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_seasonal_demand_patterns AS
SELECT
    region_code,
    EXTRACT(MONTH FROM created_at)::int as month_num,
    TO_CHAR(created_at, 'Month') as month_name,
    EXTRACT(DOW FROM created_at)::int as day_of_week,
    TO_CHAR(created_at, 'Day') as day_name,

    -- Task Volume
    COUNT(*) as total_tasks,
    COUNT(CASE WHEN type_department = 'housekeeping' THEN 1 END) as housekeeping,
    COUNT(CASE WHEN type_department = 'inspection' THEN 1 END) as inspection,
    COUNT(CASE WHEN type_department = 'maintenance' THEN 1 END) as maintenance,

    -- Reservation correlation (if linked)
    COUNT(CASE WHEN reservation_pk IS NOT NULL THEN 1 END) as reservation_linked,

    -- Urgency
    COUNT(CASE WHEN type_priority IN ('urgent', 'high') THEN 1 END) as urgent_high_priority,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE created_at >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY region_code,
         EXTRACT(MONTH FROM created_at),
         TO_CHAR(created_at, 'Month'),
         EXTRACT(DOW FROM created_at),
         TO_CHAR(created_at, 'Day')
ORDER BY region_code, month_num, day_of_week
WITH NO DATA;


-- ============================================================================
-- VIEW 18: PROPERTY MAINTENANCE BURDEN
-- Purpose: Identify properties with recurring maintenance issues
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_property_maintenance_burden AS
SELECT
    p.id as property_pk,
    p.property_id,
    p.property_name,
    p.region_code,
    p.property_city,

    -- Maintenance Task Volume
    COUNT(t.id) as total_maintenance_tasks,
    COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as maintenance_90d,
    COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as maintenance_30d,

    -- Priority Distribution
    COUNT(CASE WHEN t.type_priority = 'urgent' THEN 1 END) as urgent_tasks,
    COUNT(CASE WHEN t.type_priority = 'high' THEN 1 END) as high_priority_tasks,

    -- Current Backlog
    COUNT(CASE WHEN t.task_status_stage IN ('new', 'in_progress') THEN 1 END) as maintenance_backlog,

    -- Average Resolution Time
    ROUND(AVG(CASE WHEN t.task_status_stage = 'finished'
        THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at))/3600 END)::numeric, 1) as avg_hours_to_resolve,

    -- Repeat Issue Indicator (tasks in last 30 days vs 90 days)
    ROUND(COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END)::numeric /
          NULLIF(COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) / 3.0, 0), 2) as recency_ratio,

    -- Maintenance Cost Indicator
    SUM(CASE WHEN t.rate_paid IS NOT NULL THEN t.rate_paid ELSE 0 END) as total_rate_paid,

    -- Rank
    DENSE_RANK() OVER (PARTITION BY p.region_code ORDER BY COUNT(t.id) DESC) as regional_maintenance_rank,

    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.properties p
LEFT JOIN breezeway.tasks t ON t.property_pk = p.id AND t.type_department = 'maintenance'
WHERE p.property_status = 'active'
GROUP BY p.id, p.property_id, p.property_name, p.region_code, p.property_city
HAVING COUNT(t.id) > 0
ORDER BY total_maintenance_tasks DESC
WITH NO DATA;


-- ============================================================================
-- VIEW 19: DATA QUALITY SCORECARD
-- Purpose: Track data completeness and quality issues
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_data_quality_scorecard AS
SELECT
    'tasks' as entity,
    COUNT(*) as total_records,
    COUNT(task_id) as with_task_id,
    COUNT(task_name) as with_task_name,
    COUNT(created_at) as with_created_at,
    COUNT(finished_at) as with_finished_at,
    COUNT(started_at) as with_started_at,
    COUNT(finished_by_name) as with_finished_by,
    COUNT(property_pk) as with_property_link,
    COUNT(reservation_pk) as with_reservation_link,
    ROUND(COUNT(finished_by_name)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_completer,
    ROUND(COUNT(started_at)::numeric / NULLIF(COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END), 0) * 100, 1) as pct_finished_with_start_time,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks

UNION ALL

SELECT
    'properties' as entity,
    COUNT(*) as total_records,
    COUNT(property_id) as with_property_id,
    COUNT(property_name) as with_property_name,
    COUNT(property_city) as with_city,
    COUNT(latitude_numeric) as with_latitude,
    COUNT(longitude_numeric) as with_longitude,
    COUNT(wifi_name) as with_wifi,
    0 as with_property_link,
    0 as with_reservation_link,
    ROUND(COUNT(latitude_numeric)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_coordinates,
    ROUND(COUNT(wifi_name)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_wifi,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.properties

UNION ALL

SELECT
    'reservations' as entity,
    COUNT(*) as total_records,
    COUNT(reservation_id) as with_reservation_id,
    COUNT(checkin_date) as with_checkin,
    COUNT(checkout_date) as with_checkout,
    COUNT(access_code) as with_access_code,
    COUNT(guide_url) as with_guide_url,
    COUNT(property_pk) as with_property_link,
    0 as placeholder1,
    0 as placeholder2,
    ROUND(COUNT(access_code)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_access_code,
    ROUND(COUNT(property_pk)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_property_link,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.reservations

UNION ALL

SELECT
    'task_assignments' as entity,
    COUNT(*) as total_records,
    COUNT(task_pk) as with_task_pk,
    COUNT(assignee_name) as with_assignee_name,
    COUNT(assignee_id) as with_assignee_id,
    0, 0, 0, 0, 0,
    ROUND(COUNT(assignee_name)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_name,
    ROUND(COUNT(assignee_id)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_id,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.task_assignments

UNION ALL

SELECT
    'people' as entity,
    COUNT(*) as total_records,
    COUNT(person_id) as with_person_id,
    COUNT(person_name) as with_name,
    COUNT(CASE WHEN active THEN 1 END) as active_count,
    COUNT(availability_monday) as with_monday_avail,
    COUNT(availability_tuesday) as with_tuesday_avail,
    0, 0, 0,
    ROUND(COUNT(CASE WHEN active THEN 1 END)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_active,
    ROUND(COUNT(availability_monday)::numeric / NULLIF(COUNT(*), 0) * 100, 1) as pct_with_availability,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.people
WITH NO DATA;


-- ============================================================================
-- VIEW 20: OPERATIONAL ALERTS
-- Purpose: Real-time alerts for operational issues
-- ============================================================================
CREATE MATERIALIZED VIEW breezeway.mv_operational_alerts AS

-- Stale Tasks (New tasks older than 7 days)
SELECT
    'STALE_TASK' as alert_type,
    'High' as severity,
    region_code,
    task_id::text as entity_id,
    task_name as entity_name,
    type_department as category,
    'Task pending for ' || (CURRENT_DATE - DATE(created_at)) || ' days' as alert_message,
    created_at as alert_trigger_date,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE task_status_stage = 'new'
  AND CURRENT_DATE - DATE(created_at) > 7

UNION ALL

-- Urgent Tasks Not Started
SELECT
    'URGENT_NOT_STARTED' as alert_type,
    'Critical' as severity,
    region_code,
    task_id::text as entity_id,
    task_name as entity_name,
    type_department as category,
    'Urgent task not started for ' || (CURRENT_DATE - DATE(created_at)) || ' days' as alert_message,
    created_at as alert_trigger_date,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks
WHERE task_status_stage = 'new'
  AND type_priority = 'urgent'
  AND CURRENT_DATE - DATE(created_at) > 1

UNION ALL

-- Properties with High Backlog
SELECT
    'HIGH_BACKLOG_PROPERTY' as alert_type,
    'Medium' as severity,
    p.region_code,
    p.property_id::text as entity_id,
    p.property_name as entity_name,
    'property' as category,
    'Property has ' || COUNT(t.id) || ' tasks in backlog' as alert_message,
    MAX(t.created_at) as alert_trigger_date,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.properties p
JOIN breezeway.tasks t ON t.property_pk = p.id
WHERE t.task_status_stage IN ('new', 'in_progress')
GROUP BY p.region_code, p.property_id, p.property_name
HAVING COUNT(t.id) >= 5

UNION ALL

-- Today's Checkouts Without Completed Housekeeping
SELECT
    'CHECKOUT_NO_CLEANING' as alert_type,
    'Critical' as severity,
    r.region_code,
    r.reservation_id::text as entity_id,
    p.property_name as entity_name,
    'housekeeping' as category,
    'Checkout today but no completed housekeeping task' as alert_message,
    r.checkout_date::timestamp as alert_trigger_date,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.reservations r
JOIN breezeway.properties p ON r.property_pk = p.id
WHERE r.checkout_date = CURRENT_DATE
  AND r.reservation_status = 'active'
  AND NOT EXISTS (
      SELECT 1 FROM breezeway.tasks t
      WHERE t.property_pk = r.property_pk
        AND t.type_department = 'housekeeping'
        AND t.task_status_stage = 'finished'
        AND DATE(t.finished_at) = CURRENT_DATE
  )

UNION ALL

-- Regions with Low Worker Activity
SELECT
    'LOW_WORKER_ACTIVITY' as alert_type,
    'Medium' as severity,
    region_code,
    region_code as entity_id,
    (SELECT region_name FROM breezeway.regions r WHERE r.region_code = t.region_code) as entity_name,
    'workforce' as category,
    'Only ' || COUNT(DISTINCT finished_by_id) || ' workers active in last 7 days' as alert_message,
    MAX(finished_at) as alert_trigger_date,
    CURRENT_TIMESTAMP as refreshed_at
FROM breezeway.tasks t
WHERE finished_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY region_code
HAVING COUNT(DISTINCT finished_by_id) < 3

ORDER BY
    CASE severity WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END,
    alert_trigger_date DESC
WITH NO DATA;


-- ============================================================================
-- CREATE INDEXES FOR MATERIALIZED VIEWS
-- ============================================================================

-- Refresh all materialized views with data
REFRESH MATERIALIZED VIEW breezeway.mv_portfolio_executive_summary;
REFRESH MATERIALIZED VIEW breezeway.mv_regional_performance_scorecard;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_housekeeping;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_inspection;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_maintenance;
REFRESH MATERIALIZED VIEW breezeway.mv_task_completion_metrics;
REFRESH MATERIALIZED VIEW breezeway.mv_task_backlog_aging;
REFRESH MATERIALIZED VIEW breezeway.mv_property_task_density;
REFRESH MATERIALIZED VIEW breezeway.mv_property_operational_health;
REFRESH MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;
REFRESH MATERIALIZED VIEW breezeway.mv_priority_response_times;
REFRESH MATERIALIZED VIEW breezeway.mv_task_tags_analysis;
REFRESH MATERIALIZED VIEW breezeway.mv_worker_efficiency_ranking;
REFRESH MATERIALIZED VIEW breezeway.mv_regional_workload_distribution;
REFRESH MATERIALIZED VIEW breezeway.mv_seasonal_demand_patterns;
REFRESH MATERIALIZED VIEW breezeway.mv_property_maintenance_burden;
REFRESH MATERIALIZED VIEW breezeway.mv_data_quality_scorecard;
REFRESH MATERIALIZED VIEW breezeway.mv_operational_alerts;

-- Create indexes on commonly queried columns
CREATE INDEX IF NOT EXISTS idx_mv_regional_perf_region ON breezeway.mv_regional_performance_scorecard(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_housekeeping_lb_region ON breezeway.mv_worker_leaderboard_housekeeping(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_inspection_lb_region ON breezeway.mv_worker_leaderboard_inspection(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_maintenance_lb_region ON breezeway.mv_worker_leaderboard_maintenance(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_task_completion_region ON breezeway.mv_task_completion_metrics(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_backlog_region ON breezeway.mv_task_backlog_aging(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_property_density_region ON breezeway.mv_property_task_density(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_property_health_score ON breezeway.mv_property_operational_health(health_score DESC);
CREATE INDEX IF NOT EXISTS idx_mv_monthly_trend_month ON breezeway.mv_monthly_trend_analysis(month DESC);
CREATE INDEX IF NOT EXISTS idx_mv_alerts_severity ON breezeway.mv_operational_alerts(severity, alert_type);


-- ============================================================================
-- HELPER FUNCTION: Refresh All Dashboard Views
-- ============================================================================
CREATE OR REPLACE FUNCTION breezeway.refresh_dashboard_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW breezeway.mv_portfolio_executive_summary;
    REFRESH MATERIALIZED VIEW breezeway.mv_regional_performance_scorecard;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_housekeeping;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_inspection;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_maintenance;
    REFRESH MATERIALIZED VIEW breezeway.mv_task_completion_metrics;
    REFRESH MATERIALIZED VIEW breezeway.mv_task_backlog_aging;
    REFRESH MATERIALIZED VIEW breezeway.mv_property_task_density;
    REFRESH MATERIALIZED VIEW breezeway.mv_property_operational_health;
    REFRESH MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis;
    REFRESH MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis;
    REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;
    REFRESH MATERIALIZED VIEW breezeway.mv_priority_response_times;
    REFRESH MATERIALIZED VIEW breezeway.mv_task_tags_analysis;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_efficiency_ranking;
    REFRESH MATERIALIZED VIEW breezeway.mv_regional_workload_distribution;
    REFRESH MATERIALIZED VIEW breezeway.mv_seasonal_demand_patterns;
    REFRESH MATERIALIZED VIEW breezeway.mv_property_maintenance_burden;
    REFRESH MATERIALIZED VIEW breezeway.mv_data_quality_scorecard;
    REFRESH MATERIALIZED VIEW breezeway.mv_operational_alerts;

    RAISE NOTICE 'All dashboard views refreshed at %', CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- GRANT PERMISSIONS TO BREEZEWAY USER
-- ============================================================================
GRANT SELECT ON breezeway.mv_portfolio_executive_summary TO breezeway;
GRANT SELECT ON breezeway.mv_regional_performance_scorecard TO breezeway;
GRANT SELECT ON breezeway.mv_worker_leaderboard_housekeeping TO breezeway;
GRANT SELECT ON breezeway.mv_worker_leaderboard_inspection TO breezeway;
GRANT SELECT ON breezeway.mv_worker_leaderboard_maintenance TO breezeway;
GRANT SELECT ON breezeway.mv_task_completion_metrics TO breezeway;
GRANT SELECT ON breezeway.mv_task_backlog_aging TO breezeway;
GRANT SELECT ON breezeway.mv_property_task_density TO breezeway;
GRANT SELECT ON breezeway.mv_property_operational_health TO breezeway;
GRANT SELECT ON breezeway.mv_reservation_turnaround_analysis TO breezeway;
GRANT SELECT ON breezeway.mv_monthly_trend_analysis TO breezeway;
GRANT SELECT ON breezeway.mv_weekly_operational_snapshot TO breezeway;
GRANT SELECT ON breezeway.mv_priority_response_times TO breezeway;
GRANT SELECT ON breezeway.mv_task_tags_analysis TO breezeway;
GRANT SELECT ON breezeway.mv_worker_efficiency_ranking TO breezeway;
GRANT SELECT ON breezeway.mv_regional_workload_distribution TO breezeway;
GRANT SELECT ON breezeway.mv_seasonal_demand_patterns TO breezeway;
GRANT SELECT ON breezeway.mv_property_maintenance_burden TO breezeway;
GRANT SELECT ON breezeway.mv_data_quality_scorecard TO breezeway;
GRANT SELECT ON breezeway.mv_operational_alerts TO breezeway;

-- Grant default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA breezeway GRANT SELECT ON TABLES TO breezeway;


-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- To refresh all views: SELECT breezeway.refresh_dashboard_views();
--
-- Recommended refresh schedule:
--   - mv_operational_alerts: Every 15 minutes (critical)
--   - mv_weekly_operational_snapshot: Hourly
--   - mv_portfolio_executive_summary: Hourly
--   - All others: Daily (midnight)
--
-- Example cron for refresh:
--   */15 * * * * psql -c "REFRESH MATERIALIZED VIEW breezeway.mv_operational_alerts;"
--   0 * * * * psql -c "REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;"
--   0 0 * * * psql -c "SELECT breezeway.refresh_dashboard_views();"
--

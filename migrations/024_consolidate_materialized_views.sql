-- ============================================================================
-- Migration 024: Consolidate Materialized Views
-- Date: 2026-02-23
-- Purpose: Combine redundant property/regional views into 2 dashboards,
--          add 4 new department-specific views, drop 6 replaced views.
--
-- Creates:
--   1. mv_property_dashboard       (replaces mv_property_task_density,
--                                    mv_property_maintenance_burden,
--                                    mv_property_operational_health)
--   2. mv_regional_dashboard       (replaces mv_regional_performance_scorecard,
--                                    mv_regional_workload_distribution,
--                                    folds in mv_task_backlog_aging)
--   3. mv_daily_turnover_board     (new - housekeeping war room)
--   4. mv_inspection_compliance    (new - inspection requirement tracking)
--   5. mv_housekeeping_schedule_performance (new - cleaner metrics)
--   6. mv_department_sla_tracker   (new - SLA compliance dashboard)
--
-- Drops:
--   mv_property_task_density, mv_property_maintenance_burden,
--   mv_property_operational_health, mv_regional_performance_scorecard,
--   mv_regional_workload_distribution, mv_task_backlog_aging
--
-- Net effect: 18 views - 6 dropped + 4 new = 16 materialized views
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1a: COMBINED PROPERTY DASHBOARD
-- Replaces: mv_property_task_density, mv_property_maintenance_burden,
--           mv_property_operational_health
-- Single properties LEFT JOIN tasks scan with all property-level metrics
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_dashboard CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_property_dashboard AS
WITH property_base AS (
    SELECT
        p.id AS property_pk,
        p.property_id,
        p.property_name,
        p.region_code,
        p.property_city,

        -- === Task Density: volume counts ===
        COUNT(t.id) AS total_tasks_all_time,
        COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) AS tasks_90d,
        COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS tasks_30d,
        COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) AS tasks_7d,

        -- Department breakdowns (90d)
        COUNT(CASE WHEN t.type_department = 'maintenance' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) AS maintenance_tasks_90d,
        COUNT(CASE WHEN t.type_department = 'housekeeping' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) AS housekeeping_tasks_90d,
        COUNT(CASE WHEN t.type_department = 'inspection' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) AS inspection_tasks_90d,
        COUNT(CASE WHEN t.type_priority IN ('urgent', 'high') AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) AS urgent_high_tasks_90d,

        -- Backlog
        COUNT(CASE WHEN t.task_status_stage IN ('new', 'in_progress') THEN 1 END) AS current_backlog,
        COUNT(CASE WHEN t.type_priority IN ('urgent', 'high') AND t.task_status_stage IN ('new', 'in_progress') THEN 1 END) AS urgent_backlog,

        -- Completion metrics
        ROUND(AVG(CASE WHEN t.task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at)) / 3600 END)::numeric, 1) AS avg_hours_to_complete,

        -- Completion rate (90d)
        ROUND(
            COUNT(CASE WHEN t.task_status_stage = 'finished' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END)::numeric /
            NULLIF(COUNT(CASE WHEN t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END), 0) * 100, 1
        ) AS completion_rate,

        -- Average turnaround hours (for health score)
        AVG(CASE WHEN t.task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at)) / 3600 END) AS avg_turnaround_hours_raw,

        -- === Maintenance Burden ===
        COUNT(CASE WHEN t.type_department = 'maintenance' THEN 1 END) AS total_maintenance_tasks,
        COUNT(CASE WHEN t.type_department = 'maintenance' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) AS maintenance_90d,
        COUNT(CASE WHEN t.type_department = 'maintenance' AND t.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS maintenance_30d,
        COUNT(CASE WHEN t.type_department = 'maintenance' AND t.type_priority = 'urgent' THEN 1 END) AS maintenance_urgent_tasks,
        COUNT(CASE WHEN t.type_department = 'maintenance' AND t.type_priority = 'high' THEN 1 END) AS maintenance_high_priority_tasks,
        COUNT(CASE WHEN t.type_department = 'maintenance' AND t.task_status_stage IN ('new', 'in_progress') THEN 1 END) AS maintenance_backlog,
        ROUND(AVG(CASE WHEN t.type_department = 'maintenance' AND t.task_status_stage = 'finished'
            THEN EXTRACT(EPOCH FROM (t.finished_at - t.created_at)) / 3600 END)::numeric, 1) AS maintenance_avg_hours_to_resolve,
        -- Recency ratio: 30d rate vs 90d monthly average
        ROUND(
            COUNT(CASE WHEN t.type_department = 'maintenance' AND t.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END)::numeric /
            NULLIF(COUNT(CASE WHEN t.type_department = 'maintenance' AND t.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) / 3.0, 0), 2
        ) AS maintenance_recency_ratio,
        SUM(CASE WHEN t.type_department = 'maintenance' AND t.rate_paid IS NOT NULL THEN t.rate_paid ELSE 0 END) AS maintenance_total_rate_paid,

        -- Reservation count (correlated subquery)
        (SELECT COUNT(*) FROM breezeway.reservations r
         WHERE r.property_pk = p.id AND r.reservation_status = 'active') AS active_reservations

    FROM breezeway.properties p
    LEFT JOIN breezeway.tasks t ON t.property_pk = p.id
    WHERE p.property_status = 'active'
    GROUP BY p.id, p.property_id, p.property_name, p.region_code, p.property_city
),
regional_avgs AS (
    SELECT
        region_code,
        AVG(avg_turnaround_hours_raw) AS avg_turnaround
    FROM property_base
    GROUP BY region_code
)
SELECT
    pb.property_pk,
    pb.property_id,
    pb.property_name,
    pb.region_code,
    pb.property_city,

    -- Task Density
    pb.total_tasks_all_time,
    pb.tasks_90d,
    pb.tasks_30d,
    pb.tasks_7d,
    pb.maintenance_tasks_90d,
    pb.housekeeping_tasks_90d,
    pb.inspection_tasks_90d,
    pb.urgent_high_tasks_90d,
    pb.current_backlog,
    pb.avg_hours_to_complete,
    pb.active_reservations,
    DENSE_RANK() OVER (PARTITION BY pb.region_code ORDER BY pb.total_tasks_all_time DESC) AS regional_task_rank,
    DENSE_RANK() OVER (ORDER BY pb.total_tasks_all_time DESC) AS global_task_rank,

    -- Maintenance Burden
    pb.total_maintenance_tasks,
    pb.maintenance_90d,
    pb.maintenance_30d,
    pb.maintenance_urgent_tasks,
    pb.maintenance_high_priority_tasks,
    pb.maintenance_backlog,
    pb.maintenance_avg_hours_to_resolve,
    pb.maintenance_recency_ratio,
    pb.maintenance_total_rate_paid,
    DENSE_RANK() OVER (PARTITION BY pb.region_code ORDER BY pb.total_maintenance_tasks DESC) AS regional_maintenance_rank,

    -- Operational Health: component scores (0-100)
    pb.urgent_backlog,
    pb.completion_rate,
    ROUND(pb.avg_turnaround_hours_raw::numeric, 1) AS avg_turnaround_hours,

    GREATEST(0, 100 - (pb.current_backlog * 10)) AS backlog_score,
    COALESCE(pb.completion_rate, 50) AS completion_score,
    CASE
        WHEN pb.urgent_backlog = 0 THEN 100
        WHEN pb.urgent_backlog <= 2 THEN 70
        ELSE 40
    END AS urgency_score,
    CASE
        WHEN pb.avg_turnaround_hours_raw IS NULL THEN 50
        WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) THEN 80
        WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) * 1.5 THEN 60
        ELSE 40
    END AS turnaround_score,

    -- Composite health score (backlog 25%, completion 35%, urgency 25%, turnaround 15%)
    ROUND((
        GREATEST(0, 100 - (pb.current_backlog * 10)) * 0.25 +
        COALESCE(pb.completion_rate, 50) * 0.35 +
        (CASE WHEN pb.urgent_backlog = 0 THEN 100 WHEN pb.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
        (CASE
            WHEN pb.avg_turnaround_hours_raw IS NULL THEN 50
            WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) THEN 80
            WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) * 1.5 THEN 60
            ELSE 40
        END) * 0.15
    )::numeric, 1) AS health_score,

    CASE
        WHEN (GREATEST(0, 100 - (pb.current_backlog * 10)) * 0.25 +
              COALESCE(pb.completion_rate, 50) * 0.35 +
              (CASE WHEN pb.urgent_backlog = 0 THEN 100 WHEN pb.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
              (CASE WHEN pb.avg_turnaround_hours_raw IS NULL THEN 50
                    WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) THEN 80
                    ELSE 40 END) * 0.15) >= 80 THEN 'Excellent'
        WHEN (GREATEST(0, 100 - (pb.current_backlog * 10)) * 0.25 +
              COALESCE(pb.completion_rate, 50) * 0.35 +
              (CASE WHEN pb.urgent_backlog = 0 THEN 100 WHEN pb.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
              (CASE WHEN pb.avg_turnaround_hours_raw IS NULL THEN 50
                    WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) THEN 80
                    ELSE 40 END) * 0.15) >= 65 THEN 'Good'
        WHEN (GREATEST(0, 100 - (pb.current_backlog * 10)) * 0.25 +
              COALESCE(pb.completion_rate, 50) * 0.35 +
              (CASE WHEN pb.urgent_backlog = 0 THEN 100 WHEN pb.urgent_backlog <= 2 THEN 70 ELSE 40 END) * 0.25 +
              (CASE WHEN pb.avg_turnaround_hours_raw IS NULL THEN 50
                    WHEN pb.avg_turnaround_hours_raw <= COALESCE(ra.avg_turnaround, 200) THEN 80
                    ELSE 40 END) * 0.15) >= 50 THEN 'Fair'
        ELSE 'Needs Attention'
    END AS health_status,

    CURRENT_TIMESTAMP AS refreshed_at
FROM property_base pb
LEFT JOIN regional_avgs ra ON pb.region_code = ra.region_code
ORDER BY pb.total_tasks_all_time DESC
WITH NO DATA;


-- ============================================================================
-- STEP 1b: COMBINED REGIONAL DASHBOARD
-- Replaces: mv_regional_performance_scorecard, mv_regional_workload_distribution
-- Folds in: mv_task_backlog_aging (aggregated per region)
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
-- Workload distribution (30-day daily averages)
daily_tasks AS (
    SELECT
        region_code,
        DATE(created_at) AS task_date,
        COUNT(*) AS tasks_created,
        COUNT(CASE WHEN task_status_stage = 'finished' THEN 1 END) AS tasks_completed
    FROM breezeway.tasks
    WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY region_code, DATE(created_at)
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
        COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) <= 1 THEN 1 END) AS backlog_age_0_1d,
        COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 2 AND 3 THEN 1 END) AS backlog_age_2_3d,
        COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 4 AND 7 THEN 1 END) AS backlog_age_4_7d,
        COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 8 AND 14 THEN 1 END) AS backlog_age_8_14d,
        COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) BETWEEN 15 AND 30 THEN 1 END) AS backlog_age_15_30d,
        COUNT(CASE WHEN CURRENT_DATE - DATE(created_at) > 30 THEN 1 END) AS backlog_age_over_30d,
        COUNT(*) AS total_backlog_tasks,
        ROUND(AVG(CURRENT_DATE - DATE(created_at))::numeric, 1) AS avg_backlog_age_days,
        MAX(CURRENT_DATE - DATE(created_at)) AS max_backlog_age_days,
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
-- STEP 2a: DAILY TURNOVER BOARD
-- "War room" view: checkouts today/tomorrow with housekeeping & inspection status
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_daily_turnover_board CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_daily_turnover_board AS
WITH checkouts AS (
    SELECT
        r.id AS reservation_pk,
        r.reservation_id,
        r.region_code,
        r.property_pk,
        r.checkout_date,
        r.checkout_time,
        r.pets,
        p.property_name,
        p.property_id
    FROM breezeway.reservations r
    JOIN breezeway.properties p ON r.property_pk = p.id
    WHERE r.reservation_status = 'active'
      AND r.checkout_date IN (CURRENT_DATE, CURRENT_DATE + 1)
),
next_checkins AS (
    SELECT DISTINCT ON (r.property_pk)
        r.property_pk,
        r.checkin_date AS next_checkin_date,
        r.checkin_time AS next_checkin_time
    FROM breezeway.reservations r
    WHERE r.reservation_status = 'active'
      AND r.checkin_date >= CURRENT_DATE
    ORDER BY r.property_pk, r.checkin_date ASC, r.checkin_time ASC
),
housekeeping_tasks AS (
    SELECT DISTINCT ON (t.property_pk, t.checkout_date)
        t.property_pk,
        t.checkout_date,
        t.id AS hk_task_id,
        t.task_status_stage AS hk_status_stage,
        t.task_name AS hk_task_name,
        t.finished_by_name AS hk_finished_by,
        -- Determine assignment/progress status
        CASE
            WHEN t.task_status_stage = 'finished' THEN 'completed'
            WHEN t.task_status_stage = 'in_progress' THEN 'in_progress'
            WHEN EXISTS (
                SELECT 1 FROM breezeway.task_assignments ta
                WHERE ta.task_pk = t.id
            ) THEN 'assigned'
            ELSE 'unassigned'
        END AS hk_status
    FROM breezeway.tasks t
    WHERE t.type_department = 'housekeeping'
      AND t.checkout_date IN (CURRENT_DATE, CURRENT_DATE + 1)
    ORDER BY t.property_pk, t.checkout_date,
        CASE t.task_status_stage
            WHEN 'finished' THEN 1
            WHEN 'in_progress' THEN 2
            WHEN 'new' THEN 3
            ELSE 4
        END
),
inspection_tasks AS (
    SELECT DISTINCT ON (t.property_pk, t.checkout_date)
        t.property_pk,
        t.checkout_date,
        t.id AS insp_task_id,
        t.task_status_stage AS insp_status_stage,
        t.task_name AS insp_task_name,
        t.finished_by_name AS insp_finished_by,
        CASE
            WHEN t.task_status_stage = 'finished' THEN 'completed'
            WHEN t.task_status_stage = 'in_progress' THEN 'in_progress'
            WHEN EXISTS (
                SELECT 1 FROM breezeway.task_assignments ta
                WHERE ta.task_pk = t.id
            ) THEN 'assigned'
            ELSE 'unassigned'
        END AS insp_status
    FROM breezeway.tasks t
    WHERE t.type_department = 'inspection'
      AND t.checkout_date IN (CURRENT_DATE, CURRENT_DATE + 1)
    ORDER BY t.property_pk, t.checkout_date,
        CASE t.task_status_stage
            WHEN 'finished' THEN 1
            WHEN 'in_progress' THEN 2
            WHEN 'new' THEN 3
            ELSE 4
        END
)
SELECT
    co.region_code,
    co.property_pk,
    co.property_id,
    co.property_name,
    co.reservation_pk,
    co.reservation_id,
    co.checkout_date,
    co.checkout_time,
    nc.next_checkin_date,
    nc.next_checkin_time,

    -- Turnaround hours between checkout and next checkin
    CASE
        WHEN nc.next_checkin_date IS NOT NULL AND co.checkout_time IS NOT NULL AND nc.next_checkin_time IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (
            (nc.next_checkin_date + nc.next_checkin_time) -
            (co.checkout_date + co.checkout_time)
        )) / 3600.0, 1)
        WHEN nc.next_checkin_date IS NOT NULL
        THEN (nc.next_checkin_date - co.checkout_date) * 24.0
        ELSE NULL
    END AS turnaround_hours,

    -- Housekeeping status
    COALESCE(hk.hk_status, 'none') AS housekeeping_status,
    hk.hk_task_name AS housekeeping_task_name,
    hk.hk_finished_by AS housekeeping_finished_by,

    -- Inspection status
    COALESCE(it.insp_status, 'none') AS inspection_status,
    it.insp_task_name AS inspection_task_name,
    it.insp_finished_by AS inspection_finished_by,

    -- Pet departure flag
    COALESCE(co.pets, 0) AS guest_pets,

    -- Risk flags array
    ARRAY_REMOVE(ARRAY[
        CASE WHEN hk.hk_status IS NULL THEN 'NO_HOUSEKEEPING_TASK' END,
        CASE WHEN hk.hk_status = 'unassigned' THEN 'NO_CLEANER_ASSIGNED' END,
        CASE WHEN nc.next_checkin_date IS NOT NULL
             AND (nc.next_checkin_date - co.checkout_date) <= 1
             AND (nc.next_checkin_date - co.checkout_date) > 0 THEN 'TIGHT_TURNAROUND' END,
        CASE WHEN nc.next_checkin_date = co.checkout_date THEN 'SAME_DAY_TURNAROUND' END,
        CASE WHEN it.insp_status IS NOT NULL AND it.insp_status != 'completed' THEN 'INSPECTION_INCOMPLETE' END,
        CASE WHEN it.insp_status IS NULL AND hk.hk_status IS NOT NULL THEN 'INSPECTION_INCOMPLETE' END,
        CASE WHEN COALESCE(co.pets, 0) > 0 THEN 'PET_DEPARTURE' END
    ], NULL) AS risk_flags,

    CURRENT_TIMESTAMP AS refreshed_at
FROM checkouts co
LEFT JOIN next_checkins nc ON co.property_pk = nc.property_pk
LEFT JOIN housekeeping_tasks hk ON co.property_pk = hk.property_pk AND co.checkout_date = hk.checkout_date
LEFT JOIN inspection_tasks it ON co.property_pk = it.property_pk AND co.checkout_date = it.checkout_date
ORDER BY
    co.checkout_date,
    ARRAY_LENGTH(ARRAY_REMOVE(ARRAY[
        CASE WHEN hk.hk_status IS NULL THEN 'x' END,
        CASE WHEN hk.hk_status = 'unassigned' THEN 'x' END,
        CASE WHEN nc.next_checkin_date = co.checkout_date THEN 'x' END,
        CASE WHEN COALESCE(co.pets, 0) > 0 THEN 'x' END
    ], NULL), 1) DESC NULLS LAST,
    co.region_code,
    co.property_name
WITH NO DATA;


-- ============================================================================
-- STEP 2b: INSPECTION COMPLIANCE
-- Per-property and per-inspector inspection requirement completion (90d)
-- Uses entity_type column for dual-granularity in one view
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_inspection_compliance CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_inspection_compliance AS
WITH inspection_tasks AS (
    -- Pre-filter to inspection department before joining 26.7M-row task_requirements
    SELECT
        t.id AS task_pk,
        t.region_code,
        t.property_pk,
        t.task_status_stage,
        t.finished_by_id,
        t.finished_by_name
    FROM breezeway.tasks t
    WHERE t.type_department = 'inspection'
      AND t.created_at >= CURRENT_DATE - INTERVAL '90 days'
),
requirement_stats AS (
    SELECT
        it.task_pk,
        it.region_code,
        it.property_pk,
        it.task_status_stage,
        it.finished_by_id,
        it.finished_by_name,
        COUNT(tr.id) AS total_requirements,
        COUNT(CASE WHEN tr.response IS NOT NULL AND tr.response != '' THEN 1 END) AS completed_requirements,
        COUNT(CASE WHEN tr.photo_required = true THEN 1 END) AS photo_required_count,
        COUNT(CASE WHEN tr.photo_required = true AND tr.photos IS NOT NULL AND tr.photos::text != '[]' AND tr.photos::text != 'null' THEN 1 END) AS photo_completed_count
    FROM inspection_tasks it
    LEFT JOIN breezeway.task_requirements tr ON tr.task_pk = it.task_pk
    GROUP BY it.task_pk, it.region_code, it.property_pk, it.task_status_stage,
             it.finished_by_id, it.finished_by_name
),
-- Property-level aggregation
property_compliance AS (
    SELECT
        'property'::text AS entity_type,
        p.property_name AS entity_name,
        p.property_id::text AS entity_id,
        rs.region_code,
        rs.property_pk,
        COUNT(*) AS total_inspections,
        COUNT(CASE WHEN rs.task_status_stage = 'finished' THEN 1 END) AS completed_inspections,
        SUM(rs.total_requirements) AS total_requirements,
        SUM(rs.completed_requirements) AS completed_requirements,
        ROUND(
            SUM(rs.completed_requirements)::numeric /
            NULLIF(SUM(rs.total_requirements), 0) * 100, 1
        ) AS requirement_completion_rate,
        SUM(rs.photo_required_count) AS total_photos_required,
        SUM(rs.photo_completed_count) AS photos_completed,
        ROUND(
            SUM(rs.photo_completed_count)::numeric /
            NULLIF(SUM(rs.photo_required_count), 0) * 100, 1
        ) AS photo_compliance_rate,
        NULL::text AS performance_classification
    FROM requirement_stats rs
    JOIN breezeway.properties p ON rs.property_pk = p.id
    GROUP BY p.property_name, p.property_id, rs.region_code, rs.property_pk
),
-- Inspector-level aggregation
inspector_compliance AS (
    SELECT
        'inspector'::text AS entity_type,
        rs.finished_by_name AS entity_name,
        rs.finished_by_id AS entity_id,
        rs.region_code,
        NULL::bigint AS property_pk,
        COUNT(*) AS total_inspections,
        COUNT(CASE WHEN rs.task_status_stage = 'finished' THEN 1 END) AS completed_inspections,
        SUM(rs.total_requirements) AS total_requirements,
        SUM(rs.completed_requirements) AS completed_requirements,
        ROUND(
            SUM(rs.completed_requirements)::numeric /
            NULLIF(SUM(rs.total_requirements), 0) * 100, 1
        ) AS requirement_completion_rate,
        SUM(rs.photo_required_count) AS total_photos_required,
        SUM(rs.photo_completed_count) AS photos_completed,
        ROUND(
            SUM(rs.photo_completed_count)::numeric /
            NULLIF(SUM(rs.photo_required_count), 0) * 100, 1
        ) AS photo_compliance_rate,
        CASE
            WHEN ROUND(SUM(rs.completed_requirements)::numeric /
                       NULLIF(SUM(rs.total_requirements), 0) * 100, 1) >= 95
                 AND ROUND(SUM(rs.photo_completed_count)::numeric /
                           NULLIF(SUM(rs.photo_required_count), 0) * 100, 1) >= 90
            THEN 'Excellent'
            WHEN ROUND(SUM(rs.completed_requirements)::numeric /
                       NULLIF(SUM(rs.total_requirements), 0) * 100, 1) >= 80
            THEN 'Good'
            WHEN ROUND(SUM(rs.completed_requirements)::numeric /
                       NULLIF(SUM(rs.total_requirements), 0) * 100, 1) >= 60
            THEN 'Developing'
            ELSE 'Needs Improvement'
        END AS performance_classification
    FROM requirement_stats rs
    WHERE rs.finished_by_name IS NOT NULL
      AND rs.finished_by_name != ''
    GROUP BY rs.finished_by_name, rs.finished_by_id, rs.region_code
    HAVING COUNT(*) >= 3  -- Minimum inspections for meaningful stats
)
SELECT
    entity_type,
    entity_name,
    entity_id,
    region_code,
    property_pk,
    total_inspections,
    completed_inspections,
    total_requirements,
    completed_requirements,
    requirement_completion_rate,
    total_photos_required,
    photos_completed,
    photo_compliance_rate,
    performance_classification,
    CURRENT_TIMESTAMP AS refreshed_at
FROM property_compliance

UNION ALL

SELECT
    entity_type,
    entity_name,
    entity_id,
    region_code,
    property_pk,
    total_inspections,
    completed_inspections,
    total_requirements,
    completed_requirements,
    requirement_completion_rate,
    total_photos_required,
    photos_completed,
    photo_compliance_rate,
    performance_classification,
    CURRENT_TIMESTAMP AS refreshed_at
FROM inspector_compliance
ORDER BY entity_type, region_code, total_inspections DESC
WITH NO DATA;


-- ============================================================================
-- STEP 2c: HOUSEKEEPING SCHEDULE PERFORMANCE
-- Per-worker housekeeping metrics (90d, min 5 tasks)
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_housekeeping_schedule_performance CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_housekeeping_schedule_performance AS
WITH worker_metrics AS (
    SELECT
        t.finished_by_name AS worker_name,
        t.finished_by_id AS worker_id,
        t.region_code,

        -- Volume
        COUNT(*) AS tasks_90d,
        COUNT(CASE WHEN t.finished_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS tasks_30d,
        COUNT(CASE WHEN t.finished_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) AS tasks_7d,
        COUNT(DISTINCT t.property_pk) AS distinct_properties,
        COUNT(DISTINCT DATE(t.finished_at)) AS active_days,

        -- Timing
        ROUND(AVG(CASE WHEN t.started_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (t.finished_at - t.started_at)) / 60 END)::numeric, 1) AS avg_active_minutes,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY CASE WHEN t.started_at IS NOT NULL
                THEN EXTRACT(EPOCH FROM (t.finished_at - t.started_at)) / 60 END
        )::numeric, 1) AS median_active_minutes,

        -- On-time rate: finished_at::date <= scheduled_date
        COUNT(CASE WHEN t.scheduled_date IS NOT NULL
                    AND t.finished_at::date <= t.scheduled_date THEN 1 END) AS on_time_count,
        COUNT(CASE WHEN t.scheduled_date IS NOT NULL THEN 1 END) AS scheduled_count,
        ROUND(
            COUNT(CASE WHEN t.scheduled_date IS NOT NULL
                        AND t.finished_at::date <= t.scheduled_date THEN 1 END)::numeric /
            NULLIF(COUNT(CASE WHEN t.scheduled_date IS NOT NULL THEN 1 END), 0) * 100, 1
        ) AS on_time_rate

    FROM breezeway.tasks t
    WHERE t.type_department = 'housekeeping'
      AND t.task_status_stage = 'finished'
      AND t.finished_by_name IS NOT NULL
      AND t.finished_by_name != ''
      AND t.finished_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY t.finished_by_name, t.finished_by_id, t.region_code
    HAVING COUNT(*) >= 5  -- Minimum 5 tasks
),
regional_context AS (
    SELECT
        region_code,
        ROUND(AVG(avg_active_minutes)::numeric, 1) AS region_avg_active_minutes,
        ROUND(AVG(on_time_rate)::numeric, 1) AS region_avg_on_time_rate
    FROM worker_metrics
    GROUP BY region_code
)
SELECT
    wm.worker_name,
    wm.worker_id,
    wm.region_code,

    -- Volume
    wm.tasks_90d,
    wm.tasks_30d,
    wm.tasks_7d,
    wm.distinct_properties,
    wm.active_days,

    -- Timing
    wm.avg_active_minutes,
    wm.median_active_minutes,
    wm.on_time_rate,

    -- Throughput
    ROUND(wm.tasks_90d::numeric / NULLIF(wm.active_days, 0), 2) AS tasks_per_active_day,
    ROUND(wm.distinct_properties::numeric / NULLIF(wm.active_days, 0), 2) AS properties_per_active_day,

    -- Regional context
    rc.region_avg_active_minutes,
    rc.region_avg_on_time_rate,

    -- Performance band
    CASE
        WHEN wm.on_time_rate >= 90 AND wm.tasks_90d >= (
            SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tasks_90d)
            FROM worker_metrics wm2 WHERE wm2.region_code = wm.region_code
        ) THEN 'Top Performer'
        WHEN wm.on_time_rate >= 75 THEN 'Solid'
        WHEN wm.on_time_rate >= 60 THEN 'Developing'
        ELSE 'Needs Coaching'
    END AS performance_band,

    -- Rankings
    DENSE_RANK() OVER (PARTITION BY wm.region_code ORDER BY wm.on_time_rate DESC NULLS LAST) AS regional_on_time_rank,
    DENSE_RANK() OVER (PARTITION BY wm.region_code ORDER BY wm.tasks_90d DESC) AS regional_volume_rank,

    CURRENT_TIMESTAMP AS refreshed_at
FROM worker_metrics wm
LEFT JOIN regional_context rc ON wm.region_code = rc.region_code
ORDER BY wm.region_code, wm.tasks_90d DESC
WITH NO DATA;


-- ============================================================================
-- STEP 2d: DEPARTMENT SLA TRACKER
-- SLA compliance dashboard per region + department
-- SLA targets: urgent=4h, high=24h, normal=72h, low=168h, watch=336h
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_department_sla_tracker CASCADE;

CREATE MATERIALIZED VIEW breezeway.mv_department_sla_tracker AS
WITH sla_targets AS (
    SELECT * FROM (VALUES
        ('urgent', 4),
        ('high', 24),
        ('normal', 72),
        ('low', 168),
        ('watch', 336)
    ) AS t(priority, sla_hours)
),
open_tasks AS (
    SELECT
        t.region_code,
        t.type_department,
        t.type_priority,
        t.id AS task_pk,
        t.created_at,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - t.created_at)) / 3600 AS age_hours,
        st.sla_hours
    FROM breezeway.tasks t
    LEFT JOIN sla_targets st ON t.type_priority = st.priority
    WHERE t.task_status_stage IN ('new', 'in_progress')
),
open_summary AS (
    SELECT
        region_code,
        type_department,
        COUNT(*) AS total_open,
        COUNT(CASE WHEN sla_hours IS NOT NULL AND age_hours <= sla_hours THEN 1 END) AS compliant,
        COUNT(CASE WHEN sla_hours IS NOT NULL AND age_hours > sla_hours * 0.75 AND age_hours <= sla_hours THEN 1 END) AS warning,
        COUNT(CASE WHEN sla_hours IS NOT NULL AND age_hours > sla_hours THEN 1 END) AS breached,
        ROUND(
            COUNT(CASE WHEN sla_hours IS NOT NULL AND age_hours > sla_hours THEN 1 END)::numeric /
            NULLIF(COUNT(CASE WHEN sla_hours IS NOT NULL THEN 1 END), 0) * 100, 1
        ) AS breach_rate,
        -- Priority breakdown: open counts
        COUNT(CASE WHEN type_priority = 'urgent' THEN 1 END) AS urgent_open,
        COUNT(CASE WHEN type_priority = 'high' THEN 1 END) AS high_open,
        COUNT(CASE WHEN type_priority = 'normal' THEN 1 END) AS normal_open,
        -- Priority breakdown: breached counts
        COUNT(CASE WHEN type_priority = 'urgent' AND sla_hours IS NOT NULL AND age_hours > sla_hours THEN 1 END) AS urgent_breached,
        COUNT(CASE WHEN type_priority = 'high' AND sla_hours IS NOT NULL AND age_hours > sla_hours THEN 1 END) AS high_breached,
        COUNT(CASE WHEN type_priority = 'normal' AND sla_hours IS NOT NULL AND age_hours > sla_hours THEN 1 END) AS normal_breached
    FROM open_tasks
    GROUP BY region_code, type_department
),
-- 7-day trend: completions and SLA compliance
recent_completed AS (
    SELECT
        t.region_code,
        t.type_department,
        COUNT(*) AS completions_7d,
        ROUND(
            COUNT(CASE
                WHEN st.sla_hours IS NOT NULL
                     AND EXTRACT(EPOCH FROM (t.finished_at - t.created_at)) / 3600 <= st.sla_hours
                THEN 1 END)::numeric /
            NULLIF(COUNT(CASE WHEN st.sla_hours IS NOT NULL THEN 1 END), 0) * 100, 1
        ) AS sla_compliance_rate_7d,
        ROUND(AVG(EXTRACT(EPOCH FROM (t.finished_at - t.created_at)) / 3600)::numeric, 1) AS avg_resolution_hours_7d
    FROM breezeway.tasks t
    LEFT JOIN sla_targets st ON t.type_priority = st.priority
    WHERE t.task_status_stage = 'finished'
      AND t.finished_at >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY t.region_code, t.type_department
)
SELECT
    os.region_code,
    os.type_department,

    -- Current open tasks
    os.total_open,
    os.compliant,
    os.warning,
    os.breached,
    os.breach_rate,

    -- Priority breakdown
    os.urgent_open,
    os.high_open,
    os.normal_open,
    os.urgent_breached,
    os.high_breached,
    os.normal_breached,

    -- 7-day trend
    COALESCE(rc.completions_7d, 0) AS completions_7d,
    rc.sla_compliance_rate_7d,
    rc.avg_resolution_hours_7d,

    -- Health status
    CASE
        WHEN COALESCE(os.breach_rate, 0) <= 5 THEN 'Healthy'
        WHEN COALESCE(os.breach_rate, 0) <= 15 THEN 'At Risk'
        WHEN COALESCE(os.breach_rate, 0) <= 30 THEN 'Degraded'
        ELSE 'Critical'
    END AS health_status,

    CURRENT_TIMESTAMP AS refreshed_at
FROM open_summary os
LEFT JOIN recent_completed rc ON os.region_code = rc.region_code AND os.type_department = rc.type_department
ORDER BY
    CASE
        WHEN COALESCE(os.breach_rate, 0) > 30 THEN 1
        WHEN COALESCE(os.breach_rate, 0) > 15 THEN 2
        WHEN COALESCE(os.breach_rate, 0) > 5 THEN 3
        ELSE 4
    END,
    os.region_code,
    os.type_department
WITH NO DATA;


-- ============================================================================
-- STEP 3: REFRESH ALL 6 NEW VIEWS
-- ============================================================================
REFRESH MATERIALIZED VIEW breezeway.mv_property_dashboard;
REFRESH MATERIALIZED VIEW breezeway.mv_regional_dashboard;
REFRESH MATERIALIZED VIEW breezeway.mv_daily_turnover_board;
REFRESH MATERIALIZED VIEW breezeway.mv_inspection_compliance;
REFRESH MATERIALIZED VIEW breezeway.mv_housekeeping_schedule_performance;
REFRESH MATERIALIZED VIEW breezeway.mv_department_sla_tracker;


-- ============================================================================
-- STEP 4: DROP REPLACED VIEWS
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_task_density CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_maintenance_burden CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_property_operational_health CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_regional_performance_scorecard CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_regional_workload_distribution CASCADE;
DROP MATERIALIZED VIEW IF EXISTS breezeway.mv_task_backlog_aging CASCADE;


-- ============================================================================
-- STEP 5: CREATE INDEXES ON NEW VIEWS
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_mv_prop_dashboard_region ON breezeway.mv_property_dashboard(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_prop_dashboard_health ON breezeway.mv_property_dashboard(health_score DESC);
CREATE INDEX IF NOT EXISTS idx_mv_prop_dashboard_pk ON breezeway.mv_property_dashboard(property_pk);
CREATE INDEX IF NOT EXISTS idx_mv_regional_dashboard_region ON breezeway.mv_regional_dashboard(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_turnover_checkout ON breezeway.mv_daily_turnover_board(checkout_date);
CREATE INDEX IF NOT EXISTS idx_mv_turnover_region ON breezeway.mv_daily_turnover_board(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_inspection_entity ON breezeway.mv_inspection_compliance(entity_type, region_code);
CREATE INDEX IF NOT EXISTS idx_mv_hk_perf_region ON breezeway.mv_housekeeping_schedule_performance(region_code);
CREATE INDEX IF NOT EXISTS idx_mv_sla_tracker_region ON breezeway.mv_department_sla_tracker(region_code, type_department);
CREATE INDEX IF NOT EXISTS idx_mv_sla_tracker_health ON breezeway.mv_department_sla_tracker(health_status);


-- ============================================================================
-- STEP 6: GRANT PERMISSIONS
-- ============================================================================
GRANT SELECT ON breezeway.mv_property_dashboard TO breezeway;
GRANT SELECT ON breezeway.mv_regional_dashboard TO breezeway;
GRANT SELECT ON breezeway.mv_daily_turnover_board TO breezeway;
GRANT SELECT ON breezeway.mv_inspection_compliance TO breezeway;
GRANT SELECT ON breezeway.mv_housekeeping_schedule_performance TO breezeway;
GRANT SELECT ON breezeway.mv_department_sla_tracker TO breezeway;


COMMIT;


-- ============================================================================
-- STEP 7: UPDATE REFRESH FUNCTION (requires function owner / superuser)
-- The function is owned by postgres, so this must run as postgres.
-- Run separately: sudo -u postgres psql -d breezeway -f <this_file>
-- or the block below if running as superuser.
-- ============================================================================
CREATE OR REPLACE FUNCTION breezeway.refresh_dashboard_views()
RETURNS void AS $$
BEGIN
    -- Core dashboards
    REFRESH MATERIALIZED VIEW breezeway.mv_regional_dashboard;
    REFRESH MATERIALIZED VIEW breezeway.mv_property_dashboard;

    -- Worker leaderboards
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_housekeeping;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_inspection;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_leaderboard_maintenance;
    REFRESH MATERIALIZED VIEW breezeway.mv_worker_efficiency_ranking;

    -- Task analytics
    REFRESH MATERIALIZED VIEW breezeway.mv_task_completion_metrics;
    REFRESH MATERIALIZED VIEW breezeway.mv_priority_response_times;
    REFRESH MATERIALIZED VIEW breezeway.mv_department_sla_tracker;

    -- Property & reservation
    REFRESH MATERIALIZED VIEW breezeway.mv_reservation_turnaround_analysis;
    REFRESH MATERIALIZED VIEW breezeway.mv_daily_turnover_board;

    -- Department-specific
    REFRESH MATERIALIZED VIEW breezeway.mv_inspection_compliance;
    REFRESH MATERIALIZED VIEW breezeway.mv_housekeeping_schedule_performance;

    -- Trends & patterns
    REFRESH MATERIALIZED VIEW breezeway.mv_monthly_trend_analysis;
    REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;
    REFRESH MATERIALIZED VIEW breezeway.mv_seasonal_demand_patterns;

    -- Meta
    REFRESH MATERIALIZED VIEW breezeway.mv_task_tags_analysis;
    REFRESH MATERIALIZED VIEW breezeway.mv_operational_alerts;

    RAISE NOTICE 'All 18 dashboard views refreshed at %', CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- VERIFICATION QUERIES (run manually after migration)
-- ============================================================================
-- SELECT 'mv_property_dashboard' AS view_name, COUNT(*) AS rows FROM breezeway.mv_property_dashboard
-- UNION ALL SELECT 'mv_regional_dashboard', COUNT(*) FROM breezeway.mv_regional_dashboard
-- UNION ALL SELECT 'mv_daily_turnover_board', COUNT(*) FROM breezeway.mv_daily_turnover_board
-- UNION ALL SELECT 'mv_inspection_compliance', COUNT(*) FROM breezeway.mv_inspection_compliance
-- UNION ALL SELECT 'mv_housekeeping_schedule_performance', COUNT(*) FROM breezeway.mv_housekeeping_schedule_performance
-- UNION ALL SELECT 'mv_department_sla_tracker', COUNT(*) FROM breezeway.mv_department_sla_tracker;
--
-- Confirm old views are gone:
-- SELECT matviewname FROM pg_matviews WHERE schemaname = 'breezeway' ORDER BY matviewname;
--
-- Expected: 16 materialized views total

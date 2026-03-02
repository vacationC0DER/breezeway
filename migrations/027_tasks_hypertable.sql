-- ============================================================================
-- Migration 027: Convert tasks to Hypertable + Create Continuous Aggregates
-- Date: 2026-03-02
-- Purpose: Phase 4 + Phase 3 of TimescaleDB integration
--
--   Step 1: Drop foreign key constraints from child tables
--   Step 2: Change unique constraint to include created_at (partition column)
--   Step 3: Convert tasks to a hypertable
--   Step 4: Create base continuous aggregates
--   Step 5: Update refresh function to skip auto-refreshed aggregates
--
-- RISK: HIGH - Run during maintenance window with ETL paused
--
-- Prerequisites:
--   - Migration 025 (timescaledb extension installed)
--   - Migration 026 (time_bucket views)
--   - ETL pipeline MUST be stopped before running this migration
--
-- Verification:
--   1. Run: python etl/run_etl.py all all
--   2. Compare task row counts pre/post
--   3. Run ETL twice, verify no duplicates
--   4. Wait 1 hour, check: SELECT * FROM timescaledb_information.continuous_aggregate_stats;
-- ============================================================================


-- ============================================================================
-- STEP 1: DROP FOREIGN KEY CONSTRAINTS FROM CHILD TABLES
-- TimescaleDB hypertables cannot be referenced by foreign keys.
-- Referential integrity is enforced in ETL code via _resolve_parent_fks()
-- and _upsert_children() in etl/etl_base.py.
-- ============================================================================

-- Inbound FKs: child tables → tasks (blocks hypertable conversion)
ALTER TABLE breezeway.task_assignments DROP CONSTRAINT IF EXISTS fk_assignment_task;
ALTER TABLE breezeway.task_photos DROP CONSTRAINT IF EXISTS fk_task_photo_task;
ALTER TABLE breezeway.task_comments DROP CONSTRAINT IF EXISTS fk_comment_task;
ALTER TABLE breezeway.task_requirements DROP CONSTRAINT IF EXISTS fk_requirement_task;
ALTER TABLE breezeway.task_tags DROP CONSTRAINT IF EXISTS fk_task_tags_task;
ALTER TABLE breezeway.task_supplies DROP CONSTRAINT IF EXISTS task_supplies_task_pk_fkey;
ALTER TABLE breezeway.task_costs DROP CONSTRAINT IF EXISTS task_costs_task_pk_fkey;

-- Outbound FKs: tasks → parent tables (must drop for hypertable conversion)
ALTER TABLE breezeway.tasks DROP CONSTRAINT IF EXISTS fk_task_property;
ALTER TABLE breezeway.tasks DROP CONSTRAINT IF EXISTS fk_task_region;
ALTER TABLE breezeway.tasks DROP CONSTRAINT IF EXISTS fk_task_reservation;


-- ============================================================================
-- STEP 2: CHANGE UNIQUE CONSTRAINT TO INCLUDE PARTITION COLUMN
-- TimescaleDB requires the partition column (created_at) in all unique
-- constraints and primary keys.
-- ============================================================================

-- Drop old unique constraint (actual name from live DB: unique_task_region)
ALTER TABLE breezeway.tasks DROP CONSTRAINT IF EXISTS unique_task_region;

-- Add new constraint including the time partition column
ALTER TABLE breezeway.tasks ADD CONSTRAINT unique_task_region
    UNIQUE (task_id, region_code, created_at);

-- Fix primary key: TimescaleDB requires partition column in ALL unique indexes/PKs
ALTER TABLE breezeway.tasks DROP CONSTRAINT IF EXISTS breezeaway_tasks_gw_pkey;
ALTER TABLE breezeway.tasks ADD CONSTRAINT tasks_pkey PRIMARY KEY (id, created_at);


-- ============================================================================
-- STEP 3: CONVERT TASKS TO HYPERTABLE
-- migrate_data => true moves existing rows into chunks.
-- 30-day chunk interval balances query performance and chunk count.
-- ============================================================================

SELECT create_hypertable('breezeway.tasks', 'created_at',
    migrate_data => true,
    chunk_time_interval => INTERVAL '30 days');


-- ============================================================================
-- STEP 4: CREATE BASE CONTINUOUS AGGREGATES
-- These pre-compute the heavy time-bucketed GROUP BY aggregations.
-- Existing views with window functions (LAG, DENSE_RANK, PERCENTILE_CONT)
-- cannot be continuous aggregates, but they can SELECT from these base
-- aggregates for much faster refresh.
-- ============================================================================

-- 4a. Daily task metrics by region and department
DROP MATERIALIZED VIEW IF EXISTS breezeway.cagg_task_daily_metrics CASCADE;

CREATE MATERIALIZED VIEW breezeway.cagg_task_daily_metrics
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', created_at) AS bucket,
    region_code,
    type_department,
    COUNT(*) AS tasks_created,
    COUNT(*) FILTER (WHERE task_status_stage = 'finished') AS tasks_completed,
    COUNT(*) FILTER (WHERE task_status_stage = 'new') AS tasks_new,
    COUNT(*) FILTER (WHERE task_status_stage = 'in_progress') AS tasks_in_progress,
    COUNT(*) FILTER (WHERE type_priority = 'urgent') AS urgent_tasks,
    COUNT(*) FILTER (WHERE type_priority = 'high') AS high_tasks,
    COUNT(DISTINCT finished_by_id) AS unique_workers,
    AVG(EXTRACT(EPOCH FROM (finished_at - created_at)) / 3600)
        FILTER (WHERE task_status_stage = 'finished') AS avg_hours_to_complete
FROM breezeway.tasks
GROUP BY bucket, region_code, type_department;

-- Auto-refresh policy: refresh data from 3 days ago to 1 hour ago, every hour
SELECT add_continuous_aggregate_policy('breezeway.cagg_task_daily_metrics',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');


-- 4b. Monthly task metrics by region and department
DROP MATERIALIZED VIEW IF EXISTS breezeway.cagg_task_monthly_metrics CASCADE;

CREATE MATERIALIZED VIEW breezeway.cagg_task_monthly_metrics
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 month', created_at) AS bucket,
    region_code,
    type_department,
    COUNT(*) AS tasks_created,
    COUNT(*) FILTER (WHERE task_status_stage = 'finished') AS tasks_completed,
    COUNT(*) FILTER (WHERE type_priority = 'urgent') AS urgent_tasks,
    COUNT(*) FILTER (WHERE type_priority = 'high') AS high_tasks,
    COUNT(DISTINCT finished_by_id) AS unique_workers,
    AVG(EXTRACT(EPOCH FROM (finished_at - created_at)) / 3600)
        FILTER (WHERE task_status_stage = 'finished') AS avg_hours_to_complete
FROM breezeway.tasks
GROUP BY bucket, region_code, type_department;

-- Auto-refresh policy: refresh monthly buckets, every hour
SELECT add_continuous_aggregate_policy('breezeway.cagg_task_monthly_metrics',
    start_offset => INTERVAL '3 months',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');


-- Grant permissions on continuous aggregates
GRANT SELECT ON breezeway.cagg_task_daily_metrics TO breezeway;
GRANT SELECT ON breezeway.cagg_task_monthly_metrics TO breezeway;


-- ============================================================================
-- STEP 5: UPDATE REFRESH FUNCTION
-- Remove continuous aggregates from manual refresh (TimescaleDB auto-refreshes
-- them via policies). Add the continuous aggregates as comments for reference.
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

    -- NOTE: Continuous aggregates are auto-refreshed by TimescaleDB policies:
    --   breezeway.cagg_task_daily_metrics   (hourly, 3-day lookback)
    --   breezeway.cagg_task_monthly_metrics  (hourly, 3-month lookback)

    RAISE NOTICE 'All 18 dashboard views refreshed at %. Continuous aggregates are auto-refreshed by TimescaleDB.', CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- STEP 6: REFRESH ALL VIEWS TO VERIFY THEY WORK WITH HYPERTABLE
-- ============================================================================
SELECT breezeway.refresh_dashboard_views();

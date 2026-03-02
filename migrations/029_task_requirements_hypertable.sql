-- ============================================================================
-- Migration 029: Convert task_requirements to Hypertable
-- Date: 2026-03-02
-- Purpose: Deduplicate and convert task_requirements to TimescaleDB hypertable
--
--   Step 1: Deduplicate massive row bloat (27M → 66K rows)
--   Step 2: Sync created_at from parent tasks table
--   Step 3: Drop old constraints and create new ones with partition column
--   Step 4: Convert to hypertable
--   Step 5: Enable compression
--
-- RISK: HIGH - Run during maintenance window with ETL paused
--
-- Prerequisites:
--   - Migration 025 (timescaledb extension installed)
--   - Migration 027 (tasks hypertable)
--   - ETL pipeline MUST be stopped before running this migration
--
-- Background:
--   task_requirements had 27M rows but only 66K unique records due to
--   duplicate inserts over time. After dedup: 8.7 GB → 28 MB.
--
-- Verification:
--   1. Run: python etl/run_etl.py all all
--   2. Verify no duplicate rows
--   3. Check compression: SELECT * FROM timescaledb_information.compressed_chunk_stats
--      WHERE hypertable_name = 'task_requirements';
-- ============================================================================


-- ============================================================================
-- STEP 1: DEDUPLICATE ROWS
-- Use a temp table approach for speed (DELETE with subquery is too slow on 27M rows)
-- ============================================================================

CREATE TEMP TABLE task_requirements_deduped AS
SELECT DISTINCT ON (task_pk, requirement_id)
    *
FROM breezeway.task_requirements
ORDER BY task_pk, requirement_id, id;

TRUNCATE breezeway.task_requirements;

INSERT INTO breezeway.task_requirements
SELECT * FROM task_requirements_deduped;

DROP TABLE task_requirements_deduped;


-- ============================================================================
-- STEP 2: SYNC created_at FROM PARENT TASKS
-- Hypertable UPSERT requires created_at in conflict target.
-- Copy parent task's created_at to requirements so the ETL can match on it.
-- ============================================================================

UPDATE breezeway.task_requirements tr
SET created_at = t.created_at
FROM breezeway.tasks t
WHERE tr.task_pk = t.id
  AND tr.created_at IS NULL;

-- Backfill any orphan rows that have no parent match
UPDATE breezeway.task_requirements
SET created_at = '2020-01-01'::timestamptz
WHERE created_at IS NULL;

-- Ensure NOT NULL going forward
ALTER TABLE breezeway.task_requirements ALTER COLUMN created_at SET NOT NULL;


-- ============================================================================
-- STEP 3: DROP OLD CONSTRAINTS AND CREATE NEW ONES
-- TimescaleDB requires partition column in ALL unique constraints and PKs.
-- ============================================================================

-- Drop existing primary key
ALTER TABLE breezeway.task_requirements DROP CONSTRAINT IF EXISTS task_requirements_pkey;

-- Drop existing unique constraint
ALTER TABLE breezeway.task_requirements DROP CONSTRAINT IF EXISTS task_requirements_task_pk_requirement_id_key;

-- Create new PK with partition column
ALTER TABLE breezeway.task_requirements
    ADD CONSTRAINT task_requirements_pkey PRIMARY KEY (id, created_at);

-- Create new unique constraint with partition column
ALTER TABLE breezeway.task_requirements
    ADD CONSTRAINT task_requirements_task_pk_requirement_id_created_at_key
    UNIQUE (task_pk, requirement_id, created_at);


-- ============================================================================
-- STEP 4: CONVERT TO HYPERTABLE
-- 30-day chunk interval matches tasks table.
-- ============================================================================

SELECT create_hypertable('breezeway.task_requirements', 'created_at',
    migrate_data => true,
    chunk_time_interval => INTERVAL '30 days');


-- ============================================================================
-- STEP 5: ENABLE COMPRESSION
-- Segment by task_pk for efficient queries per task.
-- ============================================================================

ALTER TABLE breezeway.task_requirements SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'task_pk',
    timescaledb.compress_orderby = 'created_at DESC'
);

-- Compress chunks older than 90 days
SELECT add_compression_policy('breezeway.task_requirements', INTERVAL '90 days');

-- Manually compress all eligible chunks
SELECT compress_chunk(c.chunk_name::regclass)
FROM timescaledb_information.chunks c
WHERE c.hypertable_name = 'task_requirements'
  AND c.range_end < NOW() - INTERVAL '90 days'
  AND NOT c.is_compressed;

-- ============================================================================
-- Migration 025: Install TimescaleDB Extension + ETL Sync History Hypertable
-- Date: 2026-03-02
-- Purpose: Phase 1 of TimescaleDB integration
--   1a. Install timescaledb extension
--   1b. Create append-only etl_sync_history hypertable
--   1c. Add retention policy (1 year)
--   1e. Add compression for old history (90 days)
--
-- Prerequisites:
--   TimescaleDB must be installed on the PostgreSQL server.
--   Verify with: SELECT default_version, installed_version
--                FROM pg_available_extensions WHERE name = 'timescaledb';
-- ============================================================================

-- 1a. Install the extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 1b. Create append-only sync history table
-- The existing etl_sync_log is a status table (upserted per region/entity).
-- This new table is append-only: one row per sync attempt for full history.
CREATE TABLE IF NOT EXISTS breezeway.etl_sync_history (
    id BIGSERIAL,
    region_code VARCHAR(32) NOT NULL,
    entity_type VARCHAR(32) NOT NULL,
    sync_status VARCHAR(32) NOT NULL,
    sync_started_at TIMESTAMPTZ NOT NULL,
    sync_completed_at TIMESTAMPTZ,
    records_processed INT DEFAULT 0,
    records_new INT DEFAULT 0,
    records_updated INT DEFAULT 0,
    records_deleted INT DEFAULT 0,
    api_calls_made INT DEFAULT 0,
    error_message TEXT,
    duration_seconds NUMERIC(10,2)
);

-- Convert to hypertable partitioned by sync_started_at
SELECT create_hypertable('breezeway.etl_sync_history', 'sync_started_at',
    if_not_exists => true);

-- 1c. Retention policy: automatically drop chunks older than 1 year
SELECT add_retention_policy('breezeway.etl_sync_history', INTERVAL '1 year',
    if_not_exists => true);

-- 1e. Compression for history older than 90 days
ALTER TABLE breezeway.etl_sync_history SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'region_code, entity_type',
    timescaledb.compress_orderby = 'sync_started_at DESC'
);

SELECT add_compression_policy('breezeway.etl_sync_history', INTERVAL '90 days',
    if_not_exists => true);

-- Grant permissions
GRANT SELECT, INSERT ON breezeway.etl_sync_history TO breezeway;
GRANT USAGE, SELECT ON SEQUENCE breezeway.etl_sync_history_id_seq TO breezeway;

-- Create index for common queries
CREATE INDEX IF NOT EXISTS idx_sync_history_region_entity
    ON breezeway.etl_sync_history (region_code, entity_type, sync_started_at DESC);

-- ============================================================================
-- Migration 028: Compression Policy for Tasks Hypertable
-- Date: 2026-03-02
-- Purpose: Phase 5 of TimescaleDB integration
--   Enable compression on the tasks hypertable for chunks older than 90 days.
--   Tasks outside the 90-day window are rarely re-synced by the ETL pipeline
--   and are outside the dashboard query windows (7/30/90 day).
--
-- Prerequisites:
--   - Migration 027 (tasks converted to hypertable)
--
-- Notes:
--   - The ETL pipeline logs a warning when attempting to UPSERT records with
--     created_at older than 90 days, as these would hit compressed chunks.
--   - To manually decompress a chunk for backfill:
--       SELECT decompress_chunk('<chunk_name>');
--   - To check compression status:
--       SELECT * FROM timescaledb_information.compressed_chunk_stats
--       WHERE hypertable_name = 'tasks';
-- ============================================================================

-- Enable compression settings
ALTER TABLE breezeway.tasks SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'region_code',
    timescaledb.compress_orderby = 'created_at DESC'
);

-- Compress chunks older than 90 days automatically
SELECT add_compression_policy('breezeway.tasks', INTERVAL '90 days',
    if_not_exists => true);

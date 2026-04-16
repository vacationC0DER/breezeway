-- Migration 031: Add retention policy for webhook_events
-- Deletes processed events older than 90 days

-- Add index to support efficient deletion
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_webhook_events_retention
    ON breezeway.webhook_events (received_at)
    WHERE processed = true;

-- Preview what will be deleted
DO $$
DECLARE
    total_count INTEGER;
    keep_count INTEGER;
BEGIN
    SELECT count(*) INTO total_count FROM breezeway.webhook_events;
    SELECT count(*) INTO keep_count FROM breezeway.webhook_events
        WHERE received_at > NOW() - INTERVAL '90 days' OR processed = false;
    RAISE NOTICE 'Total events: %, Events to keep: %, Events to delete: %',
        total_count, keep_count, total_count - keep_count;
END $$;

-- Delete ALL old processed events in batches (loop until done)
DO $$
DECLARE
    rows_deleted INTEGER;
    total_deleted INTEGER := 0;
BEGIN
    LOOP
        DELETE FROM breezeway.webhook_events
        WHERE id IN (
            SELECT id FROM breezeway.webhook_events
            WHERE received_at < NOW() - INTERVAL '90 days'
              AND processed = true
            LIMIT 50000
        );
        GET DIAGNOSTICS rows_deleted = ROW_COUNT;
        total_deleted := total_deleted + rows_deleted;
        EXIT WHEN rows_deleted = 0;
        RAISE NOTICE 'Deleted batch of % rows (total: %)', rows_deleted, total_deleted;
        PERFORM pg_sleep(0.5);
    END LOOP;
    RAISE NOTICE 'Retention cleanup complete: % rows deleted', total_deleted;
END $$;

-- Reclaim disk space
VACUUM ANALYZE breezeway.webhook_events;

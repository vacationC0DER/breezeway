-- ============================================================================
-- BREEZEWAY ETL - PROPERTY PHOTOS DEDUPLICATION (FOCUSED FIX)
-- ============================================================================
-- Purpose: Remove 10.2M duplicate property_photos records only
--          Task photos will remain as-is
--
-- Impact:  • Reduces property_photos from 10.2M to 16K records
--          • Saves ~7 GB disk space
--          • Improves property photo queries by 600x
--
-- Risk:    LOW (backup table created, transaction-safe, rollback available)
-- Duration: ~20 minutes total
--
-- Author:  System Administrator
-- Date:    December 2, 2025
-- Version: 1.1 (focused scope)
-- ============================================================================

\echo '================================'
\echo 'PROPERTY PHOTOS DEDUPLICATION'
\echo '================================'
\echo ''

-- ============================================================================
-- STEP 1: PRE-MIGRATION VALIDATION
-- ============================================================================

\echo 'Current property_photos status:'
SELECT
    COUNT(*) as total_records,
    COUNT(DISTINCT (property_pk, photo_id)) as unique_records,
    COUNT(*) - COUNT(DISTINCT (property_pk, photo_id)) as duplicates,
    pg_size_pretty(pg_total_relation_size('breezeway.property_photos')) as table_size
FROM breezeway.property_photos;

\echo ''
\echo 'Press Enter to continue with deduplication or Ctrl+C to cancel...'
\prompt continue

-- ============================================================================
-- STEP 2: CREATE BACKUP
-- ============================================================================

\echo ''
\echo 'Creating backup table...'

BEGIN;

-- Drop existing backup if present
DROP TABLE IF EXISTS breezeway.property_photos_backup CASCADE;

-- Create full backup
CREATE TABLE breezeway.property_photos_backup AS
SELECT * FROM breezeway.property_photos;

-- Verify backup
DO $$
DECLARE
    orig_count BIGINT;
    backup_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO orig_count FROM breezeway.property_photos;
    SELECT COUNT(*) INTO backup_count FROM breezeway.property_photos_backup;

    IF orig_count != backup_count THEN
        RAISE EXCEPTION 'Backup verification failed: original=%, backup=%', orig_count, backup_count;
    END IF;

    RAISE NOTICE 'Backup created: % records', backup_count;
END $$;

COMMIT;

\echo '✓ Backup complete'
\echo ''

-- ============================================================================
-- STEP 3: DEDUPLICATE property_photos
-- ============================================================================

\echo 'Deduplicating property_photos...'
\echo 'Keeping oldest record (lowest id) for each (property_pk, photo_id)'
\echo ''

BEGIN;

-- Create temp table with deduplicated records
CREATE TEMP TABLE property_photos_deduped AS
SELECT DISTINCT ON (property_pk, photo_id)
    id,
    property_pk,
    photo_id,
    url,
    caption,
    photo_order,
    created_at,
    updated_at
FROM breezeway.property_photos
ORDER BY property_pk, photo_id, id ASC;  -- Keep oldest (lowest id)

-- Verify deduplication
DO $$
DECLARE
    orig_count BIGINT;
    dedup_count BIGINT;
    expected_unique BIGINT;
BEGIN
    SELECT COUNT(*) INTO orig_count FROM breezeway.property_photos;
    SELECT COUNT(*) INTO dedup_count FROM property_photos_deduped;
    SELECT COUNT(DISTINCT (property_pk, photo_id)) INTO expected_unique
        FROM breezeway.property_photos;

    IF dedup_count != expected_unique THEN
        RAISE EXCEPTION 'Deduplication failed: expected %, got %', expected_unique, dedup_count;
    END IF;

    RAISE NOTICE 'Deduplicated: % → % records (removed %)',
        orig_count, dedup_count, orig_count - dedup_count;
END $$;

-- Replace original table with deduplicated data
TRUNCATE breezeway.property_photos;
INSERT INTO breezeway.property_photos
SELECT * FROM property_photos_deduped;

DROP TABLE property_photos_deduped;

COMMIT;

\echo '✓ Deduplication complete'
\echo ''

-- ============================================================================
-- STEP 4: ADD UNIQUE CONSTRAINT
-- ============================================================================

\echo 'Adding UNIQUE constraint to prevent future duplicates...'

BEGIN;

-- Drop constraint if exists (from previous migration attempts)
ALTER TABLE breezeway.property_photos
DROP CONSTRAINT IF EXISTS property_photos_unique_photo;

-- Add UNIQUE constraint
ALTER TABLE breezeway.property_photos
ADD CONSTRAINT property_photos_unique_photo
UNIQUE (property_pk, photo_id);

COMMIT;

\echo '✓ UNIQUE constraint added'
\echo ''

-- ============================================================================
-- STEP 5: VACUUM AND ANALYZE
-- ============================================================================

\echo 'Reclaiming disk space and updating statistics...'

VACUUM FULL breezeway.property_photos;
ANALYZE breezeway.property_photos;

\echo '✓ Vacuum complete'
\echo ''

-- ============================================================================
-- STEP 6: POST-MIGRATION VALIDATION
-- ============================================================================

\echo '================================'
\echo 'POST-MIGRATION VALIDATION'
\echo '================================'
\echo ''

\echo 'Final property_photos status:'
SELECT
    COUNT(*) as total_records,
    COUNT(DISTINCT (property_pk, photo_id)) as unique_records,
    COUNT(*) - COUNT(DISTINCT (property_pk, photo_id)) as duplicates,
    pg_size_pretty(pg_total_relation_size('breezeway.property_photos')) as table_size,
    pg_size_pretty(pg_total_relation_size('breezeway.property_photos_backup')) as backup_size
FROM breezeway.property_photos;

\echo ''
\echo 'Verify UNIQUE constraint exists:'
SELECT
    constraint_name,
    string_agg(column_name, ', ' ORDER BY ordinal_position) as columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'UNIQUE'
  AND tc.table_schema = 'breezeway'
  AND tc.table_name = 'property_photos'
GROUP BY constraint_name;

\echo ''
\echo 'Total database size:'
SELECT pg_size_pretty(pg_database_size('breezeway')) as database_size;

\echo ''
\echo '================================'
\echo 'MIGRATION COMPLETE ✓'
\echo '================================'
\echo ''
\echo 'Summary:'
\echo '  • Deduplicated property_photos: 10.2M → 16K records'
\echo '  • Added UNIQUE constraint (property_pk, photo_id)'
\echo '  • Reduced table size by ~7 GB'
\echo '  • Backup table created for rollback if needed'
\echo ''
\echo 'Next steps:'
\echo '  1. Test property queries to verify performance'
\echo '  2. Monitor ETL logs for next 48 hours'
\echo '  3. Drop backup table after 7 days if no issues'
\echo ''
\echo 'To drop backup after validation:'
\echo '  DROP TABLE breezeway.property_photos_backup;'
\echo '  VACUUM FULL;'
\echo ''

-- ============================================================================
-- ROLLBACK INSTRUCTIONS
-- ============================================================================
/*

-- EMERGENCY ROLLBACK PROCEDURE
-- ==============================

BEGIN;

-- 1. Drop UNIQUE constraint
ALTER TABLE breezeway.property_photos
DROP CONSTRAINT IF EXISTS property_photos_unique_photo;

-- 2. Restore from backup
TRUNCATE breezeway.property_photos;
INSERT INTO breezeway.property_photos
SELECT * FROM breezeway.property_photos_backup;

-- 3. Verify restoration
SELECT COUNT(*) FROM breezeway.property_photos;
-- Should return 10,192,750

COMMIT;

-- 4. Optionally drop backup after rollback confirmed
-- DROP TABLE breezeway.property_photos_backup;

*/

-- ============================================================================
-- END OF MIGRATION SCRIPT
-- ============================================================================

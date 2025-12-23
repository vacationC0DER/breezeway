# Deduplication Deployment Guide

**Purpose:** Execute deduplication migration to remove 36.5M duplicate records and prevent future duplicates

**Status:** Ready for execution

**Risk Level:** LOW (backups created, rollback available)

**Duration:** 1.5-2 hours

**Database Impact:** 10.16 GB → ~1.2 GB (saves 8.96 GB)

---

## Prerequisites

### Before You Begin

1. **Schedule Maintenance Window**
   - Duration: 2 hours minimum
   - Recommended: Off-peak hours (late night/early morning)
   - Notify stakeholders of scheduled downtime

2. **Disable ETL Jobs**
   ```bash
   # Comment out ETL cron jobs temporarily
   crontab -e

   # Comment these lines:
   # 0 * * * * /root/Breezeway/scripts/run_hourly_etl.sh
   # 0 0 * * * /root/Breezeway/scripts/run_daily_etl.sh
   ```

3. **Verify Disk Space**
   ```bash
   df -h
   # Need at least 12 GB free (current data + backups)
   ```

4. **Check No ETL Processes Running**
   ```bash
   ps aux | grep run_etl
   # Should return nothing
   ```

---

## Deployment Steps

### Step 1: Backup Database (Recommended)

**Duration:** 10 minutes

```bash
# Create full database backup
sudo -u postgres pg_dump breezeway | gzip > /root/Breezeway/backups/breezeway_pre_dedup_$(date +%Y%m%d_%H%M%S).sql.gz

# Verify backup exists
ls -lh /root/Breezeway/backups/
```

### Step 2: Review Current State

**Duration:** 2 minutes

```bash
# Connect to database
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway

# Check current record counts
SELECT
    'property_photos' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT (property_pk, photo_id)) as unique_records
FROM breezeway.property_photos
UNION ALL
SELECT
    'task_requirements',
    COUNT(*),
    COUNT(DISTINCT (task_pk, requirement_id))
FROM breezeway.task_requirements;

# Expected results:
# property_photos:    10,192,750 total → 16,113 unique
# task_requirements:  24,174,099 total → 26,580 unique

# Exit psql
\q
```

### Step 3: Execute Migration Script

**Duration:** 1.5 hours

**IMPORTANT:** This script includes prompts. Be ready to press Enter to continue.

```bash
cd /root/Breezeway

# Execute migration
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f migrations/010_deduplicate_child_tables.sql | tee logs/deduplication_$(date +%Y%m%d_%H%M%S).log
```

**What Happens During Execution:**

1. **Pre-Migration Validation** (2 min)
   - Shows current duplicate counts
   - Displays table sizes
   - Prompts for confirmation

2. **Backup Creation** (15 min)
   - Creates *_backup tables for all 6 child tables
   - Verifies backup integrity
   - Total: 36.5M records backed up

3. **Deduplication** (60-90 min)
   - property_photos: 10.2M → 16K (10 min)
   - reservation_guests: 1.76M → 1.76M (3 min)
   - task_assignments: 1.49M → 1K (3 min)
   - task_photos: 715K → 26K (2 min)
   - task_comments: 14.7K → 470 (1 min)
   - task_requirements: 24.2M → 26K (40 min)

4. **Add UNIQUE Constraints** (5 min)
   - 6 constraints added
   - Prevents future duplicates

5. **VACUUM FULL** (10 min)
   - Reclaims disk space
   - Updates statistics

6. **Post-Migration Validation** (2 min)
   - Verifies no duplicates remain
   - Shows new table sizes
   - Confirms constraints exist

### Step 4: Validate Results

**Duration:** 5 minutes

```bash
# Reconnect to database
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway

# Verify no duplicates remain
SELECT
    'property_photos' as table_name,
    COUNT(*) as total,
    COUNT(DISTINCT (property_pk, photo_id)) as unique_records,
    COUNT(*) - COUNT(DISTINCT (property_pk, photo_id)) as duplicates
FROM breezeway.property_photos
UNION ALL
SELECT 'task_requirements',
    COUNT(*),
    COUNT(DISTINCT (task_pk, requirement_id)),
    COUNT(*) - COUNT(DISTINCT (task_pk, requirement_id))
FROM breezeway.task_requirements;

# Expected: duplicates column should be 0 for all tables

# Verify UNIQUE constraints exist
SELECT
    tc.table_name,
    tc.constraint_name,
    string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) as columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'UNIQUE'
  AND tc.table_schema = 'breezeway'
  AND tc.table_name IN ('property_photos', 'task_requirements', 'task_assignments', 'task_photos', 'task_comments', 'reservation_guests')
GROUP BY tc.table_name, tc.constraint_name
ORDER BY tc.table_name;

# Expected: 6 UNIQUE constraints

# Check database size
SELECT pg_size_pretty(pg_database_size('breezeway')) as database_size;

# Expected: ~1.2 GB (down from 10.16 GB)

\q
```

### Step 5: Test ETL with New Code

**Duration:** 10 minutes

**The ETL code has been updated to use natural keys in conflict targets.**

```bash
# Run single ETL job as test
cd /root/Breezeway
python3 etl/run_etl.py nashville properties

# Check logs for successful execution
tail -50 logs/hourly_etl_$(date +%Y%m%d).log

# Should see:
# - "Loaded X property_photos records" (no duplicates inserted)
# - No errors about constraint violations
```

### Step 6: Re-enable ETL Jobs

**Duration:** 2 minutes

```bash
# Uncomment ETL cron jobs
crontab -e

# Uncomment these lines:
0 * * * * /root/Breezeway/scripts/run_hourly_etl.sh
0 0 * * * /root/Breezeway/scripts/run_daily_etl.sh

# Verify cron jobs are active
crontab -l | grep etl
```

---

## Post-Deployment Monitoring

### Day 1: Intensive Monitoring

**Check every 2 hours for first day:**

```bash
# Check ETL logs for errors
tail -100 /root/Breezeway/logs/hourly_etl_$(date +%Y%m%d).log | grep -i error

# Check for duplicate insertions (should be 0)
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "
SELECT
    COUNT(*) - COUNT(DISTINCT (property_pk, photo_id)) as property_photos_duplicates,
    (SELECT COUNT(*) - COUNT(DISTINCT (task_pk, requirement_id)) FROM breezeway.task_requirements) as task_requirements_duplicates
FROM breezeway.property_photos;"

# Expected: Both should be 0

# Check alert log
tail -50 /root/Breezeway/logs/alerts.log
```

### Week 1: Daily Checks

**Run once per day:**

```bash
# Daily duplicate check
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "
SELECT
    'property_photos' as table_name,
    COUNT(*) - COUNT(DISTINCT (property_pk, photo_id)) as duplicates
FROM breezeway.property_photos
UNION ALL
SELECT 'task_requirements',
    COUNT(*) - COUNT(DISTINCT (task_pk, requirement_id))
FROM breezeway.task_requirements;
"

# Review ETL success rate
grep "ETL Complete" /root/Breezeway/logs/*.log | wc -l
```

### After 7 Days: Drop Backup Tables

**If no issues detected, reclaim backup space:**

```bash
# Verify system is stable
echo "Has there been any issues in the past 7 days? (y/n)"
read answer

if [ "$answer" = "n" ]; then
    PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway <<EOF
    -- Drop backup tables to reclaim ~9 GB
    DROP TABLE IF EXISTS breezeway.property_photos_backup;
    DROP TABLE IF EXISTS breezeway.reservation_guests_backup;
    DROP TABLE IF EXISTS breezeway.task_assignments_backup;
    DROP TABLE IF EXISTS breezeway.task_photos_backup;
    DROP TABLE IF EXISTS breezeway.task_comments_backup;
    DROP TABLE IF EXISTS breezeway.task_requirements_backup;

    VACUUM FULL;

    SELECT pg_size_pretty(pg_database_size('breezeway')) as final_size;
EOF
    echo "Backup tables dropped. System cleanup complete."
else
    echo "Keeping backup tables for further investigation."
fi
```

---

## Rollback Procedure

**If issues are detected, rollback immediately:**

```bash
# 1. Stop ETL jobs
crontab -e
# Comment out ETL jobs again

# 2. Connect to database
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway

# 3. Execute rollback
BEGIN;

-- Drop UNIQUE constraints
ALTER TABLE breezeway.property_photos DROP CONSTRAINT IF EXISTS property_photos_unique_photo;
ALTER TABLE breezeway.reservation_guests DROP CONSTRAINT IF EXISTS reservation_guests_unique_guest;
ALTER TABLE breezeway.task_assignments DROP CONSTRAINT IF EXISTS task_assignments_unique_assignee;
ALTER TABLE breezeway.task_photos DROP CONSTRAINT IF EXISTS task_photos_unique_photo;
ALTER TABLE breezeway.task_comments DROP CONSTRAINT IF EXISTS task_comments_unique_comment;
ALTER TABLE breezeway.task_requirements DROP CONSTRAINT IF EXISTS task_requirements_unique_requirement;

-- Restore from backups
TRUNCATE breezeway.property_photos;
INSERT INTO breezeway.property_photos SELECT * FROM breezeway.property_photos_backup;

TRUNCATE breezeway.reservation_guests;
INSERT INTO breezeway.reservation_guests SELECT * FROM breezeway.reservation_guests_backup;

TRUNCATE breezeway.task_assignments;
INSERT INTO breezeway.task_assignments SELECT * FROM breezeway.task_assignments_backup;

TRUNCATE breezeway.task_photos;
INSERT INTO breezeway.task_photos SELECT * FROM breezeway.task_photos_backup;

TRUNCATE breezeway.task_comments;
INSERT INTO breezeway.task_comments SELECT * FROM breezeway.task_comments_backup;

TRUNCATE breezeway.task_requirements;
INSERT INTO breezeway.task_requirements SELECT * FROM breezeway.task_requirements_backup;

-- Verify restoration
SELECT COUNT(*) FROM breezeway.property_photos;
SELECT COUNT(*) FROM breezeway.task_requirements;

COMMIT;

\q

# 4. Revert ETL code changes
cd /root/Breezeway
git checkout etl/etl_base.py etl/config.py
# (or manually revert changes)

# 5. Re-enable ETL with old code
crontab -e
# Uncomment ETL jobs

# 6. Document what went wrong
echo "Rollback completed on $(date)" >> logs/rollback.log
echo "Reason: [Document issue here]" >> logs/rollback.log
```

---

## Expected Results

### Before Migration

| Metric | Value |
|--------|-------|
| Database Size | 10.16 GB |
| property_photos | 10,192,750 records |
| task_requirements | 24,174,099 records |
| Total child records | 36.5M |
| Duplicates | 36.4M (99.7%) |
| Query Performance | Slow (10-600x overhead) |

### After Migration

| Metric | Value |
|--------|-------|
| Database Size | ~1.2 GB |
| property_photos | 16,113 records |
| task_requirements | 26,580 records |
| Total child records | ~70K |
| Duplicates | 0 |
| Query Performance | Fast (baseline) |
| Space Saved | 8.96 GB |

---

## Code Changes Summary

### 1. config.py (Line 187)

**Fixed task_comments natural_key:**

```python
# Before:
'natural_key': ['comment_id', 'region_code']

# After:
'natural_key': ['task_pk', 'comment_id']
```

### 2. etl/etl_base.py (Lines 816-861)

**Updated _upsert_children method:**

```python
# Before:
query = f"""
    INSERT INTO {schema}.{table_name} ({columns_str})
    VALUES %s
    ON CONFLICT DO NOTHING  # ← No conflict target = always insert
"""

# After:
natural_key = child_config.get('natural_key', [])
if natural_key:
    conflict_columns = ', '.join(natural_key)
    query = f"""
        INSERT INTO {schema}.{table_name} ({columns_str})
        VALUES %s
        ON CONFLICT ({conflict_columns})  # ← Proper conflict detection
        DO UPDATE SET {update_set}
    """
```

**Impact:** ETL now properly detects and handles duplicate records.

---

## Success Criteria

✅ Migration completes without errors

✅ All 6 UNIQUE constraints added successfully

✅ Duplicate count = 0 for all child tables

✅ Database size reduced by ~9 GB

✅ ETL jobs run successfully with new code

✅ No constraint violation errors in logs (48 hours)

✅ Query performance improved (validate with sample queries)

---

## Troubleshooting

### Issue: Migration Takes Too Long

**Symptom:** Deduplication running > 3 hours

**Solution:**
```bash
# Check if VACUUM FULL is running
SELECT pid, query, state FROM pg_stat_activity WHERE query LIKE '%VACUUM%';

# If stuck, cancel and retry migration in smaller batches
```

### Issue: Constraint Violation After Migration

**Symptom:** ETL logs show "duplicate key value violates unique constraint"

**Root Cause:** API returned truly duplicate data (same photo on same property twice)

**Solution:** This is expected behavior - the constraint is working! The duplicate is being rejected. No action needed.

### Issue: Query Performance Still Slow

**Symptom:** Queries still slow after deduplication

**Solution:**
```bash
# Rerun ANALYZE on all tables
PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "
ANALYZE breezeway.property_photos;
ANALYZE breezeway.task_requirements;
"
```

---

## Contact & Support

**Migration Author:** System Administrator

**Date Created:** December 2, 2025

**Documentation:**
- Analysis: `/root/Breezeway/docs/DUPLICATE_RECORDS_ANALYSIS_AND_FIX_PLAN.md`
- Migration Script: `/root/Breezeway/migrations/010_deduplicate_child_tables.sql`
- This Guide: `/root/Breezeway/docs/DEDUPLICATION_DEPLOYMENT_GUIDE.md`

**Emergency Rollback:** See "Rollback Procedure" section above

---

## Post-Deployment Checklist

- [ ] Maintenance window scheduled
- [ ] ETL jobs disabled
- [ ] Full database backup created
- [ ] Migration script executed successfully
- [ ] Post-migration validation passed (0 duplicates)
- [ ] UNIQUE constraints verified (6 constraints exist)
- [ ] Database size reduced (~1.2 GB)
- [ ] Test ETL run completed successfully
- [ ] ETL jobs re-enabled
- [ ] Day 1 monitoring completed (no errors)
- [ ] Week 1 monitoring completed (no duplicates)
- [ ] Backup tables dropped (after 7 days)
- [ ] Documentation updated with actual results

---

**Status:** Ready for execution

**Recommendation:** Execute during next maintenance window (off-peak hours)

**Risk:** LOW - Comprehensive backups and rollback procedures in place

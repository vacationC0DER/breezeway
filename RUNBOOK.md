# Breezeway ETL Runbook

**Operational procedures and troubleshooting guide for the Breezeway ETL Pipeline**

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Alert Response](#alert-response)
3. [Common Issues](#common-issues)
4. [Manual Interventions](#manual-interventions)
5. [Monitoring](#monitoring)
6. [Escalation](#escalation)

---

## Daily Operations

### Morning Check (5 minutes)

**Every morning, review overnight ETL runs:**

```bash
# 1. Check for alert emails
# Look for subject lines starting with 🚨, ⚠️, or 📊

# 2. Review alert log
tail -50 /root/Breezeway/logs/alerts.log

# 3. Check recent sync status
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT region_code, entity_type, sync_status,
       last_successful_sync_at,
       EXTRACT(HOUR FROM (NOW() - last_successful_sync_at)) as hours_ago
FROM breezeway.etl_sync_log
WHERE last_successful_sync_at > NOW() - INTERVAL '24 hours'
  AND sync_status IN ('failed', 'running')
ORDER BY sync_started_at DESC;
"

# 4. Quick validation - check record counts
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT 'properties' as entity, COUNT(*) as count FROM breezeway.properties
UNION ALL
SELECT 'reservations', COUNT(*) FROM breezeway.reservations
UNION ALL
SELECT 'tasks', COUNT(*) FROM breezeway.tasks;
"
```

**Expected Results:**
- ✅ No failed syncs in last 24 hours
- ✅ All regions synced within last 2 hours (hourly entities)
- ✅ All regions synced within last 25 hours (daily entities)
- ✅ Record counts stable or growing

### Weekly Check (15 minutes)

```bash
# 1. Review sync performance trends
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT region_code, entity_type,
       AVG(api_calls_made) as avg_api_calls,
       AVG(records_processed) as avg_records,
       COUNT(*) as sync_count
FROM breezeway.etl_sync_log
WHERE sync_started_at > NOW() - INTERVAL '7 days'
  AND sync_status = 'success'
GROUP BY region_code, entity_type
ORDER BY region_code, entity_type;
"

# 2. Check log file sizes
du -h /root/Breezeway/logs/

# 3. Check token status
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT region_code,
       last_refreshed_at,
       token_generation_count,
       EXTRACT(HOUR FROM (token_expires_at - NOW())) as hours_until_expiry
FROM breezeway.api_tokens
ORDER BY region_code;
"
```

---

## Alert Response

### 🚨 FAILURE ALERT

**Email Subject:** `🚨 ETL FAILURE: {region}/{entity}`

**Immediate Actions (within 15 minutes):**

1. **Check the error message** (from email or log):
```bash
tail -200 /root/Breezeway/logs/hourly_etl_$(date +%Y%m%d).log | grep -A 10 "FAILED"
```

2. **Identify error type:**

#### A. Database Connection Error

**Symptoms:**
- `connection to server ... failed`
- `could not connect to server`
- `FATAL: remaining connection slots`

**Resolution:**
```bash
# 1. Check database connectivity
psql -h 159.89.235.26 -U breezeway -d breezeway -c "SELECT 1;"

# 2. Check active connections
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT COUNT(*), state
FROM pg_stat_activity
WHERE datname = 'breezeway'
GROUP BY state;
"

# 3. If connection pool exhausted, wait 5 minutes and retry
sleep 300
python3 /root/Breezeway/etl/run_etl.py {region} {entity}

# 4. If still failing, check firewall/network
ping 159.89.235.26
```

#### B. API Connection Error

**Symptoms:**
- `Connection timeout`
- `HTTPSConnectionPool`
- `Read timed out`
- `429 Too Many Requests`

**Resolution:**
```bash
# 1. Check API connectivity
curl -I https://api.breezeway.io

# 2. Check token validity
python3 /root/Breezeway/shared/auth_manager.py {region}

# 3. If rate limited (429), wait 1 hour
# The system auto-retries with backoff, so this should be rare

# 4. Retry manually after wait period
python3 /root/Breezeway/etl/run_etl.py {region} {entity}
```

#### C. Token Error

**Symptoms:**
- `Token generation failed`
- `401 Unauthorized`
- `Invalid client credentials`

**Resolution:**
```bash
# 1. Check token in database
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT region_code, token_expires_at, last_error
FROM breezeway.api_tokens
WHERE region_code = '{region}';
"

# 2. Force token refresh
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
UPDATE breezeway.api_tokens
SET access_token = NULL,
    refresh_token = NULL,
    token_expires_at = NOW() - INTERVAL '1 hour'
WHERE region_code = '{region}';
"

# 3. Retry (will generate new token)
python3 /root/Breezeway/etl/run_etl.py {region} {entity}

# 4. If still failing, check credentials in config.py
nano /root/Breezeway/etl/config.py
# Verify client_id and client_secret match Breezeway account
```

#### D. Data Error

**Symptoms:**
- `foreign key constraint`
- `unique constraint`
- `null value in column`
- `invalid input syntax`

**Resolution:**
```bash
# 1. Check the specific error in logs
tail -50 /root/Breezeway/logs/hourly_etl_$(date +%Y%m%d).log

# 2. For FK violations, check parent record exists:
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT COUNT(*)
FROM breezeway.properties
WHERE region_code = '{region}';
"

# 3. For reservations FK error, run properties first:
python3 /root/Breezeway/etl/run_etl.py {region} properties
python3 /root/Breezeway/etl/run_etl.py {region} reservations

# 4. For tasks FK error, run properties AND reservations first:
python3 /root/Breezeway/etl/run_etl.py {region} properties
python3 /root/Breezeway/etl/run_etl.py {region} reservations
python3 /root/Breezeway/etl/run_etl.py {region} tasks
```

### ⚠️ WARNING ALERT

**Email Subject:** `⚠️ ETL WARNING: {region}/{entity}`

**Actions (within 1 hour):**

1. **Review warning message** - Usually performance-related

2. **Check ETL duration:**
```bash
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT region_code, entity_type,
       sync_started_at,
       sync_completed_at,
       EXTRACT(EPOCH FROM (sync_completed_at - sync_started_at)) as duration_seconds,
       records_processed
FROM breezeway.etl_sync_log
WHERE region_code = '{region}'
  AND entity_type = '{entity}'
ORDER BY sync_started_at DESC
LIMIT 10;
"
```

3. **Common causes:**
   - Large data volume (normal, no action needed)
   - Slow API response (transient, monitor)
   - Slow database (check other queries running)

4. **If duration consistently > 10 minutes:**
   - Check for database locks
   - Review API response times
   - Consider optimization (contact dev team)

### 📊 BATCH SUMMARY

**Email Subject:** `📊 {Job Type} Summary: {N} failures`

**Actions:**
- Review individual failure details (see FAILURE ALERT section above)
- If multiple regions failing, likely system-wide issue (network/database)
- If single region failing consistently, likely region-specific (credentials/data)

---

## Common Issues

### Issue: ETL Stuck in "running" Status

**Symptoms:**
```sql
SELECT * FROM breezeway.etl_sync_log
WHERE sync_status = 'running'
  AND sync_started_at < NOW() - INTERVAL '1 hour';
```

**Resolution:**
```bash
# 1. Check if process actually running
ps aux | grep run_etl.py

# 2. If no process found, mark as failed manually:
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
UPDATE breezeway.etl_sync_log
SET sync_status = 'failed',
    sync_completed_at = NOW(),
    error_message = 'Process terminated unexpectedly - marked failed by operator'
WHERE sync_status = 'running'
  AND sync_started_at < NOW() - INTERVAL '1 hour';
"

# 3. Retry the ETL
python3 /root/Breezeway/etl/run_etl.py {region} {entity}
```

### Issue: Missing Data for Recent Date

**Symptoms:** User reports data missing for specific date

**Resolution:**
```bash
# 1. Check when last successful sync occurred
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT region_code, entity_type,
       last_successful_sync_at,
       records_processed
FROM breezeway.etl_sync_log
WHERE region_code = '{region}'
  AND entity_type = '{entity}'
ORDER BY last_successful_sync_at DESC
LIMIT 1;
"

# 2. Check if records exist in database
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
SELECT COUNT(*)
FROM breezeway.{entity}
WHERE region_code = '{region}'
  AND synced_at > NOW() - INTERVAL '48 hours';
"

# 3. If sync was successful but data missing, it may not exist in API
# Verify by manually checking API (requires dev assistance)

# 4. If sync failed, retry:
python3 /root/Breezeway/etl/run_etl.py {region} {entity}
```

### Issue: Cron Job Not Running

**Symptoms:** No logs generated at expected time

**Resolution:**
```bash
# 1. Check cron status
systemctl status cron

# 2. Check cron logs
grep CRON /var/log/syslog | tail -20

# 3. Verify crontab entries exist
crontab -l | grep Breezeway

# 4. If missing, re-add:
crontab -e
# Add these lines:
# 0 * * * * /root/Breezeway/scripts/run_hourly_etl.sh >> /root/Breezeway/logs/cron_hourly.log 2>&1
# 0 0 * * * /root/Breezeway/scripts/run_daily_etl.sh >> /root/Breezeway/logs/cron_daily.log 2>&1

# 5. Test manually
bash /root/Breezeway/scripts/run_hourly_etl.sh
```

---

## Manual Interventions

### Force Full Refresh (All Regions, One Entity)

**Use case:** Data quality issue requires full re-sync

```bash
cd /root/Breezeway

# Run sequentially
for region in nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country; do
    echo "=== Processing $region ==="
    python3 etl/run_etl.py $region {entity}
done
```

### Resync Specific Date Range

**Note:** Current implementation doesn't support date range filtering.
**Workaround:** Full refresh (above)

### Clear Sync Status (Emergency Reset)

**Use case:** Sync log corrupted or needs reset

```bash
# ⚠️ USE WITH CAUTION - Only clear completed/failed, never "running"
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
DELETE FROM breezeway.etl_sync_log
WHERE sync_status IN ('success', 'failed')
  AND sync_started_at < NOW() - INTERVAL '7 days';
"
```

### Manual Token Refresh (All Regions)

```bash
cd /root/Breezeway

for region in nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country; do
    echo "=== Refreshing token: $region ==="
    python3 shared/auth_manager.py $region
done
```

---

## Monitoring

### Key Metrics to Track

1. **Success Rate:** > 99%
2. **ETL Duration:** < 10 minutes per job
3. **Records Processed:** Stable or growing
4. **API Calls:** < 20 per job
5. **Sync Lag:** < 2 hours for hourly, < 25 hours for daily

### Health Check Query

```sql
-- Overall health check
SELECT
    entity_type,
    COUNT(DISTINCT region_code) as regions_synced,
    MAX(last_successful_sync_at) as most_recent_sync,
    EXTRACT(HOUR FROM (NOW() - MAX(last_successful_sync_at))) as hours_since_last,
    SUM(CASE WHEN sync_status = 'failed' AND sync_started_at > NOW() - INTERVAL '24 hours' THEN 1 ELSE 0 END) as failures_24h
FROM breezeway.etl_sync_log
GROUP BY entity_type
ORDER BY entity_type;
```

**Expected:**
- regions_synced = 8 (all regions)
- hours_since_last < 2 (for hourly) or < 25 (for daily)
- failures_24h = 0

---

## Escalation

### When to Escalate

**Escalate to Development Team if:**

1. ❌ Multiple regions failing simultaneously (> 3)
2. ❌ Same entity failing across all regions
3. ❌ Failures persist after standard troubleshooting (> 2 hours)
4. ❌ Data corruption suspected
5. ❌ API credentials invalid (require re-issuing from Breezeway)

### Escalation Information to Provide

```bash
# 1. Collect error logs (last 500 lines)
tail -500 /root/Breezeway/logs/hourly_etl_$(date +%Y%m%d).log > /tmp/etl_error_$(date +%Y%m%d_%H%M).txt
tail -500 /root/Breezeway/logs/daily_etl_$(date +%Y%m%d).log >> /tmp/etl_error_$(date +%Y%m%d_%H%M).txt

# 2. Collect sync status
psql -h 159.89.235.26 -U breezeway -d breezeway -c "
COPY (
    SELECT *
    FROM breezeway.etl_sync_log
    WHERE sync_started_at > NOW() - INTERVAL '24 hours'
    ORDER BY sync_started_at DESC
) TO STDOUT WITH CSV HEADER" > /tmp/sync_status_$(date +%Y%m%d_%H%M).csv

# 3. Collect alert log
cp /root/Breezeway/logs/alerts.log /tmp/alerts_$(date +%Y%m%d_%H%M).log

# 4. Send to dev team with:
#    - Error description
#    - Steps already attempted
#    - All log files from above
```

### Emergency Contact

- **Primary:** ops@example.com
- **Secondary:** dev-team@example.com
- **After Hours:** [On-call phone number]

---

## Appendix

### Useful Commands

```bash
# Quick status check
python3 -c "from shared.sync_tracker import SyncTracker; t=SyncTracker('nashville','properties'); print(t.get_last_sync_time())"

# Test database connection
python3 -c "from shared.database import DatabaseManager; print('Connected:', DatabaseManager.get_connection().info.dbname)"

# Test API token
python3 -c "from shared.auth_manager import TokenManager; print('Token:', TokenManager('nashville').get_valid_token()[:50])"

# View all running ETL processes
ps aux | grep -E "run_etl|run_hourly|run_daily"

# Kill stuck ETL process (emergency only)
pkill -f run_etl.py
```

### Quick Reference: Entity Dependencies

```
properties (no dependencies)
  ↓
reservations (requires properties)
  ↓
tasks (requires properties, optionally reservations)

people (no dependencies)
supplies (no dependencies)
tags (no dependencies)
```

**Important:** Always run properties before reservations/tasks for a region.

---

**Last Updated:** December 2025
**Document Version:** 2.0
**Maintained By:** Operations Team

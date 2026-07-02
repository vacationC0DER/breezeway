#!/bin/bash
# ============================================================================
# Daily ETL Runner - Tasks
# ============================================================================
# Runs tasks ETL for all 8 regions daily at 4 AM EST
# Logs to: /root/Breezeway/logs/daily_etl_YYYYMMDD.log

# Don't use set -e: we want to continue on failures and track them
# set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/daily_etl_$(date +%Y%m%d).log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log rotation: keep last 30 days
find "$LOG_DIR" -name "daily_etl_*.log" -mtime +30 -delete

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=========================================================================="
log "DAILY ETL START - TASKS, PEOPLE, SUPPLIES, TAGS"
log "=========================================================================="

# All 8 regions
# Active regions (DB-driven from breezeway.tenant_regions as of 2026-05-15).
# Falls back to hardcoded list if psql fails so the cron is never silenced.
REGIONS_FALLBACK="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"
REGIONS=$(sudo -u postgres psql -d breezeway -tAc "SELECT string_agg(region_code, ' ' ORDER BY region_code) FROM breezeway.tenant_regions WHERE active = true" 2>/dev/null)
if [ -z "$REGIONS" ]; then
    log "WARNING: tenant_regions lookup empty/failed, using fallback list"
    REGIONS="$REGIONS_FALLBACK"
fi

# All daily entities
# Child API calls (requirements/comments) windowed to recently-updated tasks
# (ETL plan Task 2b.2). Override with BZ_TASK_WINDOW_DAYS=0 for a full sweep
# (monthly cron does this). Default 35 days.
export BZ_TASK_WINDOW_DAYS="${BZ_TASK_WINDOW_DAYS-35}"

ENTITIES="properties tasks people supplies tags subdepartments templates property_tags reservation_tags"  # properties moved from hourly 2026-07-02 (2b.4): property-status webhook covers realtime; new-property discovery is daily

# Track failures
TOTAL_JOBS=0
FAILED_JOBS=0

# Run all entities for all regions
for entity in $ENTITIES; do
    log "Starting $entity ETL for all regions..."
    for region in $REGIONS; do
        log "  → Running: $region / $entity"
        START_TIME=$(date +%s)
        TOTAL_JOBS=$((TOTAL_JOBS + 1))

        cd "$PROJECT_DIR"
        python3 etl/run_etl.py "$region" "$entity" >> "$LOG_FILE" 2>&1
        EXIT_CODE=$?  # Capture exit code immediately

        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        if [ $EXIT_CODE -eq 0 ]; then
            log "  ✓ SUCCESS: $region / $entity (${DURATION}s)"
        else
            log "  ✗ FAILED: $region / $entity (${DURATION}s)"
            FAILED_JOBS=$((FAILED_JOBS + 1))
        fi
    done
    log ""
done

# ----------------------------------------------------------------------------
# Reservation-linked tasks (GET /reservation/{id}/tasks), 2026-onward.
# Runs last so reservations (hourly) + tasks (above) are current and the
# reservation_pk / task_pk soft FKs resolve. Handles all regions internally.
# ----------------------------------------------------------------------------
log "Starting reservation_tasks ETL (2026-onward) for all regions..."
START_TIME=$(date +%s)
TOTAL_JOBS=$((TOTAL_JOBS + 1))
cd "$PROJECT_DIR"
python3 etl/reservation_tasks_etl.py all --since 2026-01-01 >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
if [ $EXIT_CODE -eq 0 ]; then
    log "  ✓ SUCCESS: reservation_tasks / all regions (${DURATION}s)"
else
    log "  ✗ FAILED: reservation_tasks / all regions (${DURATION}s)"
    FAILED_JOBS=$((FAILED_JOBS + 1))
fi
log ""

log ""
log "Pushing reservation_tasks -> Supabase (incremental) for all regions..."
START_TIME=$(date +%s)
TOTAL_JOBS=$((TOTAL_JOBS + 1))
cd "$PROJECT_DIR"
python3 etl/reservation_tasks_supabase_push.py all >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
if [ $EXIT_CODE -eq 0 ]; then
    log "  OK SUCCESS: reservation_tasks Supabase push / all regions (${DURATION}s)"
else
    log "  XX FAILED: reservation_tasks Supabase push / all regions (${DURATION}s)"
    FAILED_JOBS=$((FAILED_JOBS + 1))
fi
log ""

log "Pushing bz_property_dim -> Supabase (incremental) for all regions..."
START_TIME=$(date +%s)
TOTAL_JOBS=$((TOTAL_JOBS + 1))
cd "$PROJECT_DIR"
python3 etl/bz_property_dim_supabase_push.py all >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
if [ $EXIT_CODE -eq 0 ]; then
    log "  OK SUCCESS: bz_property_dim Supabase push / all regions (${DURATION}s)"
else
    log "  XX FAILED: bz_property_dim Supabase push / all regions (${DURATION}s)"
    FAILED_JOBS=$((FAILED_JOBS + 1))
fi
log ""

log "=========================================================================="
log "DAILY ETL COMPLETE"
log "Total: $TOTAL_JOBS jobs, Failed: $FAILED_JOBS"
log "=========================================================================="

# Exit with failure if any jobs failed
if [ $FAILED_JOBS -gt 0 ]; then
    exit 1
fi

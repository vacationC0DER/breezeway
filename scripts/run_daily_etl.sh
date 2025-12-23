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
REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"

# All daily entities
ENTITIES="tasks people supplies tags"

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

log "=========================================================================="
log "DAILY ETL COMPLETE"
log "Total: $TOTAL_JOBS jobs, Failed: $FAILED_JOBS"
log "=========================================================================="

# Exit with failure if any jobs failed
if [ $FAILED_JOBS -gt 0 ]; then
    exit 1
fi

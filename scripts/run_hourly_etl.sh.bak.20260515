#!/bin/bash
# ============================================================================
# Hourly ETL Runner - Properties & Reservations
# ============================================================================
# Runs properties and reservations ETL for all 8 regions every hour
# Logs to: /root/Breezeway/logs/hourly_etl_YYYYMMDD.log

# Don't use set -e: we want to continue on failures and track them
# set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/hourly_etl_$(date +%Y%m%d).log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log rotation: keep last 30 days
find "$LOG_DIR" -name "hourly_etl_*.log" -mtime +30 -delete

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=========================================================================="
log "HOURLY ETL START"
log "=========================================================================="

# All 8 regions
REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"

# Track failures
TOTAL_JOBS=0
FAILED_JOBS=0

# Run properties for all regions
log "Starting PROPERTIES ETL for all regions..."
for region in $REGIONS; do
    log "  → Running: $region / properties"
    TOTAL_JOBS=$((TOTAL_JOBS + 1))
    cd "$PROJECT_DIR"
    python3 etl/run_etl.py "$region" properties >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?  # Capture exit code immediately
    if [ $EXIT_CODE -eq 0 ]; then
        log "  ✓ SUCCESS: $region / properties"
    else
        log "  ✗ FAILED: $region / properties"
        FAILED_JOBS=$((FAILED_JOBS + 1))
    fi
done

# Run reservations for all regions
log "Starting RESERVATIONS ETL for all regions..."
for region in $REGIONS; do
    log "  → Running: $region / reservations"
    TOTAL_JOBS=$((TOTAL_JOBS + 1))
    cd "$PROJECT_DIR"
    python3 etl/run_etl.py "$region" reservations >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?  # Capture exit code immediately
    if [ $EXIT_CODE -eq 0 ]; then
        log "  ✓ SUCCESS: $region / reservations"
    else
        log "  ✗ FAILED: $region / reservations"
        FAILED_JOBS=$((FAILED_JOBS + 1))
    fi
done

log "=========================================================================="
log "HOURLY ETL COMPLETE"
log "Total: $TOTAL_JOBS jobs, Failed: $FAILED_JOBS"
log "=========================================================================="

# Exit with failure if any jobs failed
if [ $FAILED_JOBS -gt 0 ]; then
    exit 1
fi

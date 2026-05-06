#!/bin/sh
# ============================================================
#  pg-baseera RDS CloudWatch Logs and pgBadger sync
#  Downloads PostgreSQL logs from CloudWatch Logs to local/S3(TODO)
#  postgres/logs/ directory for pgBadger analysis.
#
#  Usage:
#    ./rds/log_sync.sh                  # sync today's logs
#    ./rds/log_sync.sh 2026-04-19       # sync specific date
#    ./rds/log_sync.sh --watch          # sync every $RDS_LOG_SYNC_INTERVAL seconds
# ============================================================
set -e

# If a .env file exists in the same directory as the script, load and export it 

ENV_FILE="$(dirname "$0")/../.env" 
if [ -f "$ENV_FILE" ]; then 
    set -a 
    . "$ENV_FILE"  #The dot '.' is the same as 'source' 
    set +a 
fi

# Config from .env
AWS_REGION="${AWS_REGION:-eu-central-1}"
LOG_DIR="${LOG_DIR:-$(dirname "$0")/../postgres/logs}"
INTERVAL="${RDS_LOG_SYNC_INTERVAL:-3600}"
PRIMARY_LOG_GROUP="${RDS_STAGING_PRIMARY_LOG_GROUP:-/aws/rds/instance/staging-rds-pg/postgresql}"
REPLICA_LOG_GROUP="${RDS_STAGING_REPLICA_LOG_GROUP:-/aws/rds/instance/staging-rds-pg-replica/postgresql}"

echo "Primary log group: ${PRIMARY_LOG_GROUP}"
# Validate AWS CLI
if ! command -v aws > /dev/null 2>&1; then
    echo "ERROR: AWS CLI not found.Install awscli."
    exit 1
fi


mkdir -p "$LOG_DIR"


# Download logs from one log group
sync_log_group() {
    LOG_GROUP="$1"
    LABEL="$2"
    DATE="$3"
    OUT_FILE="${LOG_DIR}/postgresql-${LABEL}-${DATE}.log"


    echo "[$(date '+%H:%M:%S')] Syncing $LOG_GROUP -> $OUT_FILE"


    # Get log streams for this log group (most recent 5)
    STREAMS=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending \
        --region "$AWS_REGION" \
        --query 'logStreams[*].logStreamName' \
        --output text 2>/dev/null | tr '\t' '\n' | head -5)


    if [ -z "$STREAMS" ]; then
        echo "[$(date '+%H:%M:%S')] WARNING: No log streams found in $LOG_GROUP"
        return
    fi


    # Clear output file
    > "$OUT_FILE"


    # Download each stream
    echo "$STREAMS" | while IFS= read -r STREAM; do
        [ -z "$STREAM" ] && continue
        echo "[$(date '+%H:%M:%S')]   Stream: $STREAM"
        aws logs get-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$STREAM" \
            --region "$AWS_REGION" \
            --no-paginate \
            --output json 2>/dev/null | \
            python3 -c "
import sys, json
data = json.load(sys.stdin)
for e in data.get('events', []):
    msg = e.get('message', '').rstrip()
    if msg:
        print(msg)
" >> "$OUT_FILE"
    done


    LINE_COUNT=$(wc -l < "$OUT_FILE" | tr -d ' ')
    echo "[$(date '+%H:%M:%S')] Done — ${LINE_COUNT} lines -> $OUT_FILE"
}


# Main sync
run_sync() {
    TARGET_DATE="$1"
    echo "======================================================"
    echo " pg-baseera RDS Log Sync"
    echo " Date     : $TARGET_DATE"
    echo " Log dir  : $LOG_DIR"
    echo " Region   : $AWS_REGION"
    echo "======================================================"


    sync_log_group "$PRIMARY_LOG_GROUP" "staging-primary" "$TARGET_DATE"
    sync_log_group "$REPLICA_LOG_GROUP" "staging-replica" "$TARGET_DATE"


    echo ""
    echo "Sync complete. To generate pgBadger report run:"
    echo "  pgbadger --format rds \\"
    echo "    --outfile /reports/rds-report-${TARGET_DATE}.html \\"
    echo "    ${LOG_DIR}/postgresql-staging-primary-${TARGET_DATE}.log"
}


# Watch mode vs single run
if [ "$1" = "--watch" ]; then
    echo "Watch mode: syncing every ${INTERVAL}s"
    while true; do
        run_sync "$(date +%Y-%m-%d)"
        echo "Next sync in ${INTERVAL}s..."
        sleep "$INTERVAL"
    done
else
    TARGET_DATE="${1:-$(date +%Y-%m-%d)}"
    run_sync "$TARGET_DATE"
fi

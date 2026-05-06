#!/bin/bash
set -e


# Load env
if [ ! -f .env ]; then
    echo "ERROR: .env not found. Run: cp .env.example .env"
    echo "       Then fill in your credentials."
    exit 1
fi
source .env


# Detect mode
if [ -n "$EXTERNAL_DB_DSN" ]; then
    MODE="B"
    echo "Mode B: Monitoring external PostgreSQL"
    echo "  DSN: ${EXTERNAL_DB_DSN%%@*}@***"
else
    MODE="A"
    echo " Mode A: Full stack with internal PostgreSQL"
fi


# Detect RDS extension
RDS_ENABLED=false
if [ -n "$RDS_STAGING_PRIMARY_HOST" ] && \
   [ "$RDS_STAGING_PRIMARY_HOST" != "staging-rds-pg.xxxxxxxx.eu-central-1.rds.amazonaws.com" ]; then
    RDS_ENABLED=true
    echo "RDS Extension ENABLED"
    echo "  Staging primary : $RDS_STAGING_PRIMARY_HOST"
    echo "  Staging replica : $RDS_STAGING_REPLICA_HOST"
    echo "  AWS region      : ${AWS_REGION:-eu-central-1}"
else
    echo "RDS Extension DISABLED (set RDS_STAGING_PRIMARY_HOST in .env to enable)"
fi


# pgBench
PROFILES=""
if [ "$PGBENCH_ENABLED" = "true" ]; then
    if [ "$MODE" = "B" ] || [ "$RDS_ENABLED" = "true" ]; then
        echo "pgBench disabled. Only works with internal PostgreSQL (Mode A)"
    else
        echo "pgBench load testing: ENABLED"
        echo "  Clients: $PGBENCH_CLIENTS | Burst: ${PGBENCH_BURST_DURATION}s | Idle: ${PGBENCH_IDLE_DURATION}s"
        PROFILES="--profile pgbench"
    fi
else
    echo "pgBench load testing: DISABLED"
fi


# Validate AWS credentials if RDS enabled
if [ "$RDS_ENABLED" = "true" ]; then
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ "$AWS_ACCESS_KEY_ID" = "your-access-key-id" ]; then
        echo "ERROR: AWS_ACCESS_KEY_ID not set in .env"
        echo "       Required for RDS CloudWatch metrics and log sync."
        exit 1
    fi
    if [ -z "$RDS_EXPORTER_PASSWORD" ] || [ "$RDS_EXPORTER_PASSWORD" = "changeme" ]; then
        echo "WARNING: RDS_EXPORTER_PASSWORD is still set to 'changeme'."
        echo "         Update it to the real pgexporter password before connecting to RDS."
    fi
fi


# Fix log dir permissions
mkdir -p postgres/logs pgbadger/reports
sudo chmod 777 postgres/logs pgbadger/reports 2>/dev/null || \
    chmod 777 postgres/logs pgbadger/reports 2>/dev/null || true


# Bring up stack
echo ""
echo "Starting pg-baseera..."
docker compose $PROFILES up -d --build


echo ""
echo "════════════════════════════════════════════════"
echo "  pg-baseera is running!"
echo "════════════════════════════════════════════════"
echo "  Grafana       : http://localhost:${GRAFANA_PORT:-3000}"
echo "  Login         : ${GF_ADMIN_USER:-admin} / ${GF_ADMIN_PASSWORD}"
echo "  Prometheus    : http://localhost:${PROMETHEUS_PORT:-9090}"
echo "  Alertmanager  : http://localhost:${ALERTMANAGER_PORT:-9093}"
echo "  pgBadger      : http://localhost:${PGBADGER_PORT:-8080}"
echo "  pg-monitor    : http://localhost:9999  (run: ./pg-monitor-bin)"
if [ "$RDS_ENABLED" = "true" ]; then
echo "────────────────────────────────────────────────"
echo "  RDS Exporter  (primary) : http://localhost:9188/metrics"
echo "  RDS Exporter  (replica) : http://localhost:9189/metrics"
echo "  RDS Log Sync  : logs synced to postgres/logs/ every ${RDS_LOG_SYNC_INTERVAL:-3600}s"
fi
echo "════════════════════════════════════════════════"

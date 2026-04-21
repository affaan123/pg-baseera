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
    PROFILES=""
else
    MODE="A"
    echo " Mode A: Full stack with internal PostgreSQL"
    PROFILES=""
fi

# pgBench
if [ "$PGBENCH_ENABLED" = "true" ]; then
    if [ "$MODE" = "B" ]; then
        echo "   pgBench is enabled but EXTERNAL_DB_DSN is set."
        echo "   pgBench only works with internal PostgreSQL (Mode A)."
        echo "   Disabling pgBench for this run."
    else
        echo " pgBench load testing: ENABLED"
        echo "  Clients: $PGBENCH_CLIENTS | Burst: ${PGBENCH_BURST_DURATION}s | Idle: ${PGBENCH_IDLE_DURATION}s"
        PROFILES="--profile pgbench"
    fi
else
    echo " pgBench load testing: DISABLED (set PGBENCH_ENABLED=true to enable)"
fi

# Fix log dir permissions
mkdir -p postgres/logs pgbadger/reports
echo "Log dirs ready."

# Bring up stack
echo ""
echo "Starting pg-baseera..."
docker compose $PROFILES up -d --build

echo ""
echo "════════════════════════════════════════"
echo "  pg-baseera is running!"
echo "════════════════════════════════════════"
echo "  Grafana     : http://localhost:${GRAFANA_PORT:-3000}"
echo "              Login: ${GF_ADMIN_USER:-admin} / ${GF_ADMIN_PASSWORD}"
echo "  Prometheus  : http://localhost:${PROMETHEUS_PORT:-9090}"
echo "  pgBadger    : http://localhost:${PGBADGER_PORT:-8080}"
echo "  pg-monitor  : http://localhost:9999  (run: ./pg-monitor-bin)"
echo "════════════════════════════════════════"

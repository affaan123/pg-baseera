#!/bin/bash
set -e

HOST="postgres"
PORT="5432"
USER="${POSTGRES_USER:-pgadmin}"
DB="${POSTGRES_DB:-appdb}"
export PGPASSWORD="${POSTGRES_PASSWORD:-changeme}"

CLIENTS="${PGBENCH_CLIENTS:-20}"
THREADS="${PGBENCH_THREADS:-4}"
BURST_DURATION="${PGBENCH_BURST_DURATION:-60}"
IDLE_DURATION="${PGBENCH_IDLE_DURATION:-240}"

echo "[pgbench] Waiting for PostgreSQL to be ready..."
until pg_isready -h "$HOST" -p "$PORT" -U "$USER"; do
    sleep 2
done

echo "[pgbench] Starting burst load: ${CLIENTS} clients, ${BURST_DURATION}s bursts, ${IDLE_DURATION}s idle"

CYCLE=1
while true; do
    echo "[pgbench] Cycle $CYCLE: starting ${BURST_DURATION}s burst (${CLIENTS} clients)"

    pgbench -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
        --client="$CLIENTS" \
        --jobs="$THREADS" \
        --time="$BURST_DURATION" \
        --progress=10 \
        --builtin=tpcb-like \
        2>&1 | tail -20

    echo "[pgbench] Cycle $CYCLE: burst done. Idling for ${IDLE_DURATION}s."
    sleep "$IDLE_DURATION"

    echo "[pgbench] Cycle $CYCLE: light read-only cooldown queries."
    pgbench -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
        --client=3 \
        --jobs=1 \
        --time=30 \
        --select-only \
        --quiet \
        2>&1 | tail -5

    CYCLE=$((CYCLE + 1))
done

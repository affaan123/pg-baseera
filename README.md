# 🐘 pg-baseera

> **Stop flying blind on your PostgreSQL databases.**
> pg-baseera gives your team real-time visibility into database performance, query bottlenecks, and system health deployed in minutes, not days.

pg-baseera is a production-ready, open-source PostgreSQL monitoring stack built on **Prometheus**, **Grafana**, and **pgBadger**. It is designed for engineering teams and database administrators who need deep observability into their PostgreSQL infrastructure without the cost or complexity of commercial APM tools.

Whether you are running a SaaS product, processing financial transactions, serving e-commerce traffic, or managing healthcare data, pg-baseera gives you the insight to keep your database performing at its best.

---

## Table of Contents

- [Why pg-baseera?](#why-pg-baseera)
- [Business Use Cases](#business-use-cases)
- [What You Get Out of the Box](#what-you-get-out-of-the-box)
- [Technology Stack](#technology-stack)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
  - [Mode A: Full stack](#mode-a-full-stack-includes-postgresql)
  - [Mode B: External PostgreSQL](#mode-b-monitor-your-existing-postgresql)
- [Accessing Services](#accessing-services)
- [Go Status Monitor API](#go-status-monitor-api)
- [pgBench Load Testing](#pgbench-load-testing)
- [PostgreSQL Logging](#postgresql-logging-for-pgbadger)
- [Customizing Ports](#customizing-ports)
- [Custom Metrics](#custom-metrics)
- [Stopping](#stopping)
- [Troubleshooting](#troubleshooting)
  - [pg_up shows 0](#pg_up-shows-0--exporter-cannot-connect-to-postgresql)
  - [Permission denied on log file](#postgresql-container-is-unhealthy--permission-denied-on-log-file)
  - [pgbench-init fails with exit 127](#pgbench-init-fails-with-exit-127)
  - [Prometheus queries return empty](#prometheus-queries-return-empty-with-label-filter)
  - [Grafana shows No data](#grafana-dashboard-shows-no-data)
  - [pgBadger report has no queries](#pgbadger-report-has-no-queries)
  - [pg_ prefix reserved error](#pg_-prefix-reserved-error-on-first-start)
- [License](#license)

---

## Why pg-baseera?

### The Problem

Database problems are invisible until they become crises. Slow queries silently degrade user experience. Connection pool exhaustion causes cascading failures. Table bloat grows unnoticed until disk space runs out. Without proper monitoring, team is always reacting rather than preventing.

### The Solution

pg-baseera provides a complete observability stack that answers the questions that matter:

- **Is my database healthy right now?**: Live health dashboard across all services.
- **What queries are slowing my application down?**: Slow query analysis via pgBadger HTML reports.
- **Are we approaching connection limits?**: Real-time connection tracking in Grafana.
- **Is my cache hit ratio healthy?**: Buffer cache efficiency metrics.
- **Where is disk space going?**: Table size and bloat tracking.
- **Is replication keeping up?**: Replication lag monitoring.

---

## Business Use Cases

### 🛒 E-commerce & Retail
Traffic spikes on special occasions can overwhelm a database in seconds. pg-baseera gives real-time TPS (transactions per second) graphs, connection surge visibility, and query performance trends so the team can identify and resolve bottlenecks before customers notice.

### 💳 Fintech & Banking
Financial applications demand sub-millisecond query performance and zero downtime. pg-baseera tracks deadlocks, long-running transactions, rollback rates, and replication lag. These are the metrics that matter most for data integrity and regulatory compliance.

### 🏥 Healthcare & Compliance
Healthcare systems require audit trails and performance guarantees. pgBadger generates detailed query analysis reports that document database behaviour over time, supporting compliance reviews and capacity planning conversations with stakeholders.

### ☁️ SaaS Products
Multi-tenant SaaS applications need to understand per-database performance as they scale. pg-baseera tracks database sizes, connection counts, and query throughput simultaneously giving engineering team the data to make informed scaling decisions before they become incidents.

### 🏢 Enterprise Applications
;Large organisations running PostgreSQL as a backend for ERP, CRM, or data warehouse systems need visibility across the full stack: from OS-level CPU and memory (via Node Exporter) to query-level execution times. pg-baseera delivers all of this in a single, self-hosted, auditable stack with no data leaving your infrastructure.

### 🚀 Startups & Scale-ups
Growing teams often lack dedicated DBAs. pg-baseera gives developers the observability they need to self-serve database performance investigations. This in turn reduces mean time to resolution (MTTR) and frees the senior engineers from firefighting.

---

## What You Get Out of the Box

| Capability | Delivered By |
|---|---|
| Real-time metrics dashboard | Grafana with Prometheus |
| Slow query HTML reports | pgBadger |
| Query throughput & latency trends | postgres_exporter with Grafana |
| Connection pool monitoring | postgres_exporter with Grafana |
| Cache hit ratio tracking | postgres_exporter with Grafana |
| Table bloat & dead tuple tracking | Custom queries with Grafana |
| Replication lag monitoring | postgres_exporter with Grafana |
| OS-level host metrics | Node Exporter with Grafana |
| Service health watchdog | Go status monitor |
| Load simulation for testing | pgBench (burst mode) |
| External DB support | Mode B (connect to existing PostgreSQL) |

---

## Technology Stack

| Service | Purpose | Port |
|---|---|---|
| PostgreSQL | Database (Mode A only) | 5432 |
| postgres_exporter | Exposes PG metrics to Prometheus | 9187 |
| Prometheus | Metrics storage & querying | 9090 |
| Grafana | Dashboards & visualization | 3000 |
| pgBadger | Log-based HTML query reports | 8080 |
| Node Exporter | Host system metrics | 9100 |
| pgBench | Load simulator | — |
| GO monitor | Health dashboard & log watcher | 9999 |

---

## Architecture

```
pgBench (load)
     │
     ▼
PostgreSQL ──► postgres_exporter ──► Prometheus ──► Grafana
     │
     └── logs ──► pgBadger ──► HTML reports (port 8080)

GO monitor ──► health checks all services ──► dashboard (port 9999)
```

---

## Project Directory Structure

```
pg-baseera/
├── Dockerfile                        # pgBadger container.
├── docker-compose.yml                # Full stack definition.
├── monitor.go                        # GO status monitor source.
├── start.sh                          # Entry startup script.
├── stop.sh                           # Graceful stop script.
├── cleanup.sh                        # Wipe everything and start fresh.
├── .env.example                      # Configuration template.
├── docs/
│   └── external-db-setup.sql         # SQL for Mode B (existing DB).
├── exporter/
│   └── queries.yaml                  # Custom Prometheus metrics.
├── grafana/
│   ├── dashboards/
│   │   └── postgresql.json           # Pre-built Grafana dashboard.
│   └── provisioning/
│       ├── dashboards/dashboards.yml # Dashboard auto-provisioning.
│       └── datasources/prometheus.yml# Datasource auto-provisioning.
├── pgbadger/
│   ├── entrypoint.sh                 # pgBadger container entrypoint.
│   └── reports/                      # Generated HTML reports (gitignored).
├── postgres/
│   ├── init/
│   │   └── 01_exporter_user.sh       # Creates pgexporter user on first start.
│   ├── logs/                         # PostgreSQL logs (gitignored).
│   ├── pg_hba.conf                   # PostgreSQL auth config.
│   ├── pgbench_load.sh               # pgBench burst load script.
│   └── postgresql.conf               # PostgreSQL config (logging tuned for pgBadger).
└── prometheus/
    └── prometheus.yml                # Prometheus scrape config.
```

---

## Prerequisites

- Docker with Docker Compose v2.
- Go 1.21+ (for the status monitor binary).
- 2GB RAM minimum (4GB recommended with pgBench).

---

## Quickstart

### Mode A: Full stack (includes PostgreSQL)

```bash
# 1. Clone the repo
git clone https://github.com/affaan123/pg-baseera.git
cd pg-baseera

# 2. Configure
cp .env.example .env
# Edit .env and change all 'changeme' passwords

# 3. Fix log directory permissions
sudo chown 999:999 postgres/logs
sudo chmod 775 postgres/logs

# 4. Build the Go status monitor
go build -o pg-monitor-bin ./monitor.go

# 5. Start the stack
./start.sh

# 6. Start the Go status monitor (separate terminal)
./pg-monitor-bin
```

### Mode B: Monitor your existing PostgreSQL

```bash
# 1. Clone the repo
git clone https://github.com/affaan123/pg-baseera.git
cd pg-baseera

# 2. Prepare your existing database
# Run the SQL in docs/external-db-setup.sql on your PostgreSQL instance

# 3. Configure
cp .env.example .env

# Edit .env — set your external DSN and disable pgbench:
#   EXTERNAL_DB_DSN=postgresql://pgexporter:pass@your-host:5432/yourdb?sslmode=require
#   PGBENCH_ENABLED=false

# 4. Build the Go status monitor
go build -o pg-monitor-bin ./monitor.go

# 5. Start
./start.sh

# 6. Start the Go status monitor (separate terminal)
./pg-monitor-bin
```

---

## Accessing Services

| Service | URL | Default credentials |
|---|---|---|
| Grafana | http://localhost:3000 | admin / (your .env value) |
| Prometheus | http://localhost:9090 | NA |
| pgBadger reports | http://localhost:8080 | NA |
| Go status dashboard | http://localhost:9999 | NA |
| postgres_exporter metrics | http://localhost:9187/metrics | NA |

---

## Go Status Monitor API

The Go binary exposes two JSON endpoints in addition to the web dashboard:

| Endpoint | Description |
|---|---|
| `GET http://localhost:9999/` | HTML status dashboard (auto-refreshes every 30s) |
| `GET http://localhost:9999/api/health` | JSON array of all service health states |
| `GET http://localhost:9999/api/reports` | JSON array of last 20 pgBadger report records |

Example:
```bash
# Check all service health states as JSON
curl http://localhost:9999/api/health

# Check pgBadger report history as JSON
curl http://localhost:9999/api/reports
```

---

## pgBench Load Testing

pgBench simulates a realistic TPC-B workload against PostgreSQL.
It runs in **burst mode** by default as heavy load for 60s followed by idle for 240s.

| Variable | Default | Description |
|---|---|---|
| PGBENCH_ENABLED | true | Enable/disable load testing |
| PGBENCH_CLIENTS | 20 | Concurrent clients |
| PGBENCH_THREADS | 4 | Worker threads |
| PGBENCH_BURST_DURATION | 60 | Seconds of heavy load |
| PGBENCH_IDLE_DURATION | 240 | Seconds of idle between bursts |

To disable pgBench:
```bash
# In .env
PGBENCH_ENABLED=false
```

---

## PostgreSQL Logging (for pgBadger)

pg-baseera configures PostgreSQL to log queries slower than **100ms**.
This keeps logs manageable in production. To capture all queries for testing:

```bash
# In postgres/postgresql.conf
log_min_duration_statement = 0
# Then reload without restart:
docker exec postgres psql -U pgadmin -c "SELECT pg_reload_conf();"
```

---

## Ports Customization

All ports are configurable in `.env`:

```bash
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
PGBADGER_PORT=8080
NODE_EXPORTER_PORT=9100
EXPORTER_PORT=9187
POSTGRES_PORT=5432
MONITOR_PORT=9999
```

---

## Custom Metrics

Add your own PostgreSQL queries to `exporter/queries.yaml`.
They will be automatically exposed as Prometheus metrics and
available in Grafana. See the existing file for examples.

**Important:** Do not redefine metrics already collected by
postgres_exporter (e.g. `pg_database_size_bytes`, `pg_replication_*`).
Only add genuinely new queries to avoid metric conflicts.

---

## Shutting down the stack

```bash
# Stop all containers (preserve data)
./stop.sh

# Stop and wipe all data volumes
./cleanup.sh
```

---

## Troubleshooting

### pg_up shows 0: exporter cannot connect to PostgreSQL

**Symptom:** `curl http://localhost:9187/metrics | grep pg_up` returns `pg_up 0`

**Cause:** Password mismatch between `.env` and what was created in the database.
This can happen if you changed `EXPORTER_PASSWORD` in `.env` after the first start.

**Fix:**
```bash
source .env
docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "ALTER USER pgexporter WITH PASSWORD '$EXPORTER_PASSWORD';"
docker compose restart postgres-exporter
sleep 10
curl http://localhost:9187/metrics | grep pg_up
```

---

### PostgreSQL container is unhealthy — Permission denied on log file

**Symptom:** `docker logs postgres` shows:
```
FATAL: could not open log file "/var/log/postgresql/postgresql-YYYY-MM-DD.log": Permission denied
```

**Cause:** The `postgres/logs` directory is owned by your host user but the
PostgreSQL container runs as UID 999.

**Fix:**
```bash
sudo chown 999:999 postgres/logs
sudo chmod 775 postgres/logs
docker compose restart postgres
```

---

### pgbench-init fails with exit 127

**Symptom:** `docker logs pgbench-init` shows `sh: pgbench: not found`

**Cause:** Shell quoting issue in the compose command block prevents
the binary from being found.

**Fix:** Ensure the `pgbench-init` service in `docker-compose.yml` uses
`entrypoint: ["/bin/sh", "-c"]` with a multiline `command:` block,
not the `command: >` folded scalar form.

---

### Prometheus queries return empty with label filter

**Symptom:**
```bash
curl "http://localhost:9090/api/v1/query?query=pg_stat_database_numbackends{datname=\"appdb\"}"
# returns empty result
```

**Cause:** Shell double-quote escaping strips the label filter.

**Fix:** Always use single quotes around the full URL:
```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_database_numbackends{datname="appdb"}' \
  | python3 -m json.tool
```

---

### Grafana dashboard shows "No data"

**Symptom:** Panels load but show no data or "No data" message.

**Causes and fixes:**

1. **Metric name conflicts**: custom `queries.yaml` conflicts with built-in
   postgres_exporter metrics. Check for errors:
   ```bash
   curl http://localhost:9187/metrics | head -20
   ```
   If you see `collected metric X has help Y but should have Z`, remove
   the conflicting metric from `exporter/queries.yaml` and restart:
   ```bash
   docker compose restart postgres-exporter
   ```

2. **Prometheus not scraped yet**: wait 30s after startup before
   expecting data in Grafana.

3. **Time range too narrow**: in Grafana set the time range to
   `Last 1 hour`.

---

### pgBadger report has no queries

**Symptom:** pgBadger HTML report opens but shows 0 queries analyzed.

**Cause:** `log_min_duration_statement = 100` filters out fast queries.
pgBench queries average 6-8ms so nothing gets logged at this threshold.

**Fix for testing:**
```bash
docker exec postgres psql -U pgadmin -d appdb \
  -c "ALTER SYSTEM SET log_min_duration_statement = 0;"
docker exec postgres psql -U pgadmin -d appdb \
  -c "SELECT pg_reload_conf();"

# Trigger a manual report after the next pgbench burst
docker exec pgbadger /bin/bash -c "
  pgbadger --format stderr \
    --prefix '%t [%p]: user=%u,db=%d,app=%a,client=%h ' \
    --outfile /reports/report_manual.html \
    /logs/postgresql-\$(date +%Y-%m-%d).log &&
  ln -sf /reports/report_manual.html /reports/latest.html
"
```

---

### pg_ prefix reserved error on first start

**Symptom:** `docker logs postgres` shows:
```
ERROR: role name "pg_exporter" is reserved
DETAIL: Role names starting with "pg_" are reserved.
```

**Cause:** PostgreSQL 16 reserves all role names starting with `pg_`.

**Fix:** The init script uses `pgexporter` (no underscore after pg).
If you see this error it means an old init SQL file is present. Run:
```bash
./cleanup.sh && ./start.sh
```

---

## License

MIT © pg-baseera contributors: see [LICENSE](./LICENSE) for full text

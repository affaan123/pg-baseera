# 🐘 pg-baseera

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Docker](https://img.shields.io/badge/Docker-required-blue?logo=docker)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)
![Grafana](https://img.shields.io/badge/Grafana-dashboard-orange?logo=grafana)

> **Stop flying blind on your PostgreSQL databases.**
> pg-baseera gives your team real-time visibility into database performance, query bottlenecks, and system health deployed in minutes, not days.

pg-baseera is a production-ready, open-source PostgreSQL monitoring stack built on **Prometheus**, **Grafana**, and **pgBadger**. It is designed for engineering teams and database administrators who need deep observability into their PostgreSQL infrastructure without the cost or complexity of commercial APM tools.

Whether you are running a SaaS product, processing financial transactions, serving e-commerce traffic, or managing healthcare data; pg-baseera gives you the insight to keep your database performing at its best.

---

## Table of Contents

- [Why pg-baseera?](#why-pg-baseera)
- [Business Use Cases](#business-use-cases)
- [What You Get Out of the Box](#what-you-get-out-of-the-box)
- [Stack](#stack)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
  - [Mode A: Full stack](#mode-a-full-stack)
  - [Mode B: External PostgreSQL](#mode-b-external-postgresql)
- [RDS Extension](#rds-extension)
  - [Phase 1: pgBadger via CloudWatch Logs](#phase-1-pgbadger-via-cloudwatch-logs)
  - [Phase 2: CloudWatch Metrics in Grafana](#phase-2-cloudwatch-metrics-in-grafana)
  - [Phase 3: postgres-exporter for PostgreSQL Internals](#phase-3-postgres-exporter-for-postgresql-internals)
- [Kubernetes Delivery Package](#kubernetes-delivery-package)
- [Accessing Services](#accessing-services)
- [Go Status Monitor API](#go-status-monitor-api)
- [pgBench Load Testing](#pgbench-load-testing)
- [PostgreSQL Logging](#postgresql-logging)
- [Customizing Ports](#customizing-ports)
- [Custom Metrics](#custom-metrics)
- [Stopping](#stopping)
- [Troubleshooting](#troubleshooting)
  - [pg_up shows 0](#pg_up-shows-0)
  - [Permission denied on log file](#permission-denied-on-log-file)
  - [pgbench-init fails with exit 127](#pgbench-init-fails-with-exit-127)
  - [Prometheus queries return empty](#prometheus-queries-return-empty)
  - [Grafana shows No data](#grafana-shows-no-data)
  - [pgBadger report has no queries](#pgbadger-report-has-no-queries)
  - [pg_ prefix reserved error](#pg_-prefix-reserved-error)
- [License](#license)

---

## Why pg-baseera?

### The Problem

Database problems are invisible until they become crises. Slow queries silently degrade user experience. Connection pool exhaustion causes cascading failures. Table bloat grows unnoticed until disk space runs out. Without proper monitoring, your team is always reacting — never preventing.

### The Solution

pg-baseera provides a complete observability stack that answers the questions that matter:

- **Is my database healthy right now?** Live health dashboard across all services
- **What queries are slowing my application down?** Slow query analysis via pgBadger HTML reports
- **Are we approaching connection limits?** Real-time connection tracking in Grafana
- **Is my cache hit ratio healthy?** Buffer cache efficiency metrics
- **Where is disk space going?** Table size and bloat tracking
- **Is replication keeping up?** Replication lag monitoring

---

## Business Use Cases

### 🛒 E-commerce & Retail
Black Friday traffic spikes can overwhelm a database in seconds. pg-baseera gives you real-time TPS (transactions per second) graphs, connection surge visibility, and query performance trends so your team can identify and resolve bottlenecks before customers notice.

### 💳 Fintech & Banking
Financial applications demand sub-millisecond query performance and zero downtime. pg-baseera tracks deadlocks, long-running transactions, rollback rates, and replication lag — the metrics that matter most for data integrity and regulatory compliance.

### 🏥 Healthcare & Compliance
Healthcare systems require audit trails and performance guarantees. pgBadger generates detailed query analysis reports that document database behaviour over time, supporting compliance reviews and capacity planning conversations with stakeholders.

### ☁️ SaaS Products
Multi-tenant SaaS applications need to understand per-database performance as they scale. pg-baseera tracks database sizes, connection counts, and query throughput simultaneously — giving your engineering team the data to make informed scaling decisions before they become incidents.

### 🏢 Enterprise Applications
Large organisations running PostgreSQL as a backend for ERP, CRM, or data warehouse systems need visibility across the full stack — from OS-level CPU and memory (via Node Exporter) to query-level execution times. pg-baseera delivers all of this in a single, self-hosted, auditable stack with no data leaving your infrastructure.

### 🚀 Startups & Scale-ups
Growing teams often lack dedicated DBAs. pg-baseera gives developers the observability they need to self-serve database performance investigations — reducing mean time to resolution (MTTR) and freeing senior engineers from firefighting.

---

## What You Get Out of the Box

| Capability | Delivered By |
|---|---|
| Real-time metrics dashboard | Grafana and Prometheus |
| Slow query HTML reports | pgBadger |
| Query throughput & latency trends | postgres_exporter and Grafana |
| Connection pool monitoring | postgres_exporter and Grafana |
| Cache hit ratio tracking | postgres_exporter and Grafana |
| Table bloat & dead tuple tracking | Custom queries and Grafana |
| Replication lag monitoring | postgres_exporter and Grafana |
| OS-level host metrics | Node Exporter and Grafana |
| Service health watchdog | Go status monitor |
| Load simulation for testing | pgBench (burst mode) |
| External DB support | Mode B (connect to existing PostgreSQL) |
| AWS RDS monitoring | RDS extension (CloudWatch and pgBadger) |
| Kubernetes delivery package | Helm patches and K8s manifests |

---

## Stack

| Service | Purpose | Port |
|---|---|---|
| PostgreSQL | Database (Mode A only) | 5432 |
| postgres_exporter | Exposes PG metrics to Prometheus | 9187 |
| rds-exporter-staging-primary | RDS staging primary metrics | 9188 |
| rds-exporter-staging-replica | RDS staging replica metrics | 9189 |
| Prometheus | Metrics storage & querying | 9090 |
| Alertmanager | Alert routing (Slack-ready) | 9093 |
| Grafana | Dashboards & visualization | 3000 |
| pgBadger | Log-based HTML query reports | 8080 |
| Node Exporter | Host system metrics | 9100 |
| pgBench | Load simulator (opt-out) | — |
| Go monitor | Health dashboard & log watcher | 9999 |

---

## Architecture

```
pgBench (load)
     │
     ▼
PostgreSQL ──► postgres_exporter ──► Prometheus ──► Alertmanager
     │              ▲                     │
     │              │                     ▼
     │         RDS exporters          Grafana
     │         (staging x2)       (Prometheus +
     │                             CloudWatch
     └── logs ──► pgBadger          datasources)
                    ▲
                    │
     CloudWatch Logs (RDS) ──► log_sync.sh

Go monitor ──► health checks all services ──► dashboard (port 9999)
```

---

## Project Structure

```
pg-baseera/
├── Dockerfile                        # pgBadger container
├── docker-compose.yml                # Full stack definition
├── monitor.go                        # Go status monitor source
├── start.sh                          # Smart startup script
├── stop.sh                           # Graceful stop script
├── cleanup.sh                        # Wipe everything and start fresh
├── .env.example                      # Configuration template
├── docs/
│   └── external-db-setup.sql         # SQL for Mode B (existing DB)
├── exporter/
│   └── queries.yaml                  # Custom Prometheus metrics
├── grafana/
│   ├── dashboards/postgresql.json    # Pre-built Grafana dashboard
│   └── provisioning/
│       ├── dashboards/dashboards.yml
│       └── datasources/prometheus.yml
├── k8s/                              # Kubernetes delivery package
│   ├── README.md                     # K8s deployment guide
│   ├── cloudwatch/
│   │   └── grafana-cloudwatch-ds.yaml
│   ├── helm/
│   │   ├── grafana-dashboard-cm.yaml
│   │   ├── postgres-exporter-patch.yaml
│   │   └── prometheus-rules.yaml
│   └── pgbadger/
│       ├── cronjob.yaml
│       ├── deployment.yaml
│       └── service.yaml
├── pgbadger/
│   ├── entrypoint.sh                 # pgBadger container entrypoint
│   └── reports/                      # Generated HTML reports (gitignored)
├── postgres/
│   ├── init/01_exporter_user.sql     # Creates pgexporter user on first start
│   ├── logs/                         # PostgreSQL logs (gitignored)
│   ├── pg_hba.conf
│   ├── pgbench_load.sh               # pgBench burst load script
│   └── postgresql.conf
├── prometheus/
│   └── prometheus.yml                # Prometheus scrape config
└── rds/                              # RDS extension
    ├── alert_rules.yml               # 7 Prometheus alert rules
    ├── alertmanager.yml              # Alertmanager routing config
    ├── log_sync.sh                   # CloudWatch Logs → pgBadger sync
    ├── dashboards/rds_postgresql.json
    └── provisioning/
        ├── dashboards/rds_dashboards.yml
        └── datasources/cloudwatch.yml
```

---

## Prerequisites

- Docker and Docker Compose v2.
- Go 1.21+ (for the status monitor binary)
- 2GB RAM minimum (4GB recommended with pgBench)
- AWS CLI + credentials (for RDS extension)

---

## Quickstart

### Mode A: Full stack

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

### Mode B: External PostgreSQL

```bash
# 1. Clone the repo
git clone https://github.com/affaan123/pg-baseera.git
cd pg-baseera

# 2. Prepare your existing database
# Run the SQL in docs/external-db-setup.sql on your PostgreSQL instance

# 3. Configure
cp .env.example .env

# Edit .env:
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

## RDS Extension

pg-baseera supports AWS RDS PostgreSQL monitoring in three phases.
Each phase is independent. Deploy only what you need.

### Phase 1: pgBadger via CloudWatch Logs

No VPC access required. Uses IAM credentials only.

```bash
# Configure in .env
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_REGION=your-region
RDS_STAGING_PRIMARY_LOG_GROUP=/aws/rds/instance/staging-rds-pg/postgresql

# Sync logs and generate report
./rds/log_sync.sh

# Run pgBadger against downloaded logs
pgbadger --format rds \
  --outfile pgbadger/reports/rds-report.html \
  postgres/logs/postgresql-staging-primary-$(date +%Y-%m-%d).log

# Or sync a specific date
./rds/log_sync.sh 2026-04-30
```

**Required IAM permissions:** `CloudWatchReadOnlyAccess`

**Required RDS parameter group settings:**
- `log_min_duration_statement` Set to desired threshold (e.g. 100ms)
- `log_checkpoints = on`
- `log_connections = on`
- `log_disconnections = on`
- `log_lock_waits = on`

### Phase 2: CloudWatch Metrics in Grafana

Adds AWS RDS host metrics (CPU, memory, disk, connections, replica lag)
to your Grafana instance via the CloudWatch datasource.

```bash
# Add to .env
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret

# Start stack (CloudWatch datasource auto-provisioned)
./start.sh

# Open Grafana → RDS folder → RDS PostgreSQL — Staging dashboard
```

### Phase 3: postgres-exporter for PostgreSQL Internals

Requires network connectivity from pg-baseera host to RDS (VPC or VPN).

```bash
# Add to .env
RDS_STAGING_PRIMARY_HOST=staging-rds-pg.xxxx.region.rds.amazonaws.com
RDS_STAGING_REPLICA_HOST=staging-rds-pg-replica.xxxx.region.rds.amazonaws.com
RDS_EXPORTER_USER=pgexporter
RDS_EXPORTER_PASSWORD=your-password

# Start stack
./start.sh
```

Adds per-table bloat, pg_stat_statements slow queries, TPS,
lock analysis — metrics not available from CloudWatch alone.

---

## Kubernetes Delivery Package

For teams already running **kube-prometheus-stack** on Kubernetes,
pg-baseera provides a ready-to-apply configuration package
in the `k8s/` directory.

See [k8s/README.md](./k8s/README.md) for full deployment instructions.

**What is delivered:**

| File | Purpose |
|---|---|
| `helm/prometheus-rules.yaml` | 7 PrometheusRule alert rules as K8s CRD |
| `helm/postgres-exporter-patch.yaml` | Custom query additions for Helm upgrade |
| `helm/grafana-dashboard-cm.yaml` | RDS dashboard as Grafana sidecar ConfigMap |
| `cloudwatch/grafana-cloudwatch-ds.yaml` | CloudWatch datasource and AWS secret |
| `pgbadger/deployment.yaml` | Standalone pgBadger pod |
| `pgbadger/service.yaml` | ClusterIP service on port 8080 |
| `pgbadger/cronjob.yaml` | Hourly scheduled report generation |

---

## Accessing Services

| Service | URL | Default credentials |
|---|---|---|
| Grafana | http://localhost:3000 | admin / (your .env value) |
| Prometheus | http://localhost:9090 | — |
| Alertmanager | http://localhost:9093 | — |
| pgBadger reports | http://localhost:8080 | — |
| Go status dashboard | http://localhost:9999 | — |
| postgres_exporter | http://localhost:9187/metrics | — |
| RDS exporter (primary) | http://localhost:9188/metrics | — |
| RDS exporter (replica) | http://localhost:9189/metrics | — |

---

## Go Status Monitor API

| Endpoint | Description |
|---|---|
| `GET http://localhost:9999/` | HTML status dashboard (auto-refreshes every 30s) |
| `GET http://localhost:9999/api/health` | JSON array of all service health states |
| `GET http://localhost:9999/api/reports` | JSON array of last 20 pgBadger report records |

```bash
curl http://localhost:9999/api/health
curl http://localhost:9999/api/reports
```

---

## pgBench Load Testing

| Variable | Default | Description |
|---|---|---|
| PGBENCH_ENABLED | true | Enable/disable load testing |
| PGBENCH_CLIENTS | 20 | Concurrent clients |
| PGBENCH_THREADS | 4 | Worker threads |
| PGBENCH_BURST_DURATION | 60 | Seconds of heavy load |
| PGBENCH_IDLE_DURATION | 240 | Seconds of idle between bursts |

```bash
# Disable in .env
PGBENCH_ENABLED=false
```

---

## PostgreSQL Logging

pg-baseera configures PostgreSQL to log queries slower than **100ms**.

```bash
# Lower threshold for testing (logs all queries)
docker exec postgres psql -U pgadmin -c \
  "ALTER SYSTEM SET log_min_duration_statement = 0;"
docker exec postgres psql -U pgadmin -c "SELECT pg_reload_conf();"
```

---

## Customizing Ports

```bash
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
ALERTMANAGER_PORT=9093
PGBADGER_PORT=8080
NODE_EXPORTER_PORT=9100
EXPORTER_PORT=9187
POSTGRES_PORT=5432
MONITOR_PORT=9999
```

---

## Custom Metrics

Add queries to `exporter/queries.yaml`. Do not redefine metrics
already collected by postgres_exporter (e.g. `pg_database_size_bytes`,
`pg_replication_*`) to avoid metric conflicts.

---

## Stopping

```bash
./stop.sh        # stop containers, preserve data
./cleanup.sh     # stop containers, wipe all data volumes
```

---

## Troubleshooting

### pg_up shows 0

**Cause:** Password mismatch between `.env` and database.

```bash
source .env
docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "ALTER USER pgexporter WITH PASSWORD '$EXPORTER_PASSWORD';"
docker compose restart postgres-exporter
sleep 10 && curl http://localhost:9187/metrics | grep pg_up
```

---

### Permission denied on log file

**Cause:** `postgres/logs` owned by wrong user.

```bash
sudo chown 999:999 postgres/logs
sudo chmod 775 postgres/logs
docker compose restart postgres
```

---

### pgbench-init fails with exit 127

**Cause:** Shell quoting issue in compose command block.
Ensure `pgbench-init` uses `entrypoint: ["/bin/sh", "-c"]`
with a multiline `command:` block.

---

### Prometheus queries return empty

**Cause:** Shell escaping strips label filter braces.
Always use single quotes:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_database_numbackends{datname="appdb"}' \
  | python3 -m json.tool
```

---

### Grafana shows No data

1. Check for metric conflicts:
   ```bash
   curl http://localhost:9187/metrics | head -20
   ```
   Remove conflicting entries from `exporter/queries.yaml` and restart.

2. Wait 30s after startup for first Prometheus scrape.

3. Set Grafana time range to `Last 1 hour`.

---

### pgBadger report has no queries

**Cause:** `log_min_duration_statement` threshold too high.

```bash
# Lower for testing
docker exec postgres psql -U pgadmin -d appdb \
  -c "ALTER SYSTEM SET log_min_duration_statement = 0;"
docker exec postgres psql -U pgadmin -d appdb \
  -c "SELECT pg_reload_conf();"

# Generate manual report
docker exec pgbadger /bin/bash -c "
  pgbadger --format stderr \
    --prefix '%t [%p]: user=%u,db=%d,app=%a,client=%h ' \
    --outfile /reports/report_manual.html \
    /logs/postgresql-\$(date +%Y-%m-%d).log &&
  ln -sf /reports/report_manual.html /reports/latest.html
"
```

For RDS logs use `--format rds` (no `--prefix` needed):
```bash
pgbadger --format rds \
  --outfile pgbadger/reports/rds-report.html \
  postgres/logs/postgresql-staging-primary-$(date +%Y-%m-%d).log
```

---

### pg_ prefix reserved error

**Cause:** PostgreSQL 16 reserves role names starting with `pg_`.

```bash
./cleanup.sh && ./start.sh
```

---

## License

MIT © pg-baseera contributors. See [LICENSE](./LICENSE) for full text.

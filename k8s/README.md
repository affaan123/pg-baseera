# pg-baseera — Kubernetes Configuration Package

![Kubernetes](https://img.shields.io/badge/Kubernetes-ready-326CE5?logo=kubernetes)
![Helm](https://img.shields.io/badge/Helm-values--patch-0F1689?logo=helm)
![AWS](https://img.shields.io/badge/AWS-CloudWatch-FF9900?logo=amazonaws)

Configuration package for teams already running **kube-prometheus-stack** on Kubernetes.
Extends your existing stack with RDS PostgreSQL monitoring and pgBadger slow query reports —
without replacing or duplicating anything you already have.

---

## Table of Contents

- [What This Package Does](#what-this-package-does)
- [Prerequisites](#prerequisites)
- [Package Structure](#package-structure)
- [Architecture](#architecture)
- [Deployment Guide](#deployment-guide)
  - [Step 1: Create AWS Credentials Secret](#step-1-create-aws-credentials-secret)
  - [Step 2: Apply Prometheus Alert Rules](#step-2-apply-prometheus-alert-rules)
  - [Step 3: Patch postgres-exporter with Custom Queries](#step-3-patch-postgres-exporter-with-custom-queries)
  - [Step 4: Add CloudWatch Datasource to Grafana](#step-4-add-cloudwatch-datasource-to-grafana)
  - [Step 5: Import RDS Dashboard into Grafana](#step-5-import-rds-dashboard-into-grafana)
  - [Step 6: Deploy pgBadger](#step-6-deploy-pgbadger)
  - [Step 7: Access pgBadger Reports](#step-7-access-pgbadger-reports)
- [Alert Rules Reference](#alert-rules-reference)
- [Grafana Sidecar Requirements](#grafana-sidecar-requirements)
- [PrometheusRule Label Matching](#prometheusrule-label-matching)
- [pgBadger: Deployment vs CronJob](#pgbadger-deployment-vs-cronjob)
- [Verify Everything is Working](#verify-everything-is-working)
- [Troubleshooting](#troubleshooting)
- [Removing the Package](#removing-the-package)

---

## What This Package Does

| File | What it adds |
|---|---|
| `helm/prometheus-rules.yaml` | 7 PostgreSQL alert rules as a `PrometheusRule` CRD |
| `helm/postgres-exporter-patch.yaml` | `pg_stat_statements` and table bloat custom queries |
| `helm/grafana-dashboard-cm.yaml` | RDS PostgreSQL dashboard (CloudWatch + Prometheus panels) |
| `cloudwatch/grafana-cloudwatch-ds.yaml` | CloudWatch datasource + AWS credentials secret |
| `pgbadger/deployment.yaml` | Standalone pgBadger pod serving HTML reports on port 8080 |
| `pgbadger/service.yaml` | ClusterIP service exposing pgBadger inside the cluster |
| `pgbadger/cronjob.yaml` | Alternative: hourly scheduled report generation job |

**Nothing in this package modifies your existing kube-prometheus-stack installation.**
All additions are additive — new CRDs, ConfigMaps, and a standalone Deployment.

---

## Prerequisites

Before applying this package confirm the following:

- `kube-prometheus-stack` is deployed and healthy
- `prometheus-postgres-exporter` Helm chart is deployed and scraping your RDS instance
- `kubectl` access to the target namespace (`default`)
- AWS IAM credentials with the following permissions:
  - `CloudWatchReadOnlyAccess`
  - `logs:GetLogEvents`
  - `logs:DescribeLogStreams`
  - `logs:DescribeLogGroups`
- PostgreSQL `pg_stat_statements` extension enabled on your RDS instance
- RDS parameter group has logging enabled (see RDS Parameter Requirements below)

### RDS Parameter Requirements

These parameters must be set on your RDS parameter group for pgBadger
to have data to analyze:

| Parameter | Recommended Value | Purpose |
|---|---|---|
| `log_min_duration_statement` | `100` (ms) | Log queries slower than 100ms |
| `log_checkpoints` | `1` | Log checkpoint activity |
| `log_connections` | `1` | Log new connections |
| `log_disconnections` | `1` | Log disconnections |
| `log_lock_waits` | `1` | Log lock wait events |
| `log_temp_files` | `0` | Log all temp file creation |
| `log_autovacuum_min_duration` | `250` | Log slow autovacuum runs |
| `shared_preload_libraries` | `pg_stat_statements` | Enable query stats |
| `pg_stat_statements.track` | `all` | Track all statements |

> **Note:** Parameter group changes require a reboot for `pending-reboot` parameters.
> Check the apply method column in your parameter group before applying.

---

## Package Structure

```
k8s/
├── README.md                          # This file
├── cloudwatch/
│   └── grafana-cloudwatch-ds.yaml     # CloudWatch datasource + AWS secret
├── helm/
│   ├── grafana-dashboard-cm.yaml      # RDS Grafana dashboard ConfigMap
│   ├── postgres-exporter-patch.yaml   # Custom queries Helm values patch
│   └── prometheus-rules.yaml          # PrometheusRule CRD (7 alert rules)
└── pgbadger/
    ├── cronjob.yaml                   # Hourly report CronJob (alternative)
    ├── deployment.yaml                # Always-on pgBadger Deployment
    └── service.yaml                   # ClusterIP Service port 8080
```

---

## Architecture

```
AWS CloudWatch Logs          AWS CloudWatch Metrics
(RDS PostgreSQL logs)        (CPU, memory, disk, connections)
        |                              |
        v                              v
  pgBadger pod              Grafana CloudWatch datasource
  (log_sync + HTML)                    |
        |                              v
        v                    +---------------------+
  Service :8080              |  Existing Grafana    |
        |                    |  (kube-prom-stack)   |
        v                    |                      |
  kubectl port-forward       |  + RDS Dashboard     |
  or Ingress                 |  (new ConfigMap)     |
                             +---------------------+
                                        ^
                             +----------+-----------+
                             |  Existing Prometheus |
                             |  (kube-prom-stack)   |
                             |                      |
                             |  + 7 Alert Rules     |
                             |  (new CRD)           |
                             +---------------------+
                                        ^
                             +----------+-----------+
                             |  postgres-exporter   |
                             |  (existing Helm)     |
                             |                      |
                             |  + custom queries    |
                             |  (Helm patch)        |
                             +---------------------+
                                        |
                                        v
                                  AWS RDS PostgreSQL
                                  (staging primary +
                                   staging replica)
```

---

## Deployment Guide

### Step 1: Create AWS Credentials Secret

This secret is used by both the Grafana CloudWatch datasource and the pgBadger pod.

```bash
kubectl create secret generic aws-cloudwatch-credentials \
  --from-literal=access-key-id=YOUR_ACCESS_KEY_ID \
  --from-literal=secret-access-key=YOUR_SECRET_ACCESS_KEY \
  -n default
```

Verify:
```bash
kubectl get secret aws-cloudwatch-credentials -n default
```

> **Security note:** Never commit real credentials to Git.
> Use a secrets manager (AWS Secrets Manager, Vault, Sealed Secrets)
> in production environments.

---

### Step 2: Apply Prometheus Alert Rules

The `PrometheusRule` CRD is automatically picked up by the Prometheus Operator
via label selectors. No Prometheus restart required.

```bash
kubectl apply -f helm/prometheus-rules.yaml -n default
```

Verify the rule was loaded:
```bash
# Check CRD exists
kubectl get prometheusrule pg-baseera-rds-alerts -n default

# Check Prometheus picked it up (wait ~30s)
# Open Prometheus UI -> Status -> Rules
# Or check via API:
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring &
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep "pg-baseera"
```

> **Important:** If rules are not picked up, see
> [PrometheusRule Label Matching](#prometheusrule-label-matching).

---

### Step 3: Patch postgres-exporter with Custom Queries

This adds `pg_stat_statements` slow query metrics and table bloat metrics
to your existing postgres-exporter deployment.

```bash
helm upgrade prometheus-postgres-exporter \
  prometheus-community/prometheus-postgres-exporter \
  -f your-existing-values.yaml \
  -f helm/postgres-exporter-patch.yaml \
  -n default
```

Verify new metrics are exposed:
```bash
# Port-forward to the exporter
kubectl port-forward svc/prometheus-postgres-exporter 9187:9187 -n default &

# Check for new metrics
curl -s http://localhost:9187/metrics | grep "pg_stat_statements_top\|pg_table_bloat"
```

You should see metrics like:
```
pg_stat_statements_top_mean_ms{query="SELECT ..."} 42.3
pg_table_bloat_n_dead_tup{tablename="orders",...} 1234
```

---

### Step 4: Add CloudWatch Datasource to Grafana

Before applying, open `cloudwatch/grafana-cloudwatch-ds.yaml` and replace
the placeholder values in the Secret section:

```yaml
stringData:
  access-key-id: "REPLACE_WITH_ACCESS_KEY"      # <- replace this
  secret-access-key: "REPLACE_WITH_SECRET_KEY"  # <- replace this
```

> **Skip this edit** if you already created the secret in Step 1 —
> delete the Secret section from the file before applying to avoid conflicts.

```bash
kubectl apply -f cloudwatch/grafana-cloudwatch-ds.yaml -n default
```

Verify Grafana picked up the datasource:
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring &
# Open http://localhost:3000 -> Configuration -> Data Sources
# You should see "CloudWatch" listed
```

> **Requires:** Grafana sidecar with `sidecar.datasources.enabled: true`
> See [Grafana Sidecar Requirements](#grafana-sidecar-requirements).

---

### Step 5: Import RDS Dashboard into Grafana

The dashboard ConfigMap is automatically loaded by the Grafana sidecar.

```bash
kubectl apply -f helm/grafana-dashboard-cm.yaml -n default
```

Verify:
```bash
# Check ConfigMap exists
kubectl get configmap grafana-rds-postgresql-dashboard -n default

# In Grafana UI: Dashboards -> Browse -> RDS folder
# You should see "RDS PostgreSQL - Staging"
```

> **Requires:** Grafana sidecar with `sidecar.dashboards.enabled: true`
> See [Grafana Sidecar Requirements](#grafana-sidecar-requirements).

---

### Step 6: Deploy pgBadger

pgBadger runs as a standalone Deployment — completely independent of
your Prometheus/Grafana stack.

```bash
kubectl apply -f pgbadger/ -n default
```

This applies all three files (deployment, service, cronjob) at once.

Check the pod starts successfully:
```bash
kubectl get pods -n default -l app=pgbadger
kubectl logs -f deployment/pgbadger -n default
```

Expected log output:
```
[10:00:00] Syncing logs from CloudWatch...
[10:00:05] Generating pgBadger report...
[10:00:12] Report saved: /reports/report-2026-05-01.html
```

---

### Step 7: Access pgBadger Reports

#### Option A — kubectl port-forward (quick access)
```bash
kubectl port-forward svc/pgbadger 8080:8080 -n default
# Open http://localhost:8080
```

#### Option B — Ingress (permanent access)

Create an Ingress to expose pgBadger externally:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pgbadger-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - host: pgbadger.your-domain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: pgbadger
                port:
                  number: 8080
```

```bash
kubectl apply -f pgbadger-ingress.yaml -n default
```

---

## Alert Rules Reference

All 7 rules match the NX Infrastructure RDS Audit Report specification.

| # | Alert Name | Condition | Duration | Severity |
|---|---|---|---|---|
| 1 | `PostgresqlDown` | `pg_up == 0` | 1m | critical |
| 2 | `PostgresqlConnectionsHigh` | connections > 75% of max | 5m | warning |
| 3 | `PostgresqlDeadTuplesHigh` | dead tuples > 20% AND > 10,000 | 10m | warning |
| 4 | `PostgresqlDatabaseSizeLarge` | database > 25 GB | 5m | info |
| 5 | `PostgresqlReplicationLagHigh` | lag > 30 seconds | 5m | warning |
| 6 | `PostgresqlSlowQueries` | mean exec time > 1000ms | 5m | warning |
| 7 | `PostgresqlCacheHitRatioLow` | cache hit ratio < 90% | 10m | warning |

**Inhibition rules** suppress lower severity alerts when a higher severity
alert is already firing for the same alertname. To add these to your existing
Alertmanager config, include the following in your `kube-prometheus-stack` values:

```yaml
alertmanager:
  config:
    inhibit_rules:
      - source_matchers:
          - severity = critical
        target_matchers:
          - severity =~ "warning|info"
        equal: ['alertname']
      - source_matchers:
          - severity = warning
        target_matchers:
          - severity = info
        equal: ['alertname']
```

---

## Grafana Sidecar Requirements

The dashboard and datasource ConfigMaps require the Grafana sidecar
to be enabled in your `kube-prometheus-stack` values.

Check if sidecars are enabled:
```bash
helm get values kube-prometheus-stack -n monitoring | grep -A5 sidecar
```

If not enabled, add to your values and upgrade:
```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: default
    datasources:
      enabled: true
      label: grafana_datasource
      labelValue: "1"
      searchNamespace: default
```

```bash
helm upgrade kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -f your-values.yaml \
  -n monitoring
```

---

## PrometheusRule Label Matching

The `PrometheusRule` CRD uses these labels to be picked up by
the Prometheus Operator:

```yaml
labels:
  app: kube-prometheus-stack
  release: kube-prometheus-stack
```

These must match the `ruleSelector` in your Prometheus spec.
Check your current selector:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A10 ruleSelector
```

If your `ruleSelector` uses different labels, update
`helm/prometheus-rules.yaml` metadata labels to match before applying.

Common alternative label selector example:

```yaml
# If using matchExpressions instead of matchLabels
ruleSelector:
  matchExpressions:
    - key: role
      operator: In
      values: [alert-rules]
```

In that case add `role: alert-rules` to the PrometheusRule labels.

---

## pgBadger: Deployment vs CronJob

Two options are provided — choose based on your preference:

| | Deployment | CronJob |
|---|---|---|
| **When it runs** | Continuously, syncs every hour | On schedule (`0 * * * *`) |
| **Report serving** | Always available on port 8080 | No built-in serving |
| **Resource usage** | Small pod always running | Runs only during job execution |
| **Best for** | Teams wanting always-on access | Teams wanting minimal resource usage |

To use CronJob only (without the always-on Deployment):
```bash
kubectl apply -f pgbadger/service.yaml -n default
kubectl apply -f pgbadger/cronjob.yaml -n default
# Do NOT apply pgbadger/deployment.yaml
```

To trigger a CronJob run immediately without waiting for the schedule:
```bash
kubectl create job pgbadger-manual \
  --from=cronjob/pgbadger-report \
  -n default
kubectl logs -f job/pgbadger-manual -n default
```

---

## Verify Everything is Working

Run this checklist after full deployment:

```bash
# 1. PrometheusRule loaded
kubectl get prometheusrule pg-baseera-rds-alerts -n default
echo "PrometheusRule exists"

# 2. pgBadger pod running
kubectl get pods -l app=pgbadger -n default | grep Running
echo "pgBadger running"

# 3. pgBadger service reachable
kubectl port-forward svc/pgbadger 8080:8080 -n default &
sleep 2
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080
echo " (should be 200)"

# 4. CloudWatch datasource ConfigMap exists
kubectl get configmap grafana-cloudwatch-datasource -n default
echo "CloudWatch datasource ConfigMap exists"

# 5. RDS dashboard ConfigMap exists
kubectl get configmap grafana-rds-postgresql-dashboard -n default
echo "RDS dashboard ConfigMap exists"

# 6. Custom metrics visible (requires postgres-exporter patch applied)
kubectl port-forward svc/prometheus-postgres-exporter 9187:9187 -n default &
sleep 2
curl -s http://localhost:9187/metrics | grep -c "pg_stat_statements_top"
echo " pg_stat_statements metrics (should be > 0)"
```

---

## Troubleshooting

### PrometheusRule not picked up by Prometheus

Check if the labels match the Prometheus `ruleSelector`:
```bash
kubectl describe prometheus -n monitoring | grep -A10 "Rule Selector"
```
Update labels in `helm/prometheus-rules.yaml` to match and re-apply.

---

### Grafana dashboard not appearing

Check sidecar logs:
```bash
kubectl logs -l app.kubernetes.io/name=grafana \
  -c grafana-sc-dashboard -n monitoring | tail -20
```

Ensure the ConfigMap label matches `sidecar.dashboards.label`
in your Helm values (default: `grafana_dashboard: "1"`).

---

### CloudWatch datasource not appearing in Grafana

Check datasource sidecar logs:
```bash
kubectl logs -l app.kubernetes.io/name=grafana \
  -c grafana-sc-datasources -n monitoring | tail -20
```

Ensure `sidecar.datasources.enabled: true` in your Grafana Helm values.

---

### pgBadger report shows no data

The most common cause is `log_min_duration_statement` set too high.
Check the current value on your RDS instance:

```bash
psql "postgresql://user:pass@your-rds-endpoint:5432/main?sslmode=require" \
  -c "SHOW log_min_duration_statement;"
```

On RDS you must update the parameter group via AWS Console or CLI —
`ALTER SYSTEM` is not available on RDS. Update and reboot if required.

---

### pgBadger pod CrashLoopBackOff

Check logs for the specific error:
```bash
kubectl logs deployment/pgbadger -n default --previous
```

Common causes:
- AWS credentials secret not found — verify `aws-cloudwatch-credentials` exists
- CloudWatch log group name incorrect — verify in AWS Console
- Insufficient IAM permissions — verify `logs:GetLogEvents` is allowed

---

## Removing the Package

To cleanly remove everything this package added:

```bash
# Remove alert rules
kubectl delete prometheusrule pg-baseera-rds-alerts -n default

# Remove Grafana dashboard
kubectl delete configmap grafana-rds-postgresql-dashboard -n default

# Remove CloudWatch datasource
kubectl delete configmap grafana-cloudwatch-datasource -n default

# Remove pgBadger
kubectl delete deployment pgbadger -n default
kubectl delete service pgbadger -n default
kubectl delete cronjob pgbadger-report -n default

# Remove AWS credentials secret
kubectl delete secret aws-cloudwatch-credentials -n default

# Rollback postgres-exporter to previous values
helm upgrade prometheus-postgres-exporter \
  prometheus-community/prometheus-postgres-exporter \
  -f your-original-values.yaml \
  -n default
```

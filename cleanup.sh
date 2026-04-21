#!/bin/bash
echo "  This will stop all containers and DELETE all data volumes."
read -p "Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Stopping all containers..."
docker compose --profile pgbench down -v

echo "Removing any leftover volumes..."
docker volume rm pg-monitor_postgres_data pg-monitor_prometheus_data pg-monitor_grafana_data 2>/dev/null || true

echo "Removing pgbadger reports..."
rm -f ~/pg-monitor/pgbadger/reports/*.html

echo "Removing postgres logs..."
sudo rm -f ~/pg-monitor/postgres/logs/*.log

echo "Fixing permissions..."
sudo chmod 777 ~/pg-monitor/postgres/logs
sudo chmod 777 ~/pg-monitor/pgbadger/reports

echo "Done. Run ./start.sh to start fresh."

#!/bin/bash
echo "This will stop all containers and DELETE all data volumes."
read -p "Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi


echo "Stopping all containers..."
docker compose --profile pgbench down -v


echo "Removing any leftover volumes..."
docker volume rm pg-baseera_postgres_data \
                 pg-baseera_prometheus_data \
                 pg-baseera_grafana_data 2>/dev/null || true


echo "Removing pgbadger reports..."
rm -f ./pgbadger/reports/*.html


echo "Removing postgres and RDS logs..."
sudo rm -f ./postgres/logs/*.log 2>/dev/null || \
     rm -f ./postgres/logs/*.log 2>/dev/null || true


echo "Fixing permissions..."
sudo chmod 777 ./postgres/logs ./pgbadger/reports 2>/dev/null || true


echo "Done. Run ./start.sh to start fresh."

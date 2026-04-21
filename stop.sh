#!/bin/bash
echo "Stopping pg-baseera..."
docker compose --profile pgbench down
echo "Done. Data volumes preserved. To wipe everything: docker compose down -v"

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    pgbadger \
    busybox \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /reports /logs

COPY pgbadger/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]

#!/bin/bash
set -e

LOG_DIR="/logs"
REPORT_DIR="/reports"
INTERVAL="${PGBADGER_INTERVAL:-3600}"

echo "pgBadger report generator started."
echo "Log dir   : $LOG_DIR"
echo "Report dir: $REPORT_DIR"
echo "Interval  : ${INTERVAL}s"

# Serve reports using busybox httpd
busybox httpd -f -p 8080 -h "$REPORT_DIR" &

generate_report() {
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
    OUTFILE="$REPORT_DIR/report_${TIMESTAMP}.html"
    LOGFILE="$LOG_DIR/postgresql-$(date +%Y-%m-%d).log"

    if [ ! -f "$LOGFILE" ]; then
        echo "[$(date)] No log file found at $LOGFILE — skipping."
        return
    fi

    echo "[$(date)] Generating report from $LOGFILE..."
    pgbadger \
        --format stderr \
        --prefix '%t [%p]: user=%u,db=%d,app=%a,client=%h ' \
        --outfile "$OUTFILE" \
        "$LOGFILE" && echo "[$(date)] Report saved: $OUTFILE"

    ln -sf "$OUTFILE" "$REPORT_DIR/latest.html"

    # Generate index page listing all reports
    echo "<html><head><title>pgBadger Reports</title>" > "$REPORT_DIR/index.html"
    echo "<style>body{font-family:monospace;background:#0d1117;color:#c9d1d9;padding:2rem;}</style></head><body>" >> "$REPORT_DIR/index.html"
    echo "<h2>🐘 pgBadger Reports</h2><ul>" >> "$REPORT_DIR/index.html"
    for f in "$REPORT_DIR"/report_*.html; do
        fname=$(basename "$f")
        echo "<li><a style='color:#58a6ff' href='/$fname'>$fname</a></li>" >> "$REPORT_DIR/index.html"
    done
    echo "</ul><br><a style='color:#3fb950' href='/latest.html'>→ Latest Report</a></body></html>" >> "$REPORT_DIR/index.html"
}

# Generate once on startup
generate_report

# Regenerate on interval
while true; do
    sleep "$INTERVAL"
    generate_report
done

package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Config

type Config struct {
	LogDir    string
	ReportDir string
	LogPrefix string
	Services  []ServiceConfig
	HTTPPort  string
	ScanEvery time.Duration
}

type ServiceConfig struct {
	Name string
	URL  string
}

func defaultConfig() Config {
	return Config{
		LogDir:    getEnv("LOG_DIR", "./postgres/logs"),
		ReportDir: getEnv("REPORT_DIR", "./pgbadger/reports"),
		LogPrefix: `%t [%p]: user=%u,db=%d,app=%a,client=%h `,
		HTTPPort:  getEnv("MONITOR_PORT", "9999"),
		ScanEvery: 60 * time.Second,
		Services: []ServiceConfig{
			{Name: "Prometheus",        URL: "http://localhost:9090/-/healthy"},
			{Name: "Grafana",           URL: "http://localhost:3000/api/health"},
			{Name: "postgres_exporter", URL: "http://localhost:9187/metrics"},
			{Name: "Node Exporter",     URL: "http://localhost:9100/metrics"},
			{Name: "pgBadger Reports",  URL: "http://localhost:8080"},
		},
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Health checker

type ServiceStatus struct {
	Name      string    `json:"name"`
	URL       string    `json:"url"`
	Healthy   bool      `json:"healthy"`
	Code      int       `json:"status_code"`
	CheckedAt time.Time `json:"checked_at"`
	Error     string    `json:"error,omitempty"`
}

type HealthRegistry struct {
	mu       sync.RWMutex
	statuses []ServiceStatus
}

func (h *HealthRegistry) Check(services []ServiceConfig) {
	client := &http.Client{Timeout: 5 * time.Second}
	results := make([]ServiceStatus, len(services))
	var wg sync.WaitGroup

	for i, svc := range services {
		wg.Add(1)
		go func(idx int, s ServiceConfig) {
			defer wg.Done()
			st := ServiceStatus{Name: s.Name, URL: s.URL, CheckedAt: time.Now()}
			resp, err := client.Get(s.URL)
			if err != nil {
				st.Error = err.Error()
			} else {
				resp.Body.Close()
				st.Code = resp.StatusCode
				st.Healthy = resp.StatusCode < 400
			}
			results[idx] = st
		}(i, svc)
	}
	wg.Wait()

	h.mu.Lock()
	h.statuses = results
	h.mu.Unlock()
}

func (h *HealthRegistry) Get() []ServiceStatus {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.statuses
}

// pgBadger runner

type ReportRecord struct {
	File      string    `json:"file"`
	LogSource string    `json:"log_source"`
	CreatedAt time.Time `json:"created_at"`
	Error     string    `json:"error,omitempty"`
}

type ReportRegistry struct {
	mu      sync.RWMutex
	records []ReportRecord
}

func (r *ReportRegistry) Add(rec ReportRecord) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.records = append([]ReportRecord{rec}, r.records...)
	if len(r.records) > 20 {
		r.records = r.records[:20]
	}
}

func (r *ReportRegistry) Get() []ReportRecord {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.records
}

func runPgBadger(cfg Config, logFile string, reports *ReportRegistry) {
	timestamp := time.Now().Format("2006-01-02_15-04")
	outFile := filepath.Join(cfg.ReportDir, fmt.Sprintf("report_%s.html", timestamp))

	rec := ReportRecord{
		File:      outFile,
		LogSource: logFile,
		CreatedAt: time.Now(),
	}

	log.Printf("[pgbadger] Generating report: %s → %s", logFile, outFile)

	cmd := exec.Command("pgbadger",
		"--format", "stderr",
		"--prefix", cfg.LogPrefix,
		"--outfile", outFile,
		logFile,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		rec.Error = fmt.Sprintf("%v: %s", err, strings.TrimSpace(string(out)))
		log.Printf("[pgbadger] ERROR: %s", rec.Error)
	} else {
		log.Printf("[pgbadger] Report saved: %s", outFile)
		latest := filepath.Join(cfg.ReportDir, "latest.html")
		_ = os.Remove(latest)
		_ = os.Symlink(outFile, latest)
	}
	reports.Add(rec)
}

// Log watcher

func watchLogs(cfg Config, reports *ReportRegistry) {
	seen := map[string]int64{}

	for {
		pattern := filepath.Join(cfg.LogDir, "postgresql-*.log")
		files, _ := filepath.Glob(pattern)

		for _, f := range files {
			info, err := os.Stat(f)
			if err != nil {
				continue
			}
			prev, ok := seen[f]
			if !ok {
				seen[f] = info.Size()
				runPgBadger(cfg, f, reports)
				continue
			}
			if info.Size() > prev {
				seen[f] = info.Size()
				runPgBadger(cfg, f, reports)
			}
		}
		time.Sleep(cfg.ScanEvery)
	}
}

// HTTP status dashboard

const dashboardTmpl = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="30">
<title>pg-monitor</title>
<style>
  *    { box-sizing:border-box; margin:0; padding:0; }
  body { font-family: 'Courier New', monospace; background:#0d1117; color:#c9d1d9; padding:2rem; }
  h1   { color:#58a6ff; font-size:1.4rem; margin-bottom:0.25rem; }
  h2   { color:#58a6ff; font-size:1rem; margin:1.5rem 0 0.5rem; border-bottom:1px solid #21262d; padding-bottom:0.3rem; }
  sub  { color:#484f58; font-size:0.8rem; }
  table{ width:100%; border-collapse:collapse; font-size:0.85rem; }
  th   { background:#161b22; color:#8b949e; padding:0.4rem 0.8rem; text-align:left; font-weight:normal; }
  td   { padding:0.4rem 0.8rem; border-bottom:1px solid #21262d; }
  tr:hover td { background:#161b22; }
  .up  { color:#3fb950; font-weight:bold; }
  .dn  { color:#f85149; font-weight:bold; }
  .ts  { color:#484f58; font-size:0.8em; }
  .err { color:#f85149; font-size:0.8em; }
  ul   { list-style:none; display:flex; gap:1.5rem; flex-wrap:wrap; margin:0.5rem 0; }
  ul a { color:#58a6ff; text-decoration:none; font-size:0.9rem; }
  ul a:hover { text-decoration:underline; }
  .badge-up { background:#1a4a2e; color:#3fb950; padding:0.15rem 0.5rem; border-radius:4px; font-size:0.75rem; }
  .badge-dn { background:#4a1a1a; color:#f85149; padding:0.15rem 0.5rem; border-radius:4px; font-size:0.75rem; }
</style>
</head>
<body>
<h1>🐘 pg-monitor &nbsp;<span class="ts">status dashboard</span></h1>
<sub>Auto-refreshes every 30s &nbsp;·&nbsp; {{ .Now }}</sub>

<h2>Service Health</h2>
<table>
<tr><th>Service</th><th>Status</th><th>HTTP</th><th>Checked</th><th>Detail</th></tr>
{{ range .Statuses }}
<tr>
  <td>{{ .Name }}</td>
  <td>{{ if .Healthy }}<span class="badge-up">● UP</span>{{ else }}<span class="badge-dn">● DOWN</span>{{ end }}</td>
  <td class="ts">{{ if .Code }}{{ .Code }}{{ else }}—{{ end }}</td>
  <td class="ts">{{ .CheckedAt.Format "15:04:05" }}</td>
  <td class="err">{{ .Error }}</td>
</tr>
{{ end }}
</table>

<h2>Quick Links</h2>
<ul>
  <li><a href="http://localhost:3000" target="_blank">📊 Grafana</a></li>
  <li><a href="http://localhost:9090" target="_blank">🔥 Prometheus</a></li>
  <li><a href="http://localhost:9187/metrics" target="_blank">📦 postgres_exporter</a></li>
  <li><a href="http://localhost:9100/metrics" target="_blank">🖥 Node Exporter</a></li>
  <li><a href="http://localhost:8080/latest.html" target="_blank">📄 pgBadger Latest Report</a></li>
</ul>

<h2>pgBadger Reports (last 20)</h2>
<table>
<tr><th>Report</th><th>Log Source</th><th>Generated</th><th>Error</th></tr>
{{ range .Reports }}
<tr>
  <td class="ts">{{ .File }}</td>
  <td class="ts">{{ .LogSource }}</td>
  <td class="ts">{{ .CreatedAt.Format "2006-01-02 15:04:05" }}</td>
  <td class="err">{{ .Error }}</td>
</tr>
{{ end }}
{{ if not .Reports }}<tr><td colspan="4" class="ts">No reports generated yet.</td></tr>{{ end }}
</table>
</body></html>`

type dashboardData struct {
	Now      string
	Statuses []ServiceStatus
	Reports  []ReportRecord
}

func startHTTP(cfg Config, health *HealthRegistry, reports *ReportRegistry) {
	tmpl := template.Must(template.New("dash").Funcs(template.FuncMap{
		"not": func(v interface{}) bool {
			if v == nil {
				return true
			}
			if s, ok := v.([]ReportRecord); ok {
				return len(s) == 0
			}
			return false
		},
	}).Parse(dashboardTmpl))

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		data := dashboardData{
			Now:      time.Now().Format("2006-01-02 15:04:05"),
			Statuses: health.Get(),
			Reports:  reports.Get(),
		}
		w.Header().Set("Content-Type", "text/html")
		if err := tmpl.Execute(w, data); err != nil {
			http.Error(w, err.Error(), 500)
		}
	})

	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(health.Get())
	})

	http.HandleFunc("/api/reports", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(reports.Get())
	})

	addr := ":" + cfg.HTTPPort
	log.Printf("[http] Status dashboard → http://localhost%s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

// Main

func main() {
	cfg := defaultConfig()

	if err := os.MkdirAll(cfg.ReportDir, 0755); err != nil {
		log.Fatalf("Cannot create report dir: %v", err)
	}

	health  := &HealthRegistry{}
	reports := &ReportRegistry{}

	health.Check(cfg.Services)

	go func() {
		for {
			time.Sleep(30 * time.Second)
			health.Check(cfg.Services)
		}
	}()

	go watchLogs(cfg, reports)

	startHTTP(cfg, health, reports)
}

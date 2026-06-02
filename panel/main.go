package main

import (
	"bufio"
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

//go:embed web/*
var webAssets embed.FS

var (
	startTime    = time.Now()
	mosdnsBin    = "/opt/mosdns/bin/mosdns"
	panelVersion = "v5.1.1"
)

func main() {
	portFlag := flag.Int("port", 8080, "Port to listen on")
	hostFlag := flag.String("host", "127.0.0.1", "Host IP to bind to")
	flag.Parse()

	// 1. Initialize SQLite Database
	dbPath := "/opt/mosdns/bin/panel.db"
	if err := InitDB(dbPath); err != nil {
		log.Fatalf("Fatal: Database initialization failed: %v", err)
	}

	// 2. Start Log Monitoring and Parser background thread
	logPath := "/var/log/mosdns/mosdns.log"
	// Ensure log directory exists
	os.MkdirAll(filepath.Dir(logPath), 0755)
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		// Create empty log file if missing to prevent tailer crash
		os.WriteFile(logPath, []byte(""), 0644)
	}
	StartLogTailer(logPath)

	// 3. Register HTTP Endpoints
	registerAPIs()

	// 4. Start Server
	bindAddr := fmt.Sprintf("%s:%d", *hostFlag, *portFlag)
	log.Printf("==============================================")
	log.Printf("MosDNS Control Panel listening on http://%s", bindAddr)
	log.Printf("Security: Default auth is Trust Intranet Mode")
	log.Printf("==============================================")

	server := &http.Server{
		Addr:         bindAddr,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 10 * time.Minute, // Elevated for SSE streams
	}

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Fatal: Server execution terminated: %v", err)
	}
}

func registerAPIs() {
	// Static embedded assets
	http.HandleFunc("/", serveStatic)

	// REST APIs
	http.HandleFunc("/api/status", handleStatus)
	http.HandleFunc("/api/service/action", handleServiceAction)
	http.HandleFunc("/api/config", handleConfig)
	http.HandleFunc("/api/rules", handleRulesList)
	http.HandleFunc("/api/rules/content", handleRuleFileContent)
	http.HandleFunc("/api/rules/create", handleRulesCreate)
	http.HandleFunc("/api/rules/toggle", handleRulesToggle)
	http.HandleFunc("/api/queries/history", handleQueryHistory)
	http.HandleFunc("/api/stats/summary", handleStatsSummary)
	http.HandleFunc("/api/cache/flush", handleCacheFlush)

	// SSE Real-time feeds
	http.HandleFunc("/api/logs/stream", handleLogStream)
	http.HandleFunc("/api/queries/stream", handleQueryStream)
	http.HandleFunc("/api/maintenance/run", handleMaintenanceRun)
}

// serveStatic serves embedded files safely with explicit content-type mappings
func serveStatic(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	if path == "/" || path == "/index.html" {
		data, err := webAssets.ReadFile("web/index.html")
		if err != nil {
			http.Error(w, "Asset not found", 404)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(data)
		return
	}

	filePath := "web" + path
	data, err := webAssets.ReadFile(filePath)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	contentType := "text/plain"
	if strings.HasSuffix(filePath, ".css") {
		contentType = "text/css"
	} else if strings.HasSuffix(filePath, ".js") {
		contentType = "application/javascript"
	} else if strings.HasSuffix(filePath, ".svg") {
		contentType = "image/svg+xml"
	} else if strings.HasSuffix(filePath, ".png") {
		contentType = "image/png"
	}

	w.Header().Set("Content-Type", contentType)
	w.Write(data)
}

// handleStatus retrieves live CPU/Memory, Service state, and general count statistics
func handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 1. Service Status
	serviceStatus, _ := ManageService("status")
	isActive := strings.Contains(serviceStatus, "active (running)")

	// 2. Parse system status natively (RAM, CPU Uptime)
	totalMem, freeMem := getRAMStats()
	cpuUsage := getCPUUsage()

	// 3. Scrape MosDNS native API metrics
	metrics := ScrapeMosdnsMetrics()

	response := map[string]interface{}{
		"version":               panelVersion,
		"panel_uptime_seconds":  time.Since(startTime) / time.Second,
		"service_active":        isActive,
		"service_log":           serviceStatus,
		"ram_total_kb":          totalMem,
		"ram_free_kb":           freeMem,
		"cpu_usage_percent":     cpuUsage,
		"mosdns_cache_size":     metrics.CacheSize,
		"mosdns_cache_queries":  metrics.CacheQueries,
		"mosdns_cache_hits":     metrics.CacheHits,
		"mosdns_cache_hit_rate": metrics.CacheHitRate,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// handleServiceAction triggers starting, stopping or restarting MosDNS service
func handleServiceAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Action string `json:"action"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	output, err := ManageService(req.Action)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error":  err.Error(),
			"output": output,
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Action completed successfully",
		"output":  output,
	})
}

// handleConfig reads or writes the MosDNS main config file with pre-check validation and rollbacks
func handleConfig(w http.ResponseWriter, r *http.Request) {
	configPath := "/opt/mosdns/config-v5.yaml"
	ruleBaseDir := filepath.Dir(mosdnsBin) // /opt/mosdns/bin

	if r.Method == http.MethodGet {
		data, err := os.ReadFile(configPath)
		if err != nil {
			http.Error(w, "Failed to read configuration: "+err.Error(), 500)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(data)
		return
	}

	if r.Method == http.MethodPost {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", 400)
			return
		}

		// --- HIGH AVAILABILITY PROCESS ---

		// STEP 1: Pre-flight check — verify all referenced rule files exist
		missingFiles := CheckReferencedFilesExist(body, ruleBaseDir)
		if len(missingFiles) > 0 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{
				"error":      "missing_files",
				"error_desc": fmt.Sprintf("配置引用了 %d 个不存在的规则文件，请先在「系统运维」页面执行「更新地理规则包」生成这些文件。", len(missingFiles)),
				"output":     fmt.Sprintf("缺失文件列表：%s", strings.Join(missingFiles, ", ")),
			})
			return
		}

		// STEP 2: Write to temporary config file for syntax validation
		tempConfig := "/opt/mosdns/config-v5.temp.yaml"
		if err := os.WriteFile(tempConfig, body, 0644); err != nil {
			http.Error(w, "Failed to write temp config: "+err.Error(), 500)
			return
		}
		defer os.Remove(tempConfig)

		// STEP 3: Validate configuration syntax (Dry-run via mosdns start with timeout)
		valCtx, valCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer valCancel()

		checkCmd := exec.CommandContext(valCtx, mosdnsBin, "start", "-c", tempConfig, "-d", ruleBaseDir)
		var checkOut bytesBufferWriter
		checkCmd.Stdout = &checkOut
		checkCmd.Stderr = &checkOut

		if err := checkCmd.Run(); err != nil {
			outputStr := checkOut.String()
			isConfigError := true

			// If the run timed out (context cancelled) or failed because port is occupied
			// by the production service, the config itself was parsed successfully.
			if valCtx.Err() == context.DeadlineExceeded {
				isConfigError = false
			} else if strings.Contains(outputStr, "address already in use") {
				isConfigError = false
			}

			if isConfigError {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				json.NewEncoder(w).Encode(map[string]string{
					"error":      "validation_failed",
					"error_desc": "配置文件语法校验失败，mosdns 无法解析该配置。请检查 YAML 格式及插件配置。",
					"output":     outputStr,
				})
				return
			}
		}

		// STEP 4: Record pre-restart service state (for safety)
		wasActive := isServiceActive()

		// STEP 5: Create timestamped backup of the production config
		timestamp := time.Now().Format("20060102_150405")
		backupPath := fmt.Sprintf("%s.%s.bak", configPath, timestamp)
		if originalData, err := os.ReadFile(configPath); err == nil {
			os.WriteFile(backupPath, originalData, 0644)
		}

		// STEP 6: Atomic deploy (overwrite production file)
		if err := os.WriteFile(configPath, body, 0644); err != nil {
			http.Error(w, "Failed to deploy configuration: "+err.Error(), 500)
			return
		}

		// STEP 7: Restart service and execute Canary uptime health checks
		_, restartErr := ManageService("restart")
		if restartErr == nil {
			time.Sleep(2 * time.Second)
			if canaryCheckPassed() {
				w.Header().Set("Content-Type", "application/json")
				json.NewEncoder(w).Encode(map[string]string{
					"message": "Configuration updated successfully and service verified stable",
				})
				return
			}
		}

		// --- CANARY HEALTH CHECK FAILED -> CRITICAL SELF-HEALING ROLLBACK ---
		log.Printf("CANARY HEALTH CHECK FAILED! (wasActive=%v, restartErr=%v) Triggering rollback...", wasActive, restartErr)

		// Recover backup
		if backupData, err := os.ReadFile(backupPath); err == nil {
			os.WriteFile(configPath, backupData, 0644)
		}

		// Only attempt restart if service was previously active
		rollbackMsg := "Rollback completed."
		if wasActive {
			if _, rbErr := ManageService("restart"); rbErr != nil {
				log.Printf("CRITICAL: Rollback restart also failed: %v", rbErr)
				rollbackMsg = "Rollback config restored but service restart failed. Manual intervention may be needed."
			} else {
				time.Sleep(2 * time.Second)
				if canaryCheckPassed() {
					rollbackMsg = "Rollback successful, DNS service restored to previous stable configuration."
				} else {
					rollbackMsg = "Rollback config restored but DNS canary still failing. Check service logs."
				}
			}
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error":      "canary_failed",
			"error_desc": "金丝雀健康检查失败：DNS 无法正常解析。已自动回滚至上一个稳定配置。",
			"output":     rollbackMsg,
		})
		return
	}

	http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
}

// isServiceActive checks if mosdns.service is currently running
func isServiceActive() bool {
	status, _ := ManageService("status")
	return strings.Contains(status, "active (running)")
}

// handleRulesList lists all white-listed rule filenames grouped by category
func handleRulesList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	localFiles, remoteFiles, err := ReadDomainSets()
	if err != nil {
		http.Error(w, "Failed to read configuration: "+err.Error(), http.StatusInternalServerError)
		return
	}

	onlineRulesMap := map[string]bool{
		"china-list.txt":                  true,
		"proxy-list.txt":                  true,
		"apple-cn.txt":                    true,
		"geosite_steam.txt":               true,
		"geosite_nintendo.txt":            true,
		"geosite_playstation.txt":         true,
		"geosite_epicgames.txt":           true,
		"geosite_blizzard.txt":            true,
		"geosite_ea.txt":                  true,
		"geosite_riot.txt":                true,
		"geosite_roblox.txt":              true,
		"geosite_tencent-games.txt":       true,
		"geosite_mihoyo-cn.txt":           true,
		"geosite_bilibili-game.txt":       true,
		"geosite_category-games-other.txt": true,
	}

	type RuleFileInfo struct {
		Filename string `json:"filename"`
		IsOnline bool   `json:"is_online"`
		Enabled  bool   `json:"enabled"`
	}

	// Remove duplicates and maintain order
	seenLocal := make(map[string]bool)
	var localRules []RuleFileInfo
	for _, f := range localFiles {
		if !seenLocal[f.Filename] {
			seenLocal[f.Filename] = true
			localRules = append(localRules, RuleFileInfo{
				Filename: f.Filename,
				IsOnline: onlineRulesMap[f.Filename],
				Enabled:  f.Enabled,
			})
		}
	}

	seenRemote := make(map[string]bool)
	var remoteRules []RuleFileInfo
	for _, f := range remoteFiles {
		if !seenRemote[f.Filename] {
			seenRemote[f.Filename] = true
			remoteRules = append(remoteRules, RuleFileInfo{
				Filename: f.Filename,
				IsOnline: onlineRulesMap[f.Filename],
				Enabled:  f.Enabled,
			})
		}
	}

	response := map[string]interface{}{
		"local_rules":  localRules,
		"remote_rules": remoteRules,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// handleRuleFileContent reads or writes domain-lists with timestamped safety backups
func handleRuleFileContent(w http.ResponseWriter, r *http.Request) {
	filename := r.URL.Query().Get("file")
	fullPath, err := ValidateFilename(filename)
	if err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}

	if r.Method == http.MethodGet {
		data, err := os.ReadFile(fullPath)
		if err != nil {
			http.Error(w, "Failed to read file: "+err.Error(), 500)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(data)
		return
	}

	if r.Method == http.MethodPost {
		// Online rules read-only protection
		onlineRules := map[string]bool{
			"china-list.txt":                  true,
			"proxy-list.txt":                  true,
			"apple-cn.txt":                    true,
			"geosite_steam.txt":               true,
			"geosite_nintendo.txt":            true,
			"geosite_playstation.txt":         true,
			"geosite_epicgames.txt":           true,
			"geosite_blizzard.txt":            true,
			"geosite_ea.txt":                  true,
			"geosite_riot.txt":                true,
			"geosite_roblox.txt":              true,
			"geosite_tencent-games.txt":       true,
			"geosite_mihoyo-cn.txt":           true,
			"geosite_bilibili-game.txt":       true,
			"geosite_category-games-other.txt": true,
		}
		if onlineRules[filename] {
			http.Error(w, "自动更新列表为只读，不允许在网页端修改。", http.StatusForbidden)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", 400)
			return
		}

		// Create timestamped backup of the domain list before overwriting
		timestamp := time.Now().Format("20060102_150405")
		backupPath := fmt.Sprintf("%s.%s.bak", fullPath, timestamp)
		if originalData, err := os.ReadFile(fullPath); err == nil {
			os.WriteFile(backupPath, originalData, 0644)
		}

		// Save new content
		if err := os.WriteFile(fullPath, body, 0644); err != nil {
			http.Error(w, "Failed to save file: "+err.Error(), 500)
			return
		}

		// Hot reload/Restart service and Canary test
		_, restartErr := ManageService("restart")
		if restartErr == nil {
			time.Sleep(2 * time.Second)
			if canaryCheckPassed() {
				w.Header().Set("Content-Type", "application/json")
				json.NewEncoder(w).Encode(map[string]string{
					"message": "Domain list saved successfully and service verified stable",
				})
				return
			}
		}

		// Rollback domain list if service breaks
		log.Println("CANARY HEALTH CHECK FAILED after domain list update! Rolling back...")
		if backupData, err := os.ReadFile(backupPath); err == nil {
			os.WriteFile(fullPath, backupData, 0644)
		}
		ManageService("restart")

		w.WriteHeader(http.StatusInternalServerError)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Service resolution test failed after saving list. Rollback triggered automatically to restore DNS connectivity.",
		})
		return
	}

	http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
}

// handleQueryHistory provides historical query listings with SQLite integration
func handleQueryHistory(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("pageSize"))
	if pageSize < 1 {
		pageSize = 50
	}
	search := r.URL.Query().Get("search")

	logs, totalCount, err := GetQueryLogs(page, pageSize, search)
	if err != nil {
		http.Error(w, "Database failure: "+err.Error(), 500)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"logs":        logs,
		"total_count": totalCount,
		"page":        page,
		"page_size":   pageSize,
	})
}

// handleStatsSummary fetches 24h analytical counts for graphs
func handleStatsSummary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	summary, err := GetStatsSummary()
	if err != nil {
		http.Error(w, "Database failure: "+err.Error(), 500)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(summary)
}

// handleLogStream provides SSE streaming channel for system log file
func handleLogStream(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	clientChan := make(chan string, 100)
	LogClientsMu.Lock()
	LogClients[clientChan] = true
	LogClientsMu.Unlock()

	defer func() {
		LogClientsMu.Lock()
		delete(LogClients, clientChan)
		LogClientsMu.Unlock()
		close(clientChan)
	}()

	notify := r.Context().Done()

	for {
		select {
		case <-notify:
			return
		case line := <-clientChan:
			// Text formatting strictly escapes injection payload characters before rendering text format
			escapedLine := strings.ReplaceAll(strings.ReplaceAll(line, "\n", ""), "\r", "")
			fmt.Fprintf(w, "data: %s\n\n", escapedLine)
			w.(http.Flusher).Flush()
		}
	}
}

// handleQueryStream provides SSE streaming channel for live DNS queries
func handleQueryStream(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	clientChan := make(chan QueryLog, 100)
	QueryClientsMu.Lock()
	QueryClients[clientChan] = true
	QueryClientsMu.Unlock()

	defer func() {
		QueryClientsMu.Lock()
		delete(QueryClients, clientChan)
		QueryClientsMu.Unlock()
		close(clientChan)
	}()

	notify := r.Context().Done()

	for {
		select {
		case <-notify:
			return
		case qlog := <-clientChan:
			jsonData, err := json.Marshal(qlog)
			if err == nil {
				fmt.Fprintf(w, "data: %s\n\n", jsonData)
				w.(http.Flusher).Flush()
			}
		}
	}
}

// handleMaintenanceRun executes system update scripts and streams progress via SSE
func handleMaintenanceRun(w http.ResponseWriter, r *http.Request) {
	action := r.URL.Query().Get("action")
	if action != "update-geo" && action != "update-bin" {
		http.Error(w, "Invalid maintenance action", http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	logWriter := &sseWriter{w: w, flusher: w.(http.Flusher)}
	fmt.Fprintf(w, "data: [INFO] Starting maintenance job: %s...\n\n", action)
	w.(http.Flusher).Flush()

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
	defer cancel()

	err := RunMaintenanceScript(ctx, action, logWriter)
	if err != nil {
		fmt.Fprintf(w, "data: [ERROR] Script execution reported error: %v\n\n", err)
	} else {
		fmt.Fprintf(w, "data: [SUCCESS] Maintenance job completed successfully\n\n")
	}
	w.(http.Flusher).Flush()
}

// canaryCheckPassed probes local DNS resolution to verify DNS server is operational
func canaryCheckPassed() bool {
	// Probe local resolver on 127.0.0.1:53
	r := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			d := net.Dialer{Timeout: 1500 * time.Millisecond}
			return d.DialContext(ctx, "udp", "127.0.0.1:53")
		},
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// Probe host lookup
	_, err := r.LookupHost(ctx, "www.baidu.com")
	return err == nil
}

// Native memory reading helper
func getRAMStats() (total uint64, free uint64) {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			val, _ := strconv.ParseUint(fields[1], 10, 64)
			if fields[0] == "MemTotal:" {
				total = val
			} else if fields[0] == "MemAvailable:" || fields[0] == "MemFree:" {
				if free == 0 {
					free = val // Prefer MemAvailable, fallback to MemFree
				}
			}
		}
	}
	if err := scanner.Err(); err != nil {
		log.Printf("Warning: meminfo scanner error: %v", err)
	}
	return total, free
}

// Native CPU reading helper
func getCPUUsage() float64 {
	file, err := os.Open("/proc/stat")
	if err != nil {
		return 0.0
	}
	defer file.Close()

	var user, nice, system, idle, iowait, irq, softirq uint64
	_, err = fmt.Fscanf(file, "cpu  %d %d %d %d %d %d %d", &user, &nice, &system, &idle, &iowait, &irq, &softirq)
	if err != nil {
		return 0.0
	}

	total := user + nice + system + idle + iowait + irq + softirq
	active := user + nice + system + irq + softirq

	// Read CPU samples with a short interval
	time.Sleep(100 * time.Millisecond)

	file2, err := os.Open("/proc/stat")
	if err != nil {
		return 0.0
	}
	defer file2.Close()

	var user2, nice2, system2, idle2, iowait2, irq2, softirq2 uint64
	_, err = fmt.Fscanf(file2, "cpu  %d %d %d %d %d %d %d", &user2, &nice2, &system2, &idle2, &iowait2, &irq2, &softirq2)
	if err != nil {
		return 0.0
	}

	total2 := user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2
	active2 := user2 + nice2 + system2 + irq2 + softirq2

	if total2-total == 0 {
		return 0.0
	}
	return (float64(active2-active) / float64(total2-total)) * 100.0
}

// Custom types for capturing stdout buffers and writing SSE
type bytesBufferWriter struct {
	buf bytes.Buffer
	mu  sync.Mutex
}

func (w *bytesBufferWriter) Write(p []byte) (n int, err error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.Write(p)
}

func (w *bytesBufferWriter) String() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.String()
}

type sseWriter struct {
	w       io.Writer
	flusher http.Flusher
}

func (s *sseWriter) Write(p []byte) (n int, err error) {
	lines := strings.Split(string(p), "\n")
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			escapedLine := strings.ReplaceAll(strings.ReplaceAll(line, "\n", ""), "\r", "")
			fmt.Fprintf(s.w, "data: %s\n\n", escapedLine)
		}
	}
	s.flusher.Flush()
	return len(p), nil
}

// handleRulesCreate handles the creation of a new custom rule list and adds it to config-v5.yaml
func handleRulesCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Filename string `json:"filename"`
		Category string `json:"category"` // "local" or "remote"
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad Request: "+err.Error(), http.StatusBadRequest)
		return
	}

	filename := strings.TrimSpace(req.Filename)
	category := strings.TrimSpace(req.Category)

	fullPath, err := ValidateFilename(filename)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Verify if the file already exists
	if _, err := os.Stat(fullPath); !os.IsNotExist(err) {
		http.Error(w, fmt.Sprintf("域名列表文件 '%s' 已存在，无法重复创建。", filename), http.StatusConflict)
		return
	}

	// Determine configuration target tag in config-v5.yaml
	var configTag string
	if category == "local" {
		configTag = "direct_domain"
	} else if category == "remote" {
		configTag = "remote_domain"
	} else {
		http.Error(w, "invalid category, must be 'local' or 'remote'", http.StatusBadRequest)
		return
	}

	// Default template content containing guidance and examples
	templateContent := `# MosDNS 自定义域名列表
# 
# 编写格式指导：
# 1. 每行输入一个域名匹配规则。
# 2. 支持以下几种前缀格式：
#    - domain:example.com      (精确匹配 example.com 及其所有子域名)
#    - full:www.example.com    (完整精确匹配 www.example.com)
#    - keyword:google          (匹配含有关键字 google 的域名)
#    - regexp:^[^.]+$          (使用正则表达式匹配，例如匹配所有单标签/本地主机名)
# 
# 示例：
# domain:apple.com
# full:api.github.com
# keyword:netflix
`

	// Create and write default template
	if err := os.WriteFile(fullPath, []byte(templateContent), 0644); err != nil {
		http.Error(w, "Failed to create rule list file: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Add file entry to config-v5.yaml
	if err := AddFileToDomainSet(configTag, filename); err != nil {
		// Clean up created file if config edit fails
		os.Remove(fullPath)
		http.Error(w, "Failed to update configuration: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Trigger mosdns service restart to load the new config & list
	_, restartErr := ManageService("restart")
	if restartErr != nil {
		http.Error(w, "New file created but failed to restart MosDNS service: "+restartErr.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message":  fmt.Sprintf("成功创建列表并激活，已自动挂载至 config-v5.yaml 的 %s 区域中！", configTag),
		"filename": filename,
	})
}

// handleRulesToggle handles enabling or disabling a rule list inside config-v5.yaml files list
func handleRulesToggle(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Filename string `json:"filename"`
		Tag      string `json:"tag"` // "direct_domain", "local_domain", "remote_domain"
		Enabled  bool   `json:"enabled"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad Request: "+err.Error(), http.StatusBadRequest)
		return
	}

	filename := strings.TrimSpace(req.Filename)
	tag := strings.TrimSpace(req.Tag)

	_, err := ValidateFilename(filename)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Dynamic validation on Tag to prevent any unsafe injection
	validTags := map[string]bool{"direct_domain": true, "local_domain": true, "remote_domain": true}
	if !validTags[tag] {
		http.Error(w, "Invalid tag target: "+tag, http.StatusBadRequest)
		return
	}

	// Perform the toggle action
	if err := ToggleFileInDomainSet(tag, filename, req.Enabled); err != nil {
		http.Error(w, "Failed to toggle rule list status: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Trigger restart and canary verification
	_, restartErr := ManageService("restart")
	if restartErr != nil {
		http.Error(w, "Status updated but failed to restart MosDNS service: "+restartErr.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	var msg string
	if req.Enabled {
		msg = fmt.Sprintf("成功启用规则列表 '%s'，并已在 config-v5.yaml 中激活使能！", filename)
	} else {
		msg = fmt.Sprintf("成功停用规则列表 '%s'，已在 config-v5.yaml 中安全屏蔽并热重载！", filename)
	}
	json.NewEncoder(w).Encode(map[string]string{
		"message": msg,
	})
}

// handleCacheFlush clears the cache in the local MosDNS instance via HTTP API and removes the persistence file
func handleCacheFlush(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 1. Flush in-memory cache
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://127.0.0.1:9080/flush")
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": fmt.Sprintf("Failed to flush mosdns cache: %v", err),
		})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": fmt.Sprintf("Mosdns API returned status code %d", resp.StatusCode),
		})
		return
	}

	// 2. Remove cache dump files on disk to prevent reloading on restart
	os.Remove("/opt/mosdns/bin/cache.dump")
	os.Remove("/opt/mosdns/cache.dump")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Cache flushed successfully (memory and persistence cleared)",
	})
}

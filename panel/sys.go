package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Active SSE logging channels
var (
	LogClients    = make(map[chan string]bool)
	LogClientsMu  sync.Mutex
	QueryClients  = make(map[chan QueryLog]bool)
	QueryClientsMu sync.Mutex
)

// Hardcoded safe white-listed file basenames to prevent arbitrary path traversal
var allowedFiles = map[string]string{
	"config-v5.yaml":                "/opt/mosdns/config-v5.yaml",
	"china-list.txt":                "/opt/mosdns/bin/china-list.txt",
	"proxy-list.txt":                "/opt/mosdns/bin/proxy-list.txt",
	"apple-cn.txt":                  "/opt/mosdns/bin/apple-cn.txt",
	"local-domain.txt":              "/opt/mosdns/bin/local-domain.txt",
	"direct-domain.txt":             "/opt/mosdns/bin/direct-domain.txt",
	"geosite_category-games@cn.txt": "/opt/mosdns/bin/geosite_category-games@cn.txt",
}

// Regex for parsing MosDNS query summary logs:
// e.g. "2026-05-23T09:37:54+08:00 [info] query_summary [cache_hit] qname: www.baidu.com. qtype: 1 ..."
// or "info summary: qname: www.baidu.com. qtype: 1 ... [cache_hit]"
var qnameRegex = regexp.MustCompile(`qname:\s*([^\s]+)`)
var qtypeRegex = regexp.MustCompile(`qtype:\s*([^\s]+)`)
var tagRegex = regexp.MustCompile(`\[([a-zA-Z0-9_]+_hit|[a-zA-Z0-9_]+_trial|[a-zA-Z0-9_]+_resilient|[a-zA-Z0-9_]+_final_resilient)\]`)

// ValidateFilename checks if a filename is strictly white-listed to prevent path traversal
func ValidateFilename(filename string) (string, error) {
	cleanName := filepath.Base(filename)
	fullPath, exists := allowedFiles[cleanName]
	if !exists {
		return "", fmt.Errorf("access denied: file '%s' is not in the allowed list", filename)
	}
	return fullPath, nil
}

// ManageService executes standard systemctl commands safely using strict args
func ManageService(action string) (string, error) {
	validActions := map[string]bool{"start": true, "stop": true, "restart": true, "status": true}
	if !validActions[action] {
		return "", fmt.Errorf("invalid service action: %s", action)
	}

	// Parameters are strictly bounded, preventing system execution sinks exploit
	cmd := exec.Command("/bin/systemctl", action, "mosdns.service")
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	err := cmd.Run()
	return out.String(), err
}

// RunMaintenanceScript executes geo rule update or program binary upgrade safely
func RunMaintenanceScript(ctx context.Context, action string, writer io.Writer) error {
	var scriptPath string
	switch action {
	case "update-geo":
		scriptPath = "/opt/mosdns/update-geo.sh"
	case "update-bin":
		scriptPath = "/opt/mosdns/update-bin.sh"
	default:
		return fmt.Errorf("unsupported maintenance action: %s", action)
	}

	if _, err := os.Stat(scriptPath); err != nil {
		return fmt.Errorf("script not found: %s", scriptPath)
	}

	// Execute via bash securely
	cmd := exec.CommandContext(ctx, "/bin/bash", scriptPath)
	cmd.Stdout = writer
	cmd.Stderr = writer

	return cmd.Run()
}

// StartLogTailer runs in a background goroutine, streaming logs in real time
// and parsing query records to write into the SQLite database.
func StartLogTailer(logPath string) {
	go func() {
		for {
			err := tailLogFile(logPath)
			if err != nil {
				log.Printf("Log tailer error: %v. Re-attempting in 5 seconds...", err)
				time.Sleep(5 * time.Second)
			}
		}
	}()
}

func tailLogFile(logPath string) error {
	file, err := os.Open(logPath)
	if err != nil {
		return fmt.Errorf("failed to open log file: %w", err)
	}
	defer file.Close()

	// Seek to end of file initially to capture new logs only
	stat, err := file.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat file: %w", err)
	}
	inode := getInode(stat)
	fileSize := stat.Size()

	_, err = file.Seek(0, io.SeekEnd)
	if err != nil {
		return fmt.Errorf("failed to seek: %w", err)
	}

	reader := bufio.NewReader(file)
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	log.Printf("Monitoring log file %s (inode: %d)", logPath, inode)

	for {
		line, err := reader.ReadString('\n')
		if err == nil {
			line = strings.TrimSpace(line)
			if line != "" {
				// Broadcast raw log to dashboard SSE connections
				broadcastLog(line)

				// Parse DNS query if match JSON summary patterns
				if strings.Contains(line, "\"uqid\"") && strings.Contains(line, "\"qname\"") {
					parseAndSaveQuery(line)
				}
			}
			continue
		}

		if err == io.EOF {
			// Check for log rotation (copytruncate or rename rotation)
			select {
			case <-ticker.C:
				currentStat, err := os.Stat(logPath)
				if err != nil {
					// File might be briefly deleted during rotation
					return err
				}

				// If file size shrank or inode changed, log rotation has occurred
				currentInode := getInode(currentStat)
				if currentStat.Size() < fileSize || currentInode != inode {
					log.Println("Log rotation detected, reloading tailer...")
					return nil
				}
				fileSize = currentStat.Size()
			}
			continue
		}

		return err
	}
}

// Helper to extract Unix inode
func getInode(stat os.FileInfo) uint64 {
	if stat == nil {
		return 0
	}
	if sys, ok := stat.Sys().(*syscall.Stat_t); ok {
		return sys.Ino
	}
	return 0
}

type mosdnsLogJSON struct {
	Uqid    int    `json:"uqid"`
	Client  string `json:"client"`
	Qname   string `json:"qname"`
	Qtype   int    `json:"qtype"`
	Rcode   int    `json:"rcode"`
	Elapsed string `json:"elapsed"`
}

// Parse DNS log line and save to SQLite database
func parseAndSaveQuery(line string) {
	// 1. Find the JSON block starting with { and ending with }
	startIdx := strings.Index(line, "{")
	endIdx := strings.LastIndex(line, "}")
	if startIdx == -1 || endIdx == -1 || endIdx <= startIdx {
		return
	}
	jsonStr := line[startIdx : endIdx+1]

	var logData mosdnsLogJSON
	if err := json.Unmarshal([]byte(jsonStr), &logData); err != nil {
		return
	}

	domain := strings.TrimSuffix(logData.Qname, ".") // Strip trailing dns dot
	if domain == "" {
		return
	}

	qtype := mapQType(logData.Qtype)

	// 2. Extract tag from the line before JSON
	tag := "[unknown]"
	tagMatch := tagRegex.FindStringSubmatch(line)
	if len(tagMatch) >= 2 {
		tag = "[" + tagMatch[1] + "]"
	} else if strings.Contains(line, "[cache_hit]") {
		tag = "[cache_hit]"
	} else if strings.Contains(line, "[router_hit]") {
		tag = "[router_hit]"
	} else if strings.Contains(line, "[local_hit]") {
		tag = "[local_hit]"
	} else if strings.Contains(line, "[remote_hit_resilient]") {
		tag = "[remote_hit_resilient]"
	} else if strings.Contains(line, "[fallback_cn_hit]") {
		tag = "[fallback_cn_hit]"
	} else if strings.Contains(line, "[fallback_remote_trial]") {
		tag = "[fallback_remote_trial]"
	} else if strings.Contains(line, "[fallback_remote_final_resilient]") {
		tag = "[fallback_remote_final_resilient]"
	}

	// 3. Map upstream and parse latency
	upstream := "Local DNS"
	durationMs := 0

	if strings.HasSuffix(logData.Elapsed, "ms") {
		valStr := strings.TrimSuffix(logData.Elapsed, "ms")
		val, _ := strconv.ParseFloat(valStr, 64)
		durationMs = int(val)
	} else if strings.HasSuffix(logData.Elapsed, "µs") {
		valStr := strings.TrimSuffix(logData.Elapsed, "µs")
		val, _ := strconv.ParseFloat(valStr, 64)
		durationMs = int(val / 1000.0)
	} else if strings.HasSuffix(logData.Elapsed, "s") && !strings.HasSuffix(logData.Elapsed, "ns") {
		valStr := strings.TrimSuffix(logData.Elapsed, "s")
		val, _ := strconv.ParseFloat(valStr, 64)
		durationMs = int(val * 1000)
	}

	switch tag {
	case "[cache_hit]":
		upstream = "Local Cache"
	case "[router_hit]":
		upstream = "192.168.4.1 (MikroTik)"
	case "[local_hit]", "[fallback_cn_hit]":
		upstream = "China DNS (119.29.29.29/223.5.5.5)"
	case "[remote_hit_resilient]", "[fallback_remote_final_resilient]", "[fallback_remote_trial]":
		upstream = "Secure DoT (8.8.8.8:853)"
	default:
		upstream = "Default Gateway"
	}

	clientIP := logData.Client
	if strings.HasPrefix(clientIP, "::ffff:") {
		clientIP = strings.TrimPrefix(clientIP, "::ffff:")
	}

	// Save to SQLite
	err := InsertLog(clientIP, domain, qtype, tag, durationMs, upstream)
	if err != nil {
		log.Printf("Failed to record query to database: %v", err)
		return
	}

	// Broadcast parsed QueryLog to listening SSE clients
	broadcastQuery(QueryLog{
		Time:       time.Now().Format("2006-01-02 15:04:05"),
		ClientIP:   clientIP,
		Domain:     domain,
		QType:      qtype,
		Status:     tag,
		DurationMs: durationMs,
		Upstream:   upstream,
	})
}

// Convert DNS QType Int to string Representation
func mapQType(code int) string {
	types := map[int]string{
		1:   "A",
		2:   "NS",
		5:   "CNAME",
		6:   "SOA",
		12:  "PTR",
		15:  "MX",
		16:  "TXT",
		28:  "AAAA",
		33:  "SRV",
		41:  "OPT",
		255: "ANY",
	}
	if name, ok := types[code]; ok {
		return name
	}
	return strconv.Itoa(code)
}

// SSE system log broadcast
func broadcastLog(line string) {
	LogClientsMu.Lock()
	defer LogClientsMu.Unlock()
	for clientChan := range LogClients {
		// Non-blocking select to prevent slow client block
		select {
		case clientChan <- line:
		default:
		}
	}
}

// SSE query events broadcast
func broadcastQuery(q QueryLog) {
	QueryClientsMu.Lock()
	defer QueryClientsMu.Unlock()
	for clientChan := range QueryClients {
		select {
		case clientChan <- q:
		default:
		}
	}
}

type MosdnsMetrics struct {
	CacheSize    int     `json:"mosdns_cache_size"`
	CacheQueries int     `json:"mosdns_cache_queries"`
	CacheHits    int     `json:"mosdns_cache_hits"`
	CacheHitRate float64 `json:"mosdns_cache_hit_rate"`
}

// ScrapeMosdnsMetrics scrapes Prometheus metrics from the local MosDNS API server
func ScrapeMosdnsMetrics() MosdnsMetrics {
	var m MosdnsMetrics
	// Set default safe client with timeout to prevent block
	client := &http.Client{Timeout: 1 * time.Second}
	resp, err := client.Get("http://127.0.0.1:9080/metrics")
	if err != nil {
		return m
	}
	defer resp.Body.Close()

	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		name := fields[0]
		valStr := fields[1]
		val, err := strconv.ParseFloat(valStr, 64)
		if err != nil {
			continue
		}

		cleanName := name
		if idx := strings.Index(name, "{"); idx != -1 {
			cleanName = name[:idx]
		}

		switch cleanName {
		case "mosdns_cache_size_current":
			m.CacheSize = int(val)
		case "mosdns_cache_query_total":
			m.CacheQueries = int(val)
		case "mosdns_cache_hit_total":
			m.CacheHits = int(val)
		}
	}

	if m.CacheQueries > 0 {
		m.CacheHitRate = (float64(m.CacheHits) / float64(m.CacheQueries)) * 100.0
	}
	return m
}

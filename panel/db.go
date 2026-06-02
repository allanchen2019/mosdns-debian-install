package main

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// Global DB instance
var DB *sql.DB

type QueryLog struct {
	ID         int64  `json:"id"`
	Time       string `json:"time"`
	ClientIP   string `json:"client_ip"`
	Domain     string `json:"domain"`
	QType      string `json:"qtype"`
	Status     string `json:"status"`
	DurationMs int    `json:"duration_ms"`
	Upstream   string `json:"upstream"`
}

type DomainStat struct {
	Domain string `json:"domain"`
	Count  int    `json:"count"`
}

type StatusStat struct {
	Status string `json:"status"`
	Count  int    `json:"count"`
}

type HourlyStat struct {
	Hour  string `json:"hour"`
	Count int    `json:"count"`
}

type StatsSummary struct {
	TotalQueries int          `json:"total_queries"`
	AvgDuration  float64      `json:"avg_duration_ms"`
	CacheHitRate float64      `json:"cache_hit_rate"`
	TopDomains   []DomainStat `json:"top_domains"`
	StatusDist   []StatusStat `json:"status_dist"`
	HourlyVolume []HourlyStat `json:"hourly_volume"`
}

// InitDB initializes the SQLite database, configures WAL mode, and creates the required tables and indexes.
func InitDB(dbPath string) error {
	var err error
	DB, err = sql.Open("sqlite3", dbPath)
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}

	// Optimize SQLite performance for homelab environments (WAL mode reduces write-locks and SSD wear)
	pragmas := []string{
		"PRAGMA journal_mode=WAL;",
		"PRAGMA synchronous=NORMAL;",
		"PRAGMA busy_timeout=5000;",
	}
	for _, pragma := range pragmas {
		if _, err := DB.Exec(pragma); err != nil {
			return fmt.Errorf("failed to execute pragma (%s): %w", pragma, err)
		}
	}

	// Create tables & indices
	createTableQuery := `
	CREATE TABLE IF NOT EXISTS query_logs (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		time DATETIME DEFAULT CURRENT_TIMESTAMP,
		client_ip TEXT,
		domain TEXT,
		qtype TEXT,
		status TEXT,
		duration_ms INTEGER,
		upstream TEXT
	);
	CREATE INDEX IF NOT EXISTS idx_query_time ON query_logs(time);
	CREATE INDEX IF NOT EXISTS idx_query_domain ON query_logs(domain);
	`
	if _, err := DB.Exec(createTableQuery); err != nil {
		return fmt.Errorf("failed to create tables: %w", err)
	}

	log.Println("SQLite database initialized successfully at:", dbPath)
	return nil
}

// InsertLog securely inserts a query log record using prepared statements to prevent SQL injection.
func InsertLog(clientIP, domain, qtype, status string, durationMs int, upstream string) error {
	if DB == nil {
		return fmt.Errorf("database is not initialized")
	}

	query := `INSERT INTO query_logs (client_ip, domain, qtype, status, duration_ms, upstream) VALUES (?, ?, ?, ?, ?, ?)`
	_, err := DB.Exec(query, clientIP, domain, qtype, status, durationMs, upstream)
	if err != nil {
		return fmt.Errorf("failed to insert query log: %w", err)
	}
	return nil
}

// GetQueryLogs retrieves a paginated and filtered list of query logs.
func GetQueryLogs(page, pageSize int, search string) ([]QueryLog, int, error) {
	if DB == nil {
		return nil, 0, fmt.Errorf("database is not initialized")
	}

	offset := (page - 1) * pageSize
	var logs []QueryLog
	var totalCount int

	// 1. Get Total Count
	countQuery := `SELECT COUNT(*) FROM query_logs`
	var countErr error
	var row *sql.Row

	if search != "" {
		countQuery += ` WHERE domain LIKE ? OR client_ip LIKE ? OR status LIKE ?`
		searchParam := "%" + search + "%"
		row = DB.QueryRow(countQuery, searchParam, searchParam, searchParam)
	} else {
		row = DB.QueryRow(countQuery)
	}
	if countErr = row.Scan(&totalCount); countErr != nil {
		return nil, 0, fmt.Errorf("failed to scan total count: %w", countErr)
	}

	// 2. Get Paginated Records
	selectQuery := `SELECT id, strftime('%Y-%m-%d %H:%M:%S', time, 'localtime'), client_ip, domain, qtype, status, duration_ms, upstream FROM query_logs`
	var rows *sql.Rows
	var err error

	if search != "" {
		selectQuery += ` WHERE domain LIKE ? OR client_ip LIKE ? OR status LIKE ? ORDER BY id DESC LIMIT ? OFFSET ?`
		searchParam := "%" + search + "%"
		rows, err = DB.Query(selectQuery, searchParam, searchParam, searchParam, pageSize, offset)
	} else {
		selectQuery += ` ORDER BY id DESC LIMIT ? OFFSET ?`
		rows, err = DB.Query(selectQuery, pageSize, offset)
	}

	if err != nil {
		return nil, 0, fmt.Errorf("failed to query records: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var q QueryLog
		err := rows.Scan(&q.ID, &q.Time, &q.ClientIP, &q.Domain, &q.QType, &q.Status, &q.DurationMs, &q.Upstream)
		if err != nil {
			return nil, 0, fmt.Errorf("failed to scan record row: %w", err)
		}
		logs = append(logs, q)
	}

	return logs, totalCount, nil
}

// GetStatsSummary aggregates data from the last 24 hours to generate dashboard metrics.
func GetStatsSummary() (StatsSummary, error) {
	var summary StatsSummary
	if DB == nil {
		return summary, fmt.Errorf("database is not initialized")
	}

	// Time anchor for 24 hours ago
	timeThreshold := time.Now().Add(-24 * time.Hour).Format("2006-01-02 15:04:05")

	// 1. Total queries & Average duration in last 24h
	summaryQuery := `
		SELECT COUNT(*), COALESCE(AVG(duration_ms), 0.0)
		FROM query_logs 
		WHERE time >= ?`
	err := DB.QueryRow(summaryQuery, timeThreshold).Scan(&summary.TotalQueries, &summary.AvgDuration)
	if err != nil {
		return summary, fmt.Errorf("failed to calculate general summary: %w", err)
	}

	if summary.TotalQueries == 0 {
		// Return empty summary gracefully if no records exist in last 24 hours
		summary.TopDomains = []DomainStat{}
		summary.StatusDist = []StatusStat{}
		summary.HourlyVolume = []HourlyStat{}
		return summary, nil
	}

	// 2. Cache Hit Rate calculation
	var cacheHits int
	cacheQuery := `SELECT COUNT(*) FROM query_logs WHERE time >= ? AND status = '[cache_hit]'`
	err = DB.QueryRow(cacheQuery, timeThreshold).Scan(&cacheHits)
	if err != nil {
		return summary, fmt.Errorf("failed to calculate cache hits: %w", err)
	}
	summary.CacheHitRate = (float64(cacheHits) / float64(summary.TotalQueries)) * 100.0

	// 3. Top 10 queried domains
	topDomainsQuery := `
		SELECT domain, COUNT(*) as c 
		FROM query_logs 
		WHERE time >= ? 
		GROUP BY domain 
		ORDER BY c DESC 
		LIMIT 10`
	rows, err := DB.Query(topDomainsQuery, timeThreshold)
	if err != nil {
		return summary, fmt.Errorf("failed to query top domains: %w", err)
	}
	defer rows.Close()

	summary.TopDomains = []DomainStat{}
	for rows.Next() {
		var ds DomainStat
		if err := rows.Scan(&ds.Domain, &ds.Count); err == nil {
			summary.TopDomains = append(summary.TopDomains, ds)
		}
	}

	// 4. Status Distribution
	statusDistQuery := `
		SELECT status, COUNT(*) as c 
		FROM query_logs 
		WHERE time >= ? 
		GROUP BY status 
		ORDER BY c DESC`
	rows2, err := DB.Query(statusDistQuery, timeThreshold)
	if err != nil {
		return summary, fmt.Errorf("failed to query status distribution: %w", err)
	}
	defer rows2.Close()

	summary.StatusDist = []StatusStat{}
	for rows2.Next() {
		var ss StatusStat
		if err := rows2.Scan(&ss.Status, &ss.Count); err == nil {
			summary.StatusDist = append(summary.StatusDist, ss)
		}
	}

	// 5. Hourly Volume for trend charts
	hourlyQuery := `
		SELECT strftime('%H:00', time, 'localtime') as hr, COUNT(*) as c
		FROM query_logs
		WHERE time >= ?
		GROUP BY hr
		ORDER BY time(time) ASC`
	rows3, err := DB.Query(hourlyQuery, timeThreshold)
	if err != nil {
		return summary, fmt.Errorf("failed to query hourly volume: %w", err)
	}
	defer rows3.Close()

	summary.HourlyVolume = []HourlyStat{}
	for rows3.Next() {
		var hs HourlyStat
		if err := rows3.Scan(&hs.Hour, &hs.Count); err == nil {
			summary.HourlyVolume = append(summary.HourlyVolume, hs)
		}
	}

	return summary, nil
}

// ClearQueryLogs truncates the query_logs table to reset dashboard statistics.
func ClearQueryLogs() error {
	if DB == nil {
		return fmt.Errorf("database is not initialized")
	}
	_, err := DB.Exec("DELETE FROM query_logs")
	if err != nil {
		return fmt.Errorf("failed to clear query logs: %w", err)
	}
	// Run vacuum to reclaim space
	_, _ = DB.Exec("VACUUM")
	return nil
}

/* ----------------------------------------------------
   MosDNS Premium JS System (100% XSS-Safe Vanilla SPA)
   ---------------------------------------------------- */

// Application state
const state = {
    currentTab: 'dashboard',
    pingInterval: null,
    statsInterval: null,
    logSse: null,
    querySse: null,
    
    // Audit Pagination
    auditPage: 1,
    auditPageSize: 50,
    auditSearch: '',
    
    // Rules Selection
    selectedRuleFile: '',
    
    // Console State
    consoleMode: 'maint' // 'maint' or 'sys'
};

document.addEventListener('DOMContentLoaded', () => {
    initApp();
});

function initApp() {
    // 1. Tab switches
    setupTabSwitching();

    // 2. Initial state sync and start pollers
    syncStatus();
    syncStats();
    state.pingInterval = setInterval(syncStatus, 3000);
    state.statsInterval = setInterval(syncStats, 10000);

    // 3. Quick action buttons
    setupServiceActions();

    // 4. Config Editor actions
    setupConfigEditor();

    // 5. Rules Manager selectors
    setupRulesManager();

    // 6. Audit / Query History paginators
    setupAuditPagination();

    // 7. Live SSE stream listeners
    setupRealtimeSSE();

    // 8. Maintenance triggers
    setupMaintenance();
}

/* ========================================================
   1. NAVIGATION & TAB ROUTING (XSS Safe)
   ======================================================== */
function setupTabSwitching() {
    const navItems = document.querySelectorAll('.nav-item');
    const tabPanels = document.querySelectorAll('.tab-panel');
    const titleEl = document.getElementById('current-tab-title');
    const descEl = document.getElementById('current-tab-desc');

    const tabMetadata = {
        dashboard: { title: '控制主页', desc: '实时监控 MosDNS 解析数据与主控系统状态' },
        config: { title: '核心配置编辑', desc: '可视化修改 config-v5.yaml (保存前将触发安全语法预检与 canary 回滚)' },
        rules: { title: '域名分流规则列表', desc: '直接编辑 local-domain.txt, proxy-list.txt 等域名过滤器' },
        queries: { title: '解析审计历史', desc: '实时多维度审计局域网 DNS 请求耗时与命中记录' },
        maintenance: { title: '系统运维面板', desc: '在线升级 DNS 资源包与二进制主程序，查看控制台输出' }
    };

    navItems.forEach(btn => {
        btn.addEventListener('click', () => {
            const targetTab = btn.getAttribute('data-tab');
            if (!targetTab || state.currentTab === targetTab) return;

            // Update state
            state.currentTab = targetTab;

            // Toggle active styles in navigation
            navItems.forEach(n => n.classList.remove('active'));
            btn.classList.add('active');

            // Switch panel tabs
            tabPanels.forEach(panel => {
                panel.classList.remove('active');
                if (panel.id === `tab-${targetTab}`) {
                    panel.classList.add('active');
                }
            });

            // Update Header labels
            const meta = tabMetadata[targetTab] || { title: '控制面板', desc: '' };
            titleEl.textContent = meta.title;
            descEl.textContent = meta.desc;

            // Tab-specific initializers
            if (targetTab === 'config') {
                loadConfig();
            } else if (targetTab === 'rules') {
                loadRulesList();
            } else if (targetTab === 'queries') {
                fetchQueryHistory(1);
            }
        });
    });
}

/* ========================================================
   2. SYSTEM STATUS POLLING & RESOURCE MONITORS
   ======================================================= */
function syncStatus() {
    fetch('/api/status')
        .then(res => {
            if (!res.ok) throw new Error('Offline');
            return res.json();
        })
        .then(data => {
            updatePingIndicator(true, data.service_active);
            
            // Uptime format
            const uptime = data["panel_uptime_seconds: "] || 0;
            document.getElementById('dash-uptime').textContent = formatSeconds(uptime);

            // RAM Stats
            const totalRAM = data.ram_total_kb || 0;
            const freeRAM = data.ram_free_kb || 0;
            if (totalRAM > 0) {
                const usedRAM = totalRAM - freeRAM;
                const ramPercent = Math.round((usedRAM / totalRAM) * 100);
                document.getElementById('ram-percent-txt').textContent = `${ramPercent}% (${Math.round(usedRAM/1024)}MB / ${Math.round(totalRAM/1024)}MB)`;
                document.getElementById('ram-percent-bar').style.width = `${ramPercent}%`;
            }

            // CPU Stats
            const cpuPercent = Math.round(data.cpu_usage_percent || 0);
            document.getElementById('cpu-percent-txt').textContent = `${cpuPercent}%`;
            document.getElementById('cpu-percent-bar').style.width = `${cpuPercent}%`;
        })
        .catch(() => {
            updatePingIndicator(false, false);
        });
}

function updatePingIndicator(connected, serviceActive) {
    const lamp = document.getElementById('mosdns-ping-lamp');
    const text = document.getElementById('mosdns-ping-text');

    lamp.replaceChildren(); // Safe clear
    lamp.className = 'status-lamp';

    if (!connected) {
        lamp.classList.add('lamp-offline');
        text.textContent = '面板离线';
    } else if (serviceActive) {
        lamp.classList.add('lamp-online');
        text.textContent = 'DNS 正常运行';
    } else {
        lamp.classList.add('lamp-offline');
        text.textContent = 'DNS 已停止';
    }
}

function formatSeconds(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    return [h, m, s].map(v => v < 10 ? '0' + v : v).join(':');
}

/* ========================================================
   3. STATS & ANALYTICS AGGREGATIONS (XSS Safe)
   ======================================================= */
function syncStats() {
    if (state.currentTab !== 'dashboard') return;

    fetch('/api/stats/summary')
        .then(res => res.json())
        .then(data => {
            // 1. General numbers
            document.getElementById('dash-total-queries').textContent = data.total_queries.toLocaleString();
            document.getElementById('dash-avg-duration').textContent = `平均耗时: ${data.avg_duration_ms.toFixed(1)} ms`;
            document.getElementById('dash-cache-rate').textContent = `${data.cache_hit_rate.toFixed(1)}%`;

            // Calculate mock average cache hits saving time (approx 45ms per remote query)
            const hits = Math.round(data.total_queries * (data.cache_hit_rate / 100));
            const timeSavedHours = ((hits * 45) / 1000 / 3600).toFixed(2);
            document.getElementById('dash-cache-hits').textContent = `累计节约延迟: ~ ${timeSavedHours} 小时`;

            // 2. Render rank lists
            renderTopDomainsTable(data.top_domains);
            renderStatusDistTable(data.status_dist, data.total_queries);

            // 3. Render analytical line graph
            renderVolumeChart(data.hourly_volume);
        })
        .catch(err => console.error('Error fetching statistics:', err));
}

function renderTopDomainsTable(domains) {
    const tbody = document.getElementById('dashboard-top-domains-body');
    tbody.replaceChildren();

    if (!domains || domains.length === 0) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.setAttribute('colspan', '3');
        td.className = 'text-center';
        td.textContent = '暂无解析记录数据';
        tr.appendChild(td);
        tbody.appendChild(tr);
        return;
    }

    domains.forEach((item, index) => {
        const tr = document.createElement('tr');
        
        const tdRank = document.createElement('td');
        tdRank.textContent = String(index + 1);
        
        const tdDomain = document.createElement('td');
        tdDomain.className = 'editor-path';
        tdDomain.textContent = item.domain;
        
        const tdCount = document.createElement('td');
        tdCount.textContent = item.count.toLocaleString();
        
        tr.appendChild(tdRank);
        tr.appendChild(tdDomain);
        tr.appendChild(tdCount);
        tbody.appendChild(tr);
    });
}

function renderStatusDistTable(stats, total) {
    const tbody = document.getElementById('dashboard-status-dist-body');
    tbody.replaceChildren();

    if (!stats || stats.length === 0 || total === 0) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.setAttribute('colspan', '3');
        td.className = 'text-center';
        td.textContent = '暂无策略分析数据';
        tr.appendChild(td);
        tbody.appendChild(tr);
        return;
    }

    stats.forEach(item => {
        const tr = document.createElement('tr');
        
        const tdName = document.createElement('td');
        const badge = document.createElement('span');
        badge.className = `badge-status ${getBadgeClass(item.status)}`;
        badge.textContent = item.status;
        tdName.appendChild(badge);
        
        const tdCount = document.createElement('td');
        tdCount.textContent = item.count.toLocaleString();
        
        const tdPercent = document.createElement('td');
        const pct = ((item.count / total) * 100).toFixed(1);
        tdPercent.textContent = `${pct}%`;
        
        tr.appendChild(tdName);
        tr.appendChild(tdCount);
        tr.appendChild(tdPercent);
        tbody.appendChild(tr);
    });
}

// Draw a beautiful custom canvas line-chart (No external bulky dependencies!)
function renderVolumeChart(volumeData) {
    const canvas = document.getElementById('queryTrendCanvas');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    const dpr = window.devicePixelRatio || 1;
    
    // Size settings
    const width = canvas.parentElement.clientWidth;
    const height = canvas.parentElement.clientHeight;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Dynamic grid parameters
    const paddingLeft = 40;
    const paddingRight = 20;
    const paddingTop = 20;
    const paddingBottom = 30;
    const graphWidth = width - paddingLeft - paddingRight;
    const graphHeight = height - paddingTop - paddingBottom;

    ctx.clearRect(0, 0, width, height);

    if (!volumeData || volumeData.length === 0) {
        ctx.fillStyle = '#6b7280';
        ctx.font = "12px 'Inter'";
        ctx.textAlign = 'center';
        ctx.fillText("暂无趋势图表数据", width / 2, height / 2);
        return;
    }

    // Determine bounds
    let maxVal = 0;
    volumeData.forEach(d => { if (d.count > maxVal) maxVal = d.count; });
    maxVal = Math.max(10, Math.ceil(maxVal * 1.15)); // 15% headroom

    // Draw background grid lines
    ctx.strokeStyle = "rgba(255, 255, 255, 0.03)";
    ctx.lineWidth = 1;
    const gridCount = 4;
    for (let i = 0; i <= gridCount; i++) {
        const y = paddingTop + (graphHeight * (1 - i / gridCount));
        ctx.beginPath();
        ctx.moveTo(paddingLeft, y);
        ctx.lineTo(width - paddingRight, y);
        ctx.stroke();

        // Left axis labels
        ctx.fillStyle = "#6b7280";
        ctx.font = "9px 'Inter'";
        ctx.textAlign = "right";
        ctx.fillText(Math.round(maxVal * i / gridCount), paddingLeft - 8, y + 3);
    }

    // Points setup
    const len = volumeData.length;
    const pts = volumeData.map((d, index) => {
        const x = paddingLeft + (index / (len - 1)) * graphWidth;
        const y = paddingTop + (1 - d.count / maxVal) * graphHeight;
        return { x, y };
    });

    // 1. Draw smooth gradient fills under curve
    if (len > 1) {
        ctx.beginPath();
        ctx.moveTo(pts[0].x, paddingTop + graphHeight);
        ctx.lineTo(pts[0].x, pts[0].y);
        
        // Curve coordinates using quadratic/bezier smoothing
        for (let i = 0; i < len - 1; i++) {
            const xc = (pts[i].x + pts[i+1].x) / 2;
            const yc = (pts[i].y + pts[i+1].y) / 2;
            ctx.quadraticCurveTo(pts[i].x, pts[i].y, xc, yc);
        }
        ctx.lineTo(pts[len-1].x, pts[len-1].y);
        ctx.lineTo(pts[len-1].x, paddingTop + graphHeight);
        ctx.closePath();

        const grad = ctx.createLinearGradient(0, paddingTop, 0, paddingTop + graphHeight);
        grad.addColorStop(0, "rgba(59, 130, 246, 0.22)"); // Neon blue
        grad.addColorStop(1, "rgba(59, 130, 246, 0.0)");
        ctx.fillStyle = grad;
        ctx.fill();
    }

    // 2. Draw line curve path
    if (len > 1) {
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 0; i < len - 1; i++) {
            const xc = (pts[i].x + pts[i+1].x) / 2;
            const yc = (pts[i].y + pts[i+1].y) / 2;
            ctx.quadraticCurveTo(pts[i].x, pts[i].y, xc, yc);
        }
        ctx.lineTo(pts[len-1].x, pts[len-1].y);
        ctx.strokeStyle = "#3b82f6";
        ctx.lineWidth = 2.5;
        ctx.shadowColor = "rgba(59, 130, 246, 0.4)";
        ctx.shadowBlur = 8;
        ctx.stroke();
        ctx.shadowBlur = 0; // Reset shadow
    }

    // 3. Draw dots on nodes & Hourly label
    volumeData.forEach((d, index) => {
        const pt = pts[index];
        
        // Draw bottom labels (limit count to avoid wrapping)
        if (len < 12 || index % 2 === 0) {
            ctx.fillStyle = "#6b7280";
            ctx.font = "9px 'Inter'";
            ctx.textAlign = "center";
            ctx.fillText(d.hour, pt.x, height - 10);
        }

        // Draw dot
        ctx.beginPath();
        ctx.arc(pt.x, pt.y, 4, 0, 2 * Math.PI);
        ctx.fillStyle = "#3b82f6";
        ctx.strokeStyle = "#fff";
        ctx.lineWidth = 1.5;
        ctx.fill();
        ctx.stroke();
    });
}

/* ========================================================
   4. SYSTEM QUICK SERVICES CONTROL BUTTONS
   ======================================================= */
function setupServiceActions() {
    const handleAction = (action) => {
        if (!confirm(`您确定要 ${action === 'restart' ? '重启' : action === 'start' ? '启动' : '关闭'} 本地主 DNS 解析服务吗？这可能会引起短暂的内网解析抖动。`)) return;

        const startBtn = document.getElementById('header-btn-start');
        const stopBtn = document.getElementById('header-btn-stop');
        const restartBtn = document.getElementById('header-btn-restart');

        // Loading states
        [startBtn, stopBtn, restartBtn].forEach(b => b.disabled = true);

        fetch('/api/service/action', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action })
        })
        .then(res => res.json())
        .then(data => {
            alert(data.message || '操作执行成功');
            syncStatus();
        })
        .catch(err => {
            alert('指令执行失败，请检查 Systemd 守护进程状态: ' + err.message);
        })
        .finally(() => {
            [startBtn, stopBtn, restartBtn].forEach(b => b.disabled = false);
        });
    };

    document.getElementById('header-btn-restart').addEventListener('click', () => handleAction('restart'));
    document.getElementById('header-btn-start').addEventListener('click', () => handleAction('start'));
    document.getElementById('header-btn-stop').addEventListener('click', () => handleAction('stop'));
}

/* ========================================================
   5. CONFIG FILE VISUAL EDITOR & CANARY CHECK
   ======================================================= */
function loadConfig() {
    const textarea = document.getElementById('config-textarea');
    textarea.value = '';
    textarea.placeholder = '正在读取 MosDNS 核心配置文件 config-v5.yaml...';

    fetch('/api/config')
        .then(res => res.text())
        .then(text => {
            textarea.value = text;
        })
        .catch(err => {
            textarea.placeholder = '读取配置文件失败: ' + err.message;
        });
}

function setupConfigEditor() {
    const saveBtn = document.getElementById('config-btn-save');
    const textarea = document.getElementById('config-textarea');
    const consoleContainer = document.getElementById('config-console-container');
    const consolePre = document.getElementById('config-console-pre');
    const collapseArrow = document.querySelector('.console-collapse-arrow');

    // Click collapse header triggers toggle
    document.getElementById('config-console-header').addEventListener('click', () => {
        consoleContainer.classList.toggle('console-collapsed');
        consoleContainer.classList.toggle('console-expanded');
    });

    saveBtn.addEventListener('click', () => {
        const bodyText = textarea.value.trim();
        if (!bodyText) {
            alert('配置文件内容不能为空！');
            return;
        }

        if (!confirm('【高可用重要警示】\n保存配置将触发后端 DNS 语法预检验。若校验通过，系统在覆盖配置前会自动为您创建物理备份，并进行“本地解析金丝雀自检验”。若自检失败，系统会自动回滚配置，确保内网解析 100% 不会由于配置错误发生瘫痪。\n\n确认立即应用该配置吗？')) return;

        saveBtn.disabled = true;
        saveBtn.textContent = '💾 语法预检中...';

        consoleContainer.className = 'editor-console console-expanded';
        consolePre.replaceChildren(); // Safe clear
        const line1 = document.createElement('div');
        line1.className = 'terminal-line text-info';
        line1.textContent = '>> [!] 发起配置文件语法预检...';
        consolePre.appendChild(line1);

        fetch('/api/config', {
            method: 'POST',
            body: bodyText
        })
        .then(async res => {
            const isJson = res.headers.get('Content-Type')?.includes('application/json');
            const data = isJson ? await res.json() : { error: await res.text() };

            if (res.ok) {
                const line2 = document.createElement('div');
                line2.className = 'terminal-line text-success';
                line2.textContent = `>> [SUCCESS] ${data.message || '配置更新应用成功，且金丝雀解析自测试通过！'}`;
                consolePre.appendChild(line2);
                alert('🎉 配置更新成功，且本地 DNS 金丝雀自测健康，服务已平滑热重载上线！');
            } else {
                // Show errors in precheck console
                const lineErr = document.createElement('div');
                lineErr.className = 'terminal-line text-error';
                lineErr.textContent = `>> [CRITICAL ERROR] ${data.error || '未知的应用报错'}`;
                consolePre.appendChild(lineErr);

                if (data.output) {
                    const lineOutput = document.createElement('div');
                    lineOutput.className = 'terminal-line text-dim';
                    lineOutput.textContent = data.output;
                    consolePre.appendChild(lineOutput);
                }

                alert('❌ 校验或金丝雀测试失败！生产级配置已被保护不受侵害。请查看底部控制台预检错误输出。');
            }
        })
        .catch(err => {
            const lineErr = document.createElement('div');
            lineErr.className = 'terminal-line text-error';
            lineErr.textContent = `>> [ERROR] 访问接口失败: ${err.message}`;
            consolePre.appendChild(lineErr);
            alert('网络传输故障，配置保存失败！');
        })
        .finally(() => {
            saveBtn.disabled = false;
            saveBtn.textContent = '💾 保存并应用';
            syncStatus();
        });
    });
}

/* ========================================================
   6. DOMAIN LISTS MANAGER (XSS Safe selector)
   ======================================================= */
function loadRulesList() {
    const listGroup = document.getElementById('rules-file-selector');
    listGroup.replaceChildren(); // Safe clear

    fetch('/api/rules')
        .then(res => res.json())
        .then(files => {
            if (!files || files.length === 0) {
                const p = document.createElement('p');
                p.className = 'card-helper text-center';
                p.textContent = '没有读取到可用的域名列表文件';
                listGroup.appendChild(p);
                return;
            }

            files.forEach(file => {
                const btn = document.createElement('button');
                btn.className = 'rule-file-btn';
                btn.textContent = file;
                btn.addEventListener('click', () => {
                    // Activate styles
                    document.querySelectorAll('.rule-file-btn').forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');

                    // Load content
                    loadRuleFileContent(file);
                });
                listGroup.appendChild(btn);
            });
        })
        .catch(err => {
            console.error('Error loading rules files:', err);
        });
}

function loadRuleFileContent(file) {
    const textarea = document.getElementById('rules-textarea');
    const saveBtn = document.getElementById('rules-btn-save');
    const label = document.getElementById('rules-current-file-label');

    state.selectedRuleFile = file;
    textarea.value = '';
    textarea.placeholder = `正在拉取 ${file} 过滤域名集...`;
    textarea.disabled = true;
    saveBtn.disabled = true;

    fetch(`/api/rules/content?file=${encodeURIComponent(file)}`)
        .then(res => res.text())
        .then(text => {
            textarea.value = text;
            textarea.disabled = false;
            saveBtn.disabled = false;
            label.textContent = `/opt/mosdns/bin/${file}`;
        })
        .catch(err => {
            textarea.placeholder = `拉取域名列表 ${file} 发生故障: ` + err.message;
        });
}

function setupRulesManager() {
    const saveBtn = document.getElementById('rules-btn-save');
    const textarea = document.getElementById('rules-textarea');

    saveBtn.addEventListener('click', () => {
        if (!state.selectedRuleFile) return;

        if (!confirm(`【防断网自愈保障】\n修改列表域名后，后端在重新加载 DNS 服务前会自动创建备份；如果重启后本地解析遭遇不可抗拒的故障，系统会自动回滚并还原该文件。\n\n您确认提交修改 '${state.selectedRuleFile}' 吗？`)) return;

        saveBtn.disabled = true;
        saveBtn.textContent = '💾 提交并测试...';

        fetch(`/api/rules/content?file=${encodeURIComponent(state.selectedRuleFile)}`, {
            method: 'POST',
            body: textarea.value
        })
        .then(async res => {
            if (res.ok) {
                alert(`🎉 域名列表 '${state.selectedRuleFile}' 应用成功，主主解析自测试通过，服务已平滑重载！`);
            } else {
                const text = await res.text();
                alert(`❌ 域名列表加载失败！已自动触发安全回滚。\n详情: ${text}`);
            }
        })
        .catch(err => {
            alert('网络传输故障，列表保存失败！' + err.message);
        })
        .finally(() => {
            saveBtn.disabled = false;
            saveBtn.textContent = '💾 保存域名规则';
            syncStatus();
        });
    });
}

/* ========================================================
   7. PARSED QUERIES HISTORICAL AUDIT (XSS Safe tables)
   ======================================================= */
function fetchQueryHistory(page) {
    state.auditPage = page;
    const tbody = document.getElementById('audit-table-body');
    tbody.replaceChildren();

    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.setAttribute('colspan', '7');
    td.className = 'text-center text-dim';
    td.textContent = '正在发起 SQLite 解析日志多条件查询审计中...';
    tr.appendChild(td);
    tbody.appendChild(tr);

    const queryUrl = `/api/queries/history?page=${page}&pageSize=${state.auditPageSize}&search=${encodeURIComponent(state.auditSearch)}`;
    
    fetch(queryUrl)
        .then(res => res.json())
        .then(data => {
            tbody.replaceChildren(); // Clear loading indicator

            const logs = data.logs;
            if (!logs || logs.length === 0) {
                const trEmpty = document.createElement('tr');
                const tdEmpty = document.createElement('td');
                tdEmpty.setAttribute('colspan', '7');
                tdEmpty.className = 'text-center text-dim';
                tdEmpty.textContent = '没有找到符合特定筛选条件的解析记录。';
                trEmpty.appendChild(tdEmpty);
                tbody.appendChild(trEmpty);
                
                document.getElementById('audit-page-info').textContent = '无记录';
                return;
            }

            // Render table records dynamically and XSS-immune
            logs.forEach(log => {
                const trRow = createQueryLogRow(log);
                tbody.appendChild(trRow);
            });

            // Update page controls
            const totalRecords = data.total_count || 0;
            const maxPages = Math.ceil(totalRecords / state.auditPageSize) || 1;
            document.getElementById('audit-page-info').textContent = `第 ${page} / ${maxPages} 页 (共 ${totalRecords.toLocaleString()} 条)`;
            
            document.getElementById('audit-prev-btn').disabled = (page <= 1);
            document.getElementById('audit-next-btn').disabled = (page >= maxPages);
        })
        .catch(err => {
            tbody.replaceChildren();
            const trErr = document.createElement('tr');
            const tdErr = document.createElement('td');
            tdErr.setAttribute('colspan', '7');
            tdErr.className = 'text-center text-error';
            tdErr.textContent = '拉取解析审计历史失败: ' + err.message;
            trErr.appendChild(tdErr);
            tbody.appendChild(trErr);
        });
}

function createQueryLogRow(log) {
    const tr = document.createElement('tr');

    const tdTime = document.createElement('td');
    tdTime.className = 'text-dim';
    tdTime.textContent = log.time;

    const tdIP = document.createElement('td');
    tdIP.textContent = log.client_ip;

    const tdDomain = document.createElement('td');
    tdDomain.className = 'editor-path';
    tdDomain.textContent = log.domain;

    const tdType = document.createElement('td');
    tdType.className = 'text-dim';
    tdType.textContent = log.qtype;

    const tdStatus = document.createElement('td');
    const badge = document.createElement('span');
    badge.className = `badge-status ${getBadgeClass(log.status)}`;
    badge.textContent = log.status;
    tdStatus.appendChild(badge);

    const tdLatency = document.createElement('td');
    if (log.duration_ms === 0) {
        tdLatency.className = 'text-green';
        tdLatency.textContent = '0 ms';
    } else {
        tdLatency.textContent = `${log.duration_ms} ms`;
    }

    const tdUpstream = document.createElement('td');
    tdUpstream.className = 'text-dim';
    tdUpstream.textContent = log.upstream;

    tr.appendChild(tdTime);
    tr.appendChild(tdIP);
    tr.appendChild(tdDomain);
    tr.appendChild(tdType);
    tr.appendChild(tdStatus);
    tr.appendChild(tdLatency);
    tr.appendChild(tdUpstream);

    return tr;
}

function getBadgeClass(status) {
    switch (status) {
        case '[cache_hit]':
            return 'badge-cache';
        case '[router_hit]':
            return 'badge-local';
        case '[local_hit]':
        case '[fallback_cn_hit]':
            return 'badge-local';
        case '[remote_hit_resilient]':
        case '[fallback_remote_final_resilient]':
            return 'badge-remote';
        case '[fallback_remote_trial]':
            return 'badge-fallback';
        default:
            return 'badge-warning';
    }
}

function setupAuditPagination() {
    const prevBtn = document.getElementById('audit-prev-btn');
    const nextBtn = document.getElementById('audit-next-btn');
    const searchBtn = document.getElementById('audit-btn-search');
    const resetBtn = document.getElementById('audit-btn-reset');
    const searchInput = document.getElementById('audit-search-input');

    prevBtn.addEventListener('click', () => {
        if (state.auditPage > 1) {
            fetchQueryHistory(state.auditPage - 1);
        }
    });

    nextBtn.addEventListener('click', () => {
        fetchQueryHistory(state.auditPage + 1);
    });

    searchBtn.addEventListener('click', () => {
        state.auditSearch = searchInput.value.trim();
        fetchQueryHistory(1);
    });

    searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            state.auditSearch = searchInput.value.trim();
            fetchQueryHistory(1);
        }
    });

    resetBtn.addEventListener('click', () => {
        searchInput.value = '';
        state.auditSearch = '';
        fetchQueryHistory(1);
    });
}

/* ========================================================
   8. REAL-TIME SERVER-SENT EVENTS (SSE) CHANNELS
   ======================================================= */
function setupRealtimeSSE() {
    // 1. SSE Queries Stream - prepends to history table in real time if on page 1
    state.querySse = new EventSource('/api/queries/stream');
    state.querySse.onmessage = (event) => {
        try {
            const logItem = JSON.parse(event.data);
            
            // Only prepend to audit table if user is currently on Page 1 and no search filter is applied
            const auditBody = document.getElementById('audit-table-body');
            if (state.currentTab === 'queries' && state.auditPage === 1 && state.auditSearch === '') {
                const tr = createQueryLogRow(logItem);
                
                // Keep table trimmed to pageSize
                if (auditBody.children.length >= state.auditPageSize) {
                    auditBody.removeChild(auditBody.lastChild);
                }
                auditBody.insertBefore(tr, auditBody.firstChild);
            }
        } catch (e) {
            console.error('Error parsing SSE query payload:', e);
        }
    };

    // 2. SSE Logs Stream - handled in the Maintenance/Console tab
    const maintTerminal = document.getElementById('maint-terminal');
    state.logSse = new EventSource('/api/logs/stream');
    
    state.logSse.onmessage = (event) => {
        // Output logs only if console mode is set to 'sys' (system raw logs)
        if (state.consoleMode === 'sys') {
            appendTerminalLine(event.data, 'sys');
        }
    };

    // Mode Selector buttons
    const btnMaint = document.getElementById('btn-mode-maint');
    const btnSys = document.getElementById('btn-mode-sys');

    btnMaint.addEventListener('click', () => {
        state.consoleMode = 'maint';
        btnMaint.classList.add('active');
        btnSys.classList.remove('active');
        maintTerminal.replaceChildren(); // Safe clear
        appendTerminalLine("// 终端处于空闲状态，等待发起运维升级操作...", 'dim');
    });

    btnSys.addEventListener('click', () => {
        state.consoleMode = 'sys';
        btnSys.classList.add('active');
        btnMaint.classList.remove('remove'); // Typo protection
        btnMaint.classList.remove('active');
        maintTerminal.replaceChildren();
        appendTerminalLine("// 正在连接系统物理日志流 /var/log/mosdns/mosdns.log ...", 'dim');
    });
}

function appendTerminalLine(text, style) {
    const terminal = document.getElementById('maint-terminal');
    const line = document.createElement('div');
    line.className = 'terminal-line';
    
    // Style tags mapping
    if (style === 'dim') line.classList.add('text-dim');
    else if (style === 'info') line.classList.add('text-info');
    else if (style === 'success') line.classList.add('text-success');
    else if (style === 'error') line.classList.add('text-error');
    else if (style === 'sys') {
        // System logs formatting mapping
        if (text.includes('[error]')) line.classList.add('text-error');
        else if (text.includes('[warn]')) line.classList.add('text-info');
        else if (text.includes('query_summary') || text.includes('info summary')) line.classList.add('text-success');
        else line.classList.add('text-dim');
    }

    line.textContent = text;
    terminal.appendChild(line);

    // Auto scroll to bottom
    terminal.scrollTop = terminal.scrollHeight;
}

/* ========================================================
   9. MAINTENANCE OPERATIONS RUNNER (Stream Output via SSE)
   ======================================================= */
function setupMaintenance() {
    const runMaintenance = (action, jobName) => {
        if (!confirm(`【警告：DNS 关键操作】\n您确定要立即在线执行 '${jobName}' 指令吗？\n升级过程中，系统在拉取完成且自检完全通过前不会停止原解析进程。在最后应用时可能产生毫秒级的自测试切换，通常不会影响网络。`)) return;

        // Force switch terminal view to Maintenance console
        state.consoleMode = 'maint';
        document.getElementById('btn-mode-maint').classList.add('active');
        document.getElementById('btn-mode-sys').classList.remove('active');

        const terminal = document.getElementById('maint-terminal');
        terminal.replaceChildren(); // Safe clear

        // Start SSE stream trigger
        const sseSource = new EventSource(`/api/maintenance/run?action=${action}`);
        
        sseSource.onmessage = (event) => {
            const line = event.data;
            if (line.startsWith('[INFO]')) {
                appendTerminalLine(line, 'info');
            } else if (line.startsWith('[SUCCESS]')) {
                appendTerminalLine(line, 'success');
                sseSource.close();
                alert(`🎉 恭喜，'${jobName}' 任务已安全且稳定地执行完毕！`);
                syncStatus();
            } else if (line.startsWith('[ERROR]')) {
                appendTerminalLine(line, 'error');
                sseSource.close();
                alert(`❌ 运维任务 '${jobName}' 执行报错，系统已自动实施安全保护机制，阻断了损坏更新！`);
            } else {
                appendTerminalLine(line, 'sys');
            }
        };

        sseSource.onerror = (err) => {
            appendTerminalLine(">> [ERROR] 终端日志连接意外中断。指令可能仍在后台安全执行，请稍后刷新面板确认。", 'error');
            sseSource.close();
        };
    };

    document.getElementById('maint-btn-geo').addEventListener('click', () => {
        runMaintenance('update-geo', '一键规则升级');
    });

    document.getElementById('maint-btn-bin').addEventListener('click', () => {
        runMaintenance('update-bin', '一键二进制升级');
    });
}

const OverviewView = {
    _pollTimer: null,

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in overview-page">
                <div class="flex items-start justify-between flex-wrap gap-3">
                    <div>
                        <h2 class="text-xl font-bold text-slate-100 tracking-tight">Overview</h2>
                        <p class="text-xs text-slate-400 mt-1">Is this computer healthy? Status from Event Intelligence — incidents, not raw events.</p>
                    </div>
                    <button type="button" class="action-btn cyan" onclick="OverviewView.refresh()">Refresh</button>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <div class="glass-panel p-6 text-center cursor-pointer hover:border-cyan-500/40 transition"
                         onclick="Router.loadModuleView('healthcenter')">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider">Health Score</div>
                        <div id="ov-health-score" class="score-ring text-5xl font-bold text-emerald-400 mt-3">--</div>
                        <div id="ov-health-label" class="text-sm text-slate-400 mt-2">Loading…</div>
                    </div>
                    <div class="glass-panel p-6 text-center cursor-pointer hover:border-cyan-500/40 transition"
                         onclick="Router.loadModuleView('securitycenter')">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider">Security Score</div>
                        <div id="ov-sec-score" class="score-ring text-5xl font-bold text-cyan-400 mt-3">--</div>
                        <div id="ov-sec-label" class="text-sm text-slate-400 mt-2">Loading…</div>
                    </div>
                    <div class="glass-panel p-6 text-center cursor-pointer hover:border-cyan-500/40 transition"
                         onclick="Router.loadModuleView('incidents')">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider">Active Incidents</div>
                        <div id="ov-inc-count" class="score-ring text-5xl font-bold text-amber-400 mt-3">--</div>
                        <div id="ov-inc-label" class="text-sm text-slate-400 mt-2">Loading…</div>
                    </div>
                </div>

                <div class="glass-panel p-4">
                    <div class="flex items-center justify-between mb-3 flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100 flex items-center gap-2">
                            <i data-lucide="bell" class="w-4 h-4 text-cyan-400"></i>
                            Recent alerts
                        </h3>
                        <button type="button" class="text-[11px] text-cyan-400 hover:underline"
                                onclick="Router.loadModuleView('alerts')">Open Notification Centre</button>
                    </div>
                    <div id="ov-recent-alerts" class="space-y-2 text-xs max-h-64 overflow-y-auto"></div>
                </div>

                <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
                    <div class="glass-panel p-4">
                        <div class="flex items-center justify-between mb-3">
                            <h3 class="text-sm font-bold text-slate-100">Critical &amp; Warning Incidents</h3>
                            <button type="button" class="text-[11px] text-cyan-400 hover:underline"
                                    onclick="Router.loadModuleView('incidents')">Open Incident Center</button>
                        </div>
                        <div id="ov-incidents" class="space-y-2 text-xs max-h-72 overflow-y-auto"></div>
                    </div>
                    <div class="glass-panel p-4">
                        <div class="flex items-center justify-between mb-3">
                            <h3 class="text-sm font-bold text-slate-100">Health Checks</h3>
                            <button type="button" class="text-[11px] text-cyan-400 hover:underline"
                                    onclick="Router.loadModuleView('healthcenter')">Open Health Center</button>
                        </div>
                        <div id="ov-checks" class="space-y-2 text-xs max-h-72 overflow-y-auto"></div>
                    </div>
                </div>

                <div class="grid grid-cols-2 md:grid-cols-4 gap-3" id="ov-quick">
                    <button type="button" class="glass-panel p-3 text-left hover:border-cyan-500/40 transition"
                            onclick="Router.loadModuleView('alerts')">
                        <div class="flex items-center gap-2 text-slate-300 text-xs font-semibold">
                            <i data-lucide="bell" class="w-4 h-4 text-cyan-400"></i> Notifications
                        </div>
                        <div id="ov-alert-count" class="text-[11px] text-slate-500 mt-1">—</div>
                    </button>
                    <button type="button" class="glass-panel p-3 text-left hover:border-cyan-500/40 transition"
                            onclick="Router.loadModuleView('timeline')">
                        <div class="flex items-center gap-2 text-slate-300 text-xs font-semibold">
                            <i data-lucide="history" class="w-4 h-4 text-cyan-400"></i> Timeline
                        </div>
                        <div class="text-[11px] text-slate-500 mt-1">Event &amp; incident stream</div>
                    </button>
                    <button type="button" class="glass-panel p-3 text-left hover:border-cyan-500/40 transition"
                            onclick="Router.loadModuleView('services')">
                        <div class="flex items-center gap-2 text-slate-300 text-xs font-semibold">
                            <i data-lucide="cog" class="w-4 h-4 text-cyan-400"></i> Services
                        </div>
                        <div class="text-[11px] text-slate-500 mt-1">State &amp; recovery</div>
                    </button>
                    <button type="button" class="glass-panel p-3 text-left hover:border-cyan-500/40 transition"
                            onclick="Router.loadModuleView('security')">
                        <div class="flex items-center gap-2 text-slate-300 text-xs font-semibold">
                            <i data-lucide="shield" class="w-4 h-4 text-cyan-400"></i> Security Tools
                        </div>
                        <div class="text-[11px] text-slate-500 mt-1">Defender &amp; firewall</div>
                    </button>
                </div>
            </div>
        `;
        lucide.createIcons();
        await this.refresh();
        this.startPoll();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        this._pollTimer = setInterval(() => this.refresh(true), 20000);
    },

    stopPoll() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    scoreColor(score) {
        const n = Number(score);
        if (isNaN(n)) return 'text-slate-400';
        if (n >= 80) return 'text-emerald-400';
        if (n >= 60) return 'text-amber-400';
        return 'text-rose-400';
    },

    healthVerdict(score) {
        const n = Number(score);
        if (isNaN(n)) return 'Unavailable';
        if (n >= 85) return 'Healthy';
        if (n >= 70) return 'Fair — review warnings';
        if (n >= 50) return 'Degraded — action needed';
        return 'Critical — investigate now';
    },

    statusColor(s) {
        const v = String(s || '').toLowerCase();
        if (v === 'healthy') return 'text-emerald-400';
        if (v === 'critical') return 'text-rose-400';
        if (v === 'warning') return 'text-amber-400';
        return 'text-slate-400';
    },

    sevClass(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return 'border-rose-500/40 bg-rose-500/10';
        if (s === 'warning') return 'border-amber-500/40 bg-amber-500/10';
        return 'border-slate-700 bg-slate-950/40';
    },

    sevText(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return 'text-rose-400';
        if (s === 'warning') return 'text-amber-400';
        return 'text-sky-400';
    },

    relTime(ts) {
        try {
            const d = new Date(ts);
            const sec = Math.max(0, Math.floor((Date.now() - d.getTime()) / 1000));
            if (sec < 60) return sec + 's ago';
            if (sec < 3600) return Math.floor(sec / 60) + ' min ago';
            if (sec < 86400) return Math.floor(sec / 3600) + 'h ago';
            return d.toLocaleString();
        } catch { return ts || ''; }
    },

    async ackAlert(id) {
        if (!id) return;
        await API.request(`alerts/${encodeURIComponent(id)}/ack`, 'POST', {});
        if (typeof refreshAlertsBellCount === 'function') refreshAlertsBellCount();
        await this.refresh(true);
    },

    renderRecentAlerts(alertRes) {
        const box = document.getElementById('ov-recent-alerts');
        if (!box) return;
        if (!alertRes || !alertRes.Success) {
            box.innerHTML = `<p class="text-slate-500">Could not load alerts.</p>`;
            return;
        }
        const items = API.asArray(alertRes.Data && alertRes.Data.Items ? alertRes.Data.Items : alertRes.Data);
        const unread = items.filter((a) => !(a.Acknowledged || a.acknowledged));
        const show = (unread.length ? unread : items).slice(0, 8);
        if (!show.length) {
            box.innerHTML = `
                <div class="rounded-lg border border-slate-800 bg-slate-950/40 p-3 space-y-2">
                    <p class="text-slate-400">No alerts in the dashboard inbox yet.</p>
                    <p class="text-[11px] text-slate-500">
                        Enable <span class="text-slate-300">Settings → Notifications → Dashboard inbox</span>
                        and keep Event Intelligence on. New incidents will appear here, in the header Alerts bell,
                        and in Notification Centre.
                    </p>
                    <button type="button" class="action-btn slate text-[11px]"
                            onclick="Router.loadModuleView('settings')">Open Settings</button>
                </div>`;
            return;
        }
        box.innerHTML = show.map((a) => {
            const id = this.escape(a.Id || a.id || '');
            const acked = !!(a.Acknowledged || a.acknowledged);
            const fleet = typeof isLocFleetAlert === 'function' && isLocFleetAlert(a);
            const pc = typeof locFleetPcFromAlert === 'function' ? locFleetPcFromAlert(a) : '';
            const cardClass = fleet
                ? `alert-card-fleet ${typeof locFleetSevClass === 'function' ? locFleetSevClass(a.Severity) : ''}`
                : this.sevClass(a.Severity);
            const chips = fleet
                ? `<span class="alert-chip-fleet">Fleet</span>${pc ? `<span class="alert-chip-fleet alert-chip-fleet-pc">${this.escape(pc)}</span>` : ''}`
                : '';
            return `
                <div class="flex items-start justify-between gap-3 p-3 rounded-lg border ${cardClass} ${acked ? 'opacity-50' : ''}">
                    <button type="button" class="min-w-0 text-left flex-1"
                            onclick="Router.loadModuleView('alerts')">
                        ${chips ? `<div class="flex items-center gap-1.5 flex-wrap mb-1">${chips}</div>` : ''}
                        <div class="flex items-center gap-2 flex-wrap">
                            <span class="font-semibold ${this.sevText(a.Severity)}">${this.escape(a.Severity || '')}</span>
                            <span class="text-slate-100 font-medium truncate">${this.escape(a.Title || '')}</span>
                        </div>
                        <div class="text-slate-500 mt-1 truncate">${this.escape(a.Message || '')}</div>
                        <div class="text-[11px] text-slate-500 mt-1">${this.escape(this.relTime(a.Timestamp || a.timestamp))}</div>
                    </button>
                    ${acked
                        ? '<span class="text-[10px] text-slate-500 shrink-0 mt-1">ACK</span>'
                        : `<button type="button" class="action-btn emerald text-[11px] shrink-0"
                                   onclick="event.stopPropagation(); OverviewView.ackAlert('${id}')">Ack</button>`}
                </div>`;
        }).join('');
    },

    async refresh(silent) {
        const [healthRes, secRes, incRes, alertRes] = await Promise.all([
            API.request('health-score', 'GET', null, 15000, { silent: !!silent }),
            API.request('security-score', 'GET', null, 15000, { silent: !!silent }),
            API.request('incidents?status=active', 'GET', null, 12000, { silent: !!silent }),
            API.request('alerts', 'GET', null, 8000, { silent: true })
        ]);

        const healthEl = document.getElementById('ov-health-score');
        const healthLabel = document.getElementById('ov-health-label');
        const checksEl = document.getElementById('ov-checks');
        if (healthRes.Success && healthRes.Data) {
            const score = healthRes.Data.Score;
            if (healthEl) {
                healthEl.textContent = `${score}%`;
                healthEl.className = `score-ring text-5xl font-bold mt-3 ${this.scoreColor(score)}`;
            }
            if (healthLabel) healthLabel.textContent = this.healthVerdict(score);
            if (checksEl) {
                const checks = API.asArray(healthRes.Data.Checks).slice(0, 8);
                checksEl.innerHTML = checks.length ? checks.map((c) => `
                    <div class="flex items-center justify-between p-2 rounded-lg bg-slate-950/50 border border-slate-800 cursor-pointer hover:border-cyan-500/30"
                         onclick="Router.loadModuleView('healthcenter')">
                        <div>
                            <div class="text-slate-200 font-medium">${this.escape(c.Name)}</div>
                            <div class="text-slate-500 truncate max-w-xs">${this.escape(c.Detail || '')}</div>
                        </div>
                        <span class="${this.statusColor(c.Status)} font-semibold shrink-0">${this.escape(c.Status)}</span>
                    </div>
                `).join('') : `<p class="text-slate-500">No health checks yet. Event Intelligence may still be warming up.</p>`;
            }
        } else if (healthLabel) {
            healthLabel.textContent = healthRes.Message || 'Unavailable';
        }

        const secEl = document.getElementById('ov-sec-score');
        const secLabel = document.getElementById('ov-sec-label');
        if (secRes.Success && secRes.Data) {
            const score = secRes.Data.Score;
            if (secEl) {
                secEl.textContent = `${score}%`;
                secEl.className = `score-ring text-5xl font-bold mt-3 ${this.scoreColor(score)}`;
            }
            if (secLabel) {
                const bad = API.asArray(secRes.Data.Checks).filter((c) =>
                    String(c.Status).toLowerCase() !== 'healthy').length;
                secLabel.textContent = bad ? `${bad} control(s) need attention` : 'Controls look solid';
            }
        } else if (secLabel) {
            secLabel.textContent = secRes.Message || 'Unavailable';
        }

        const incCount = document.getElementById('ov-inc-count');
        const incLabel = document.getElementById('ov-inc-label');
        const incList = document.getElementById('ov-incidents');
        if (incRes.Success && incRes.Data) {
            const summary = incRes.Data.Summary || {};
            const items = API.asArray(incRes.Data.Items);
            const open = summary.Open != null ? summary.Open : items.length;
            const critical = summary.Critical || 0;
            const warnings = summary.Warnings || 0;
            if (incCount) {
                incCount.textContent = String(open);
                incCount.className = `score-ring text-5xl font-bold mt-3 ${
                    critical > 0 ? 'text-rose-400' : warnings > 0 ? 'text-amber-400' : 'text-emerald-400'
                }`;
            }
            if (incLabel) {
                incLabel.textContent = critical > 0
                    ? `${critical} critical · ${warnings} warning`
                    : open === 0 ? 'No open incidents' : `${warnings} warning(s)`;
            }
            if (incList) {
                const focus = items.filter((i) => {
                    const s = String(i.Severity || '').toLowerCase();
                    return s === 'critical' || s === 'warning';
                }).slice(0, 8);
                const show = focus.length ? focus : items.slice(0, 6);
                if (!show.length) {
                    incList.innerHTML = `<p class="text-emerald-400/90">All clear — no open incidents.</p>`;
                } else {
                    incList.innerHTML = show.map((i) => `
                        <button type="button" class="w-full text-left p-3 rounded-lg border ${this.sevClass(i.Severity)} hover:border-cyan-500/40 transition"
                                onclick="Router.loadModuleView('incidents')">
                            <div class="flex justify-between gap-2">
                                <span class="font-semibold text-slate-100 truncate">${this.escape(i.Title)}</span>
                                <span class="shrink-0 text-slate-400">${this.escape(i.Severity)} · ${i.Score || 0}</span>
                            </div>
                            <div class="text-slate-500 mt-1">${this.escape(i.Category || '')}</div>
                        </button>
                    `).join('');
                }
            }
        }

        const alertCount = document.getElementById('ov-alert-count');
        if (alertCount && alertRes.Success) {
            const unread = alertRes.Data && (alertRes.Data.Unread != null)
                ? alertRes.Data.Unread
                : API.asArray(alertRes.Data && alertRes.Data.Items ? alertRes.Data.Items : alertRes.Data)
                    .filter((a) => !(a.Acknowledged || a.acknowledged)).length;
            alertCount.textContent = unread ? `${unread} unread` : 'Inbox clear';
        }
        this.renderRecentAlerts(alertRes);
    }
};

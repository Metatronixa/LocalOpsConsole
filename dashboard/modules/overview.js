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
    }
};

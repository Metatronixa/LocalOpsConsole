const HealthCenterView = {
    _pollTimer: null,

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Health Center</h2>
                        <p class="text-xs text-slate-400">Continuous host health checks from Event Intelligence.</p>
                    </div>
                    <div class="flex gap-2">
                        <button type="button" class="action-btn slate text-[11px]" onclick="Router.loadModuleView('overview')">Overview</button>
                        <button type="button" class="action-btn cyan" onclick="HealthCenterView.refresh()">Refresh</button>
                    </div>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div class="glass-panel p-6 text-center">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider">Health Score</div>
                        <div id="health-score" class="score-ring text-5xl font-bold text-emerald-400 mt-2">--</div>
                        <div id="health-verdict" class="text-sm text-slate-400 mt-2">—</div>
                    </div>
                    <div class="md:col-span-2 glass-panel p-4">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider mb-3">Check status</div>
                        <div id="health-checks" class="space-y-2 text-xs max-h-96 overflow-y-auto"></div>
                    </div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-2">Related</h3>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="Router.loadModuleView('incidents')">Incidents</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="Router.loadModuleView('services')">Services</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="Router.loadModuleView('storage')">Storage</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="Router.loadModuleView('internetslow')">Internet Health</button>
                    </div>
                </div>
            </div>
        `;
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

    statusColor(s) {
        const v = String(s || '').toLowerCase();
        if (v === 'healthy') return 'text-emerald-400';
        if (v === 'critical') return 'text-rose-400';
        if (v === 'warning') return 'text-amber-400';
        return 'text-slate-400';
    },

    scoreColor(score) {
        const n = Number(score);
        if (isNaN(n)) return 'text-slate-400';
        if (n >= 80) return 'text-emerald-400';
        if (n >= 60) return 'text-amber-400';
        return 'text-rose-400';
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    async refresh(silent) {
        const res = await API.request('health-score', 'GET', null, 15000, { silent: !!silent });
        const scoreEl = document.getElementById('health-score');
        const verdictEl = document.getElementById('health-verdict');
        const checksEl = document.getElementById('health-checks');
        if (!res.Success || !res.Data) {
            if (checksEl) checksEl.innerHTML = `<p class="text-slate-500">${this.escape(res.Message || 'Failed')}</p>`;
            return;
        }
        const score = res.Data.Score;
        if (scoreEl) {
            scoreEl.textContent = `${score}%`;
            scoreEl.className = `score-ring text-5xl font-bold mt-2 ${this.scoreColor(score)}`;
        }
        if (verdictEl) {
            const n = Number(score);
            verdictEl.textContent = n >= 85 ? 'Healthy' : n >= 70 ? 'Fair' : n >= 50 ? 'Degraded' : 'Critical';
        }
        const checks = API.asArray(res.Data.Checks);
        if (checksEl) {
            checksEl.innerHTML = checks.length ? checks.map((c) => `
                <div class="flex items-center justify-between p-2.5 rounded-lg bg-slate-950/50 border border-slate-800">
                    <div class="min-w-0">
                        <div class="text-slate-200 font-medium">${this.escape(c.Name)}</div>
                        <div class="text-slate-500 truncate">${this.escape(c.Detail || '')}</div>
                    </div>
                    <span class="${this.statusColor(c.Status)} font-semibold shrink-0 ml-2">${this.escape(c.Status)}</span>
                </div>
            `).join('') : `<p class="text-slate-500">No checks returned.</p>`;
        }
    }
};

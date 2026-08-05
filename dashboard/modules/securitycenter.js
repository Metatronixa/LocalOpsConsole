const SecurityCenterView = {
    _pollTimer: null,

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Security Center</h2>
                        <p class="text-xs text-slate-400">Host security posture, controls, and alert pressure by category.</p>
                    </div>
                    <div class="flex gap-2 flex-wrap">
                        <button type="button" class="action-btn slate text-[11px]" onclick="Router.loadModuleView('securitybaseline')">Security Baseline</button>
                        <button type="button" class="action-btn slate text-[11px]" onclick="Router.loadModuleView('security')">Security Tools</button>
                        <button type="button" class="action-btn cyan" onclick="SecurityCenterView.refresh()">Refresh</button>
                    </div>
                </div>
                <div id="sec-score-wrap" class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div class="glass-panel p-6 text-center">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider">Security Score</div>
                        <div id="sec-score" class="score-ring text-5xl font-bold text-cyan-400 mt-2">--</div>
                        <div id="sec-risk" class="text-sm text-slate-400 mt-2">—</div>
                    </div>
                    <div class="md:col-span-2 glass-panel p-4">
                        <div class="text-[11px] text-slate-500 uppercase tracking-wider mb-3">Controls</div>
                        <div id="sec-checks" class="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs max-h-80 overflow-y-auto"></div>
                    </div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Alert Heatmap</h3>
                    <div id="sec-heatmap" class="flex flex-wrap gap-4 text-xs"></div>
                </div>
                <div id="sec-baseline-snippet" class="glass-panel p-4 hidden">
                    <h3 class="text-sm font-bold text-slate-100 mb-2">Baseline snapshot</h3>
                    <div id="sec-baseline-body" class="text-xs text-slate-400"></div>
                </div>
            </div>
        `;
        // Paint first; load data without blocking navigation
        setTimeout(() => this.refresh(false), 0);
        this.startPoll();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        this._pollTimer = setInterval(() => this.refresh(true), 30000);
    },

    stopPoll() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    },

    statusColor(s) {
        const v = String(s || '').toLowerCase();
        if (v === 'healthy' || v === 'pass' || v === 'compliant') return 'text-emerald-400';
        if (v === 'critical' || v === 'fail') return 'text-rose-400';
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

    heatBars(n) {
        const c = Math.min(8, Math.max(0, Number(n) || 0));
        let html = '';
        for (let i = 0; i < 8; i++) {
            html += `<span class="inline-block w-2 h-4 rounded-sm ${i < c ? 'bg-cyan-400' : 'bg-slate-800'}"></span>`;
        }
        return html;
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    async refresh(silent) {
        const checksEl = document.getElementById('sec-checks');
        if (checksEl && !silent) {
            checksEl.innerHTML = '<div class="result-busy"><span class="spinner"></span> Loading security score…</div>';
        }
        const [scoreRes, heatRes] = await Promise.all([
            API.request('security-score', 'GET', null, 12000, { silent: !!silent }),
            API.request('heatmap', 'GET', null, 8000, { silent: true })
        ]);
        // Baseline is optional and can be slow — never block Security Center on it
        API.request('securitybaseline/diagnostics/Audit', 'GET', null, 20000, { silent: true })
            .then((baseRes) => this.renderBaselineSnippet(baseRes))
            .catch(() => { });

        const scoreEl = document.getElementById('sec-score');
        const riskEl = document.getElementById('sec-risk');
        const heatEl = document.getElementById('sec-heatmap');
        if (scoreRes.Success && scoreRes.Data) {
            const score = scoreRes.Data.Score;
            if (scoreEl) {
                scoreEl.textContent = `${score}%`;
                scoreEl.className = `score-ring text-5xl font-bold mt-2 ${this.scoreColor(score)}`;
            }
            if (riskEl) {
                const n = Number(score);
                riskEl.textContent = n >= 80 ? 'Risk: Low' : n >= 60 ? 'Risk: Moderate' : 'Risk: High';
            }
            const checks = API.asArray(scoreRes.Data.Checks);
            if (checksEl) {
                checksEl.innerHTML = checks.map((c) => `
                    <div class="p-2 rounded-lg bg-slate-950/50 border border-slate-800">
                        <div class="flex items-center justify-between gap-2">
                            <span class="text-slate-300">${this.escape(c.Name)}</span>
                            <span class="${this.statusColor(c.Status)} font-semibold">${this.escape(c.Status)}</span>
                        </div>
                        <div class="text-[11px] text-slate-500 mt-1">${this.escape(c.Detail || '')}</div>
                    </div>
                `).join('');
            }
        } else if (checksEl && !silent) {
            checksEl.innerHTML = `<p class="text-rose-400">${this.escape(scoreRes.Message || 'Security score timed out or failed')}</p>`;
        }
        if (heatRes.Success && heatRes.Data && heatEl) {
            const d = heatRes.Data;
            const rows = [
                ['Security', d.Security], ['Network', d.Network], ['Storage', d.Storage],
                ['Printing', d.Printing], ['Services', d.Services]
            ];
            heatEl.innerHTML = rows.map(([name, n]) => `
                <div>
                    <div class="text-slate-400 mb-1">${name}</div>
                    <div class="flex gap-0.5">${this.heatBars(n)}</div>
                </div>
            `).join('');
        }
    },

    renderBaselineSnippet(baseRes) {
        const snippet = document.getElementById('sec-baseline-snippet');
        const body = document.getElementById('sec-baseline-body');
        if (!baseRes || !baseRes.Success || !baseRes.Data || !snippet || !body) return;
        const d = baseRes.Data;
        const score = d.Score != null ? d.Score : (d.SecurityScore != null ? d.SecurityScore : null);
        const risk = d.RiskRating || d.Risk || '';
        if (score == null && !risk) return;
        snippet.classList.remove('hidden');
        body.innerHTML = `
            <div class="flex items-center justify-between gap-3 flex-wrap">
                <span>Baseline score: <strong class="text-slate-200">${score != null ? score : '—'}</strong>
                ${risk ? ` · Risk: <strong class="${this.statusColor(risk)}">${this.escape(risk)}</strong>` : ''}</span>
                <button type="button" class="action-btn cyan text-[11px]" onclick="Router.loadModuleView('securitybaseline')">Full baseline</button>
            </div>`;
    }
};

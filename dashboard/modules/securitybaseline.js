/* Security Baseline view — full UI wired when module exists (Phase 3) */
const SecurityBaselineView = {
    async render(container, mod) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Security Baseline</h2>
                        <p class="text-xs text-slate-400">Audit Defender, Firewall, BitLocker, TPM, Secure Boot, and related controls.</p>
                    </div>
                    <button type="button" class="action-btn cyan" onclick="SecurityBaselineView.refresh()">Run Audit</button>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div class="glass-panel p-6 text-center">
                        <div class="text-[11px] text-slate-500 uppercase">Security Score</div>
                        <div id="sb-score" class="score-ring text-5xl font-bold text-cyan-400 mt-2">--</div>
                    </div>
                    <div class="glass-panel p-6 text-center">
                        <div class="text-[11px] text-slate-500 uppercase">Risk Rating</div>
                        <div id="sb-risk" class="text-2xl font-bold text-amber-400 mt-3">--</div>
                    </div>
                    <div class="glass-panel p-6 text-center">
                        <div class="text-[11px] text-slate-500 uppercase">Compliance</div>
                        <div id="sb-compliance" class="text-2xl font-bold text-emerald-400 mt-3">--</div>
                    </div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Controls</h3>
                    <div id="sb-checks" class="space-y-2 text-xs"></div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Recommendations</h3>
                    <div id="sb-recs" class="space-y-2 text-xs text-slate-300"></div>
                </div>
            </div>`;
        await this.refresh();
    },

    statusColor(s) {
        const v = String(s || '').toLowerCase();
        if (v === 'pass' || v === 'healthy' || v === 'compliant') return 'text-emerald-400';
        if (v === 'fail' || v === 'critical') return 'text-rose-400';
        if (v === 'warning' || v === 'partial') return 'text-amber-400';
        return 'text-slate-400';
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    async refresh() {
        const checksEl = document.getElementById('sb-checks');
        const recsEl = document.getElementById('sb-recs');
        const res = await API.request('securitybaseline/diagnostics/Audit', 'GET', null, 60000, { silent: false });
        if (!res.Success || !res.Data) {
            // Fallback: try alternate path or show message
            const alt = await API.request('security/diagnostics/SecurityBaseline', 'GET', null, 60000, { silent: true });
            if (!alt.Success || !alt.Data) {
                if (checksEl) checksEl.innerHTML = `<p class="text-slate-500">${this.escape(res.Message || 'Security Baseline module not loaded yet.')}</p>`;
                return;
            }
            return this.renderData(alt.Data);
        }
        this.renderData(res.Data);
    },

    renderData(d) {
        const scoreEl = document.getElementById('sb-score');
        const riskEl = document.getElementById('sb-risk');
        const compEl = document.getElementById('sb-compliance');
        const checksEl = document.getElementById('sb-checks');
        const recsEl = document.getElementById('sb-recs');
        if (scoreEl) scoreEl.textContent = d.Score != null ? `${d.Score}%` : '--';
        if (riskEl) {
            riskEl.textContent = d.RiskRating || d.Risk || '--';
            riskEl.className = `text-2xl font-bold mt-3 ${this.statusColor(d.RiskRating || d.Risk)}`;
        }
        if (compEl) {
            const c = d.Compliance;
            if (c && typeof c === 'object') {
                compEl.textContent = `${c.Passed || 0}/${c.Total || 0}`;
            } else {
                compEl.textContent = c != null ? String(c) : '--';
            }
        }
        const checks = API.asArray(d.Checks || d.Controls || d.Items);
        if (checksEl) {
            checksEl.innerHTML = checks.length ? checks.map((c) => `
                <div class="flex items-center justify-between p-2.5 rounded-lg bg-slate-950/50 border border-slate-800">
                    <div>
                        <div class="text-slate-200 font-medium">${this.escape(c.Name || c.Control)}</div>
                        <div class="text-slate-500">${this.escape(c.Detail || c.Description || '')}</div>
                    </div>
                    <span class="${this.statusColor(c.Status || c.Result)} font-semibold">${this.escape(c.Status || c.Result || '')}</span>
                </div>
            `).join('') : `<p class="text-slate-500">No controls returned.</p>`;
        }
        const recs = API.asArray(d.Recommendations);
        if (recsEl) {
            recsEl.innerHTML = recs.length
                ? `<ul class="list-disc list-inside space-y-1">${recs.map((r) =>
                    `<li>${this.escape(typeof r === 'string' ? r : (r.Title || r.Detail || ''))}</li>`).join('')}</ul>`
                : `<p class="text-slate-500">No recommendations.</p>`;
        }
    }
};

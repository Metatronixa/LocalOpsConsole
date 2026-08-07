/* Security Baseline — This PC or fleet agent (AuditSecurityBaseline) */
const SecurityBaselineView = {
    _pendingAgent: null,

    /** Deep-link from Computers drawer before/while navigating. */
    openForAgent(agentId) {
        this._pendingAgent = agentId ? String(agentId) : null;
        if (typeof FleetTarget !== 'undefined' && agentId) {
            FleetTarget.openForAgent(agentId);
        }
    },

    async render(container, mod) {
        if (typeof FleetTarget !== 'undefined') {
            FleetTarget.stopPoll();
            FleetTarget.loadPersisted();
            if (this._pendingAgent) {
                FleetTarget.openForAgent(this._pendingAgent);
                this._pendingAgent = null;
            }
            await FleetTarget.loadAgents();
        }

        const strip = (typeof FleetTarget !== 'undefined')
            ? FleetTarget.renderStripHtml('sb-target-select')
            : '';

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Security Baseline</h2>
                        <p class="text-xs text-slate-400">Audit Defender, Firewall, and related controls on This PC or a fleet agent. Apply hardening stays on Computers.</p>
                    </div>
                    <button type="button" class="action-btn cyan" onclick="SecurityBaselineView.refresh()">Run Audit</button>
                </div>

                ${strip}

                <div id="sb-job-status" class="startup-job-chip hidden" role="status" aria-live="polite"></div>

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

        if (typeof FleetTarget !== 'undefined') {
            FleetTarget.bind('sb-target-select', () => this.onTargetChanged());
            this.onTargetChanged();
        }
        await this.refresh();
    },

    onTargetChanged() {
        if (typeof FleetTarget !== 'undefined') FleetTarget.stopPoll();
        this.clearJobStatus();
    },

    setJobStatus(state) {
        const el = document.getElementById('sb-job-status');
        if (!el) return;
        if (!state) {
            el.className = 'startup-job-chip hidden';
            el.innerHTML = '';
            return;
        }
        const st = String(state.Status || '');
        let cls = 'startup-job-chip';
        if (st === 'Completed') cls += ' is-ok';
        else if (st === 'Failed' || st === 'Timeout' || st === 'Cancelled') cls += ' is-err';
        else if (st === 'Running' || st === 'Pending' || st === 'Queuing') cls += ' is-busy';
        el.className = cls;
        const spin = (st === 'Running' || st === 'Pending' || st === 'Queuing')
            ? '<span class="spinner"></span> '
            : '';
        el.innerHTML = `${spin}<span class="badge badge-muted">${this.escape(st)}</span> <span>${this.escape(state.Detail || '')}</span>`;
    },

    clearJobStatus() {
        this.setJobStatus(null);
    },

    statusColor(s) {
        const v = String(s || '').toLowerCase();
        if (v === 'pass' || v === 'healthy' || v === 'compliant' || v === 'low') return 'text-emerald-400';
        if (v === 'fail' || v === 'critical' || v === 'high') return 'text-rose-400';
        if (v === 'warning' || v === 'partial' || v === 'medium') return 'text-amber-400';
        return 'text-slate-400';
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    /** Map agent AuditSecurityBaseline payload to page shape. */
    normalizeAuditData(d) {
        if (!d || typeof d !== 'object') return d;
        const out = Object.assign({}, d);
        const pass = Number(d.Pass != null ? d.Pass : 0);
        const fail = Number(d.Fail != null ? d.Fail : 0);
        const warn = Number(d.Warning != null ? d.Warning : 0);
        const unk = Number(d.Unknown != null ? d.Unknown : 0);
        const checks = API.asArray(d.Checks || d.Controls || d.Items);
        const total = checks.length || (pass + fail + warn + unk);

        if (out.Score == null && total > 0) {
            out.Score = Math.round(100 * pass / total);
        }
        if (!out.RiskRating && !out.Risk) {
            if (fail > 0) out.RiskRating = 'High';
            else if (warn > 0) out.RiskRating = 'Medium';
            else if (total > 0) out.RiskRating = 'Low';
        }
        if (!out.Compliance || typeof out.Compliance !== 'object') {
            out.Compliance = { Passed: pass, Total: total || checks.length };
        }
        if (!API.asArray(out.Recommendations).length) {
            const recs = [];
            checks.forEach((c) => {
                const st = String(c.Status || c.Result || '').toLowerCase();
                if (st === 'fail' || st === 'warning') {
                    recs.push(`${c.Name || c.Control || 'Control'}: ${c.Detail || c.Description || st}`);
                }
            });
            if (recs.length) out.Recommendations = recs;
        }
        return out;
    },

    async refresh() {
        const checksEl = document.getElementById('sb-checks');
        const thisPc = typeof FleetTarget === 'undefined' || FleetTarget.isThisPc();
        const label = thisPc ? 'This PC' : FleetTarget.getSelectedLabel();
        LiveConsole.log(`securitybaseline / Audit → ${label}`, 'INFO');

        if (thisPc) {
            this.clearJobStatus();
            if (checksEl) checksEl.innerHTML = '<p class="text-slate-500"><span class="spinner"></span> Running audit on This PC…</p>';
            const res = await API.request('securitybaseline/diagnostics/Audit', 'GET', null, 60000, { silent: false });
            if (!res.Success || !res.Data) {
                const alt = await API.request('security/diagnostics/SecurityBaseline', 'GET', null, 60000, { silent: true });
                if (!alt.Success || !alt.Data) {
                    if (checksEl) checksEl.innerHTML = `<p class="text-slate-500">${this.escape(res.Message || 'Security Baseline module not loaded yet.')}</p>`;
                    return;
                }
                return this.renderData(this.normalizeAuditData(alt.Data));
            }
            this.renderData(this.normalizeAuditData(res.Data));
            return;
        }

        const agent = FleetTarget.getSelectedAgent();
        const agentId = FleetTarget.getSelectedId();
        if (typeof FleetView !== 'undefined' && agent) {
            const ver = String(agent.AgentVersion || '');
            if (ver && !FleetView.supportsCommand(ver, 'AuditSecurityBaseline')) {
                const min = FleetView.commandMinVersion('AuditSecurityBaseline');
                const msg = `Audit requires agent ${min}+ (this PC: ${ver || '?'}). Update the agent from Computers.`;
                LiveConsole.log(msg, 'WARN');
                this.setJobStatus({ Status: 'Failed', Detail: msg });
                if (checksEl) checksEl.innerHTML = `<p class="text-amber-400">${this.escape(msg)}</p>`;
                return;
            }
        }

        if (checksEl) checksEl.innerHTML = `<p class="text-slate-500"><span class="spinner"></span> Queued audit on ${this.escape(label)}…</p>`;
        const result = await FleetTarget.queueAndWait(agentId, 'AuditSecurityBaseline', {}, {
            onStatus: (s) => this.setJobStatus(s)
        });

        if (result.Success && result.Data) {
            LiveConsole.log(result.Message || 'OK', 'SUCCESS');
            this.renderData(this.normalizeAuditData(result.Data));
        } else {
            LiveConsole.log(result.Message || 'Failed', 'ERROR');
            if (checksEl) {
                checksEl.innerHTML = `<p class="text-rose-400">${this.escape(result.Message || 'Audit failed')}</p>`;
            }
        }
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

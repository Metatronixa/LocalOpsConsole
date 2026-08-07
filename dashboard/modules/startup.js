const StartupView = {
    _mod: null,
    _pendingAgent: null,

    /** Deep-link from Computers drawer before/while navigating. */
    openForAgent(agentId) {
        this._pendingAgent = agentId ? String(agentId) : null;
        if (typeof FleetTarget !== 'undefined' && agentId) {
            FleetTarget.openForAgent(agentId);
        }
    },

    async render(container, mod) {
        this._mod = mod || { id: 'startup', name: 'Startup', version: '1.0.0' };
        if (typeof FleetTarget !== 'undefined') {
            FleetTarget.stopPoll();
            FleetTarget.loadPersisted();
            if (this._pendingAgent) {
                FleetTarget.openForAgent(this._pendingAgent);
                this._pendingAgent = null;
            }
            await FleetTarget.loadAgents();
        }

        const isAdmin = window.__LOC_ADMIN === true;
        const strip = (typeof FleetTarget !== 'undefined')
            ? FleetTarget.renderStripHtml('startup-target-select')
            : '';

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">${this.escape(this._mod.name || 'Startup')}</h2>
                        <p class="text-xs text-slate-400">Startup apps and scheduled tasks on This PC or a fleet agent. Status stays on this page while remote commands run.</p>
                    </div>
                    <span class="badge badge-muted">v${this.escape(this._mod.version || '1.0.0')}</span>
                </div>

                ${strip}

                <div id="startup-job-status" class="startup-job-chip hidden" role="status" aria-live="polite"></div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="glass-panel p-5">
                        <div class="section-title">Diagnostics</div>
                        <div class="flex flex-wrap gap-2">
                            <button type="button" class="action-btn cyan" onclick="StartupView.runDiag('GetStartupApps')">Startup apps</button>
                            <button type="button" class="action-btn cyan" onclick="StartupView.runDiag('GetScheduledTasks')">Scheduled tasks</button>
                        </div>
                    </div>
                    <div class="glass-panel p-5">
                        <div class="section-title">Remediation</div>
                        <div class="flex flex-wrap gap-2">
                            <button type="button" class="action-btn amber" id="startup-remediate-btn"
                                ${isAdmin ? '' : 'disabled title="Requires Administrator"'}
                                onclick="StartupView.runLocalAction('SetStartupEnabled')">SetStartupEnabled${isAdmin ? '' : ' 🔒'}</button>
                        </div>
                        <p class="text-[11px] text-slate-500 mt-2 mb-0" id="startup-remediate-note">Remediation runs on This PC only.</p>
                    </div>
                </div>

                <div id="startup-result" class="result-panel text-slate-500">Select a target, then run Startup apps or Scheduled tasks.</div>
            </div>
        `;

        if (typeof FleetTarget !== 'undefined') {
            FleetTarget.bind('startup-target-select', () => this.onTargetChanged());
            this.onTargetChanged();
        }
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    onTargetChanged() {
        if (typeof FleetTarget !== 'undefined') FleetTarget.stopPoll();
        const note = document.getElementById('startup-remediate-note');
        const btn = document.getElementById('startup-remediate-btn');
        const thisPc = typeof FleetTarget === 'undefined' || FleetTarget.isThisPc();
        if (note) {
            note.textContent = thisPc
                ? 'Remediation runs on This PC only.'
                : 'Remediation is local-only — switch to This PC to enable/disable startup items.';
        }
        if (btn) {
            const isAdmin = window.__LOC_ADMIN === true;
            btn.disabled = !thisPc || !isAdmin;
            if (!thisPc) btn.title = 'Switch target to This PC for remediation';
            else if (!isAdmin) btn.title = 'Requires Administrator';
            else btn.removeAttribute('title');
        }
        this.clearJobStatus();
    },

    setJobStatus(state) {
        const el = document.getElementById('startup-job-status');
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

    setBusy(message) {
        const el = document.getElementById('startup-result');
        if (!el) return;
        el.classList.remove('text-slate-500');
        const esc = (typeof ResultRenderer !== 'undefined') ? ResultRenderer.escape(message) : this.escape(message);
        el.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${esc}</div>`;
    },

    showResult(message, data) {
        const el = document.getElementById('startup-result');
        if (!el) return;
        if (typeof ResultRenderer !== 'undefined') {
            ResultRenderer.mount(el, message, data);
        } else {
            el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
        }
    },

    async runDiag(name) {
        const thisPc = typeof FleetTarget === 'undefined' || FleetTarget.isThisPc();
        LiveConsole.log(`startup / ${name} → ${thisPc ? 'This PC' : FleetTarget.getSelectedLabel()}`, 'INFO');

        if (thisPc) {
            this.clearJobStatus();
            this.setBusy(`Running ${name} on This PC…`);
            const res = await API.diagnostic('startup', name);
            if (res.Success) {
                LiveConsole.log(res.Message || 'OK', 'SUCCESS');
                this.showResult(res.Message, res.Data && res.Data.Output && Object.keys(res.Data).length <= 3 ? res.Data.Output : res.Data);
            } else {
                LiveConsole.log(res.Message || 'Failed', 'ERROR', res.Data);
                this.showResult(res.Message || 'Failed', res.Data);
            }
            return;
        }

        const agent = FleetTarget.getSelectedAgent();
        const agentId = FleetTarget.getSelectedId();
        if (typeof FleetView !== 'undefined' && agent) {
            const ver = String(agent.AgentVersion || '');
            if (ver && !FleetView.supportsCommand(ver, name)) {
                const min = FleetView.commandMinVersion(name);
                const msg = `${name} requires agent ${min}+ (this PC: ${ver || '?'}). Update the agent from Computers.`;
                LiveConsole.log(msg, 'WARN');
                this.setJobStatus({ Status: 'Failed', Detail: msg });
                this.showResult(msg, null);
                return;
            }
        }

        this.setBusy(`Queued ${name} on ${FleetTarget.getSelectedLabel()}…`);
        const result = await FleetTarget.queueAndWait(agentId, name, {}, {
            onStatus: (s) => {
                this.setJobStatus(s);
                if (s.Status === 'Pending' || s.Status === 'Running' || s.Status === 'Queuing') {
                    this.setBusy(s.Detail || `${s.Status}…`);
                }
            }
        });

        if (result.Success) {
            LiveConsole.log(result.Message || 'OK', 'SUCCESS');
            this.showResult(result.Message, result.Data);
        } else {
            LiveConsole.log(result.Message || 'Failed', 'ERROR');
            this.showResult(result.Message || 'Failed', result.Data);
        }
    },

    async runLocalAction(name) {
        if (typeof FleetTarget !== 'undefined' && !FleetTarget.isThisPc()) {
            alert('Switch target to This PC to run remediation.');
            return;
        }
        if (!confirm(`Run action ${name} on This PC?`)) return;
        LiveConsole.log(`startup / actions / ${name}`, 'INFO');
        this.setBusy(`Running ${name}…`);
        const res = await API.action('startup', name, {});
        if (res.Success) {
            LiveConsole.log(res.Message || 'OK', 'SUCCESS');
            this.showResult(res.Message, res.Data);
        } else {
            LiveConsole.log(res.Message || 'Failed', 'ERROR', res.Data);
            this.showResult(res.Message || 'Failed', res.Data);
        }
    }
};

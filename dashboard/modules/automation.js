const AutomationView = {
    _rulesById: {},
    _agents: [],
    _runStatus: {},

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Automation</h2>
                        <p class="text-xs text-slate-400">Central hub: enable playbooks, set scope (This PC / Fleet / Both), then Run now. Event Intel auto remediates This PC when scope includes local.</p>
                    </div>
                    <button type="button" class="action-btn cyan" onclick="AutomationView.refresh()">Refresh</button>
                </div>
                <div id="auto-summary" class="grid grid-cols-2 md:grid-cols-4 gap-3"></div>
                <div id="auto-run-status" class="startup-job-chip hidden" role="status" aria-live="polite"></div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Playbooks</h3>
                    <div id="auto-rules" class="space-y-2 text-xs"></div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Recent automation history</h3>
                    <div id="auto-history" class="space-y-2 text-xs max-h-64 overflow-y-auto"></div>
                </div>
                <p class="text-[11px] text-slate-500">Toggles and scope are stored locally. Fleet Run now queues agent commands (agent 2.3.0+ with updated script). Remote Event Log auto-remediation is Hub v2. Risk: Safe · Careful · Notify.</p>
            </div>`;
        await this.refresh();
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    riskBadge(risk) {
        const r = String(risk || '').trim();
        if (!r) return '';
        const cls = r === 'Safe' ? 'badge-ok' : (r === 'Careful' ? 'badge-warn' : 'badge-muted');
        return `<span class="badge ${cls}" title="Playbook risk">${this.escape(r)}</span>`;
    },

    confirmMessage(rule) {
        const risk = String((rule && rule.Risk) || '').trim() || 'Unknown';
        const title = (rule && (rule.Title || rule.RuleId)) || 'this playbook';
        const action = (rule && rule.Action) || 'automation';
        const scope = (rule && rule.Scope) || 'local';
        let impact = 'It may run automated remediation when the rule fires on This PC.';
        if (risk === 'Careful') {
            if (action === 'clear-print-queue') impact = 'It may clear print jobs when the rule fires.';
            else if (action === 'network-soft-repair') impact = 'It may flush DNS and renew DHCP (brief network blip).';
            else if (action === 'restart-update-stack') impact = 'It may restart Windows Update / BITS services.';
            else impact = 'It may restart services or change system state.';
        } else if (risk === 'Safe') {
            impact = 'It runs a low-impact action (cleanup or snapshot).';
        } else if (risk === 'Notify') {
            impact = 'It records an acknowledgement on the incident timeline only (no remediation).';
        }
        const blast = (scope === 'fleet' || scope === 'both')
            ? `\nScope is "${scope}" — Run now can affect fleet PCs.`
            : '';
        return `Enable "${title}"?\n\nRisk: ${risk}\n${impact}${blast}\n\nRuns are audited.`;
    },

    async loadAgents() {
        try {
            const res = await API.request('fleet/agents', 'GET', null, 12000, { silent: true });
            this._agents = res.Success ? API.asArray(res.Data).filter((a) => a && !a.Revoked) : [];
        } catch (e) {
            this._agents = [];
        }
    },

    setRunStatus(html, kind) {
        const el = document.getElementById('auto-run-status');
        if (!el) return;
        if (!html) {
            el.className = 'startup-job-chip hidden';
            el.innerHTML = '';
            return;
        }
        let cls = 'startup-job-chip';
        if (kind === 'ok') cls += ' is-ok';
        else if (kind === 'err') cls += ' is-err';
        else cls += ' is-busy';
        el.className = cls;
        el.innerHTML = html;
    },

    agentOptionsHtml(selectedIds) {
        const sel = new Set(API.asArray(selectedIds).map(String));
        const online = this._agents.filter((a) => a.Online);
        if (!online.length) {
            return '<option value="" disabled>No online agents</option>';
        }
        return online.map((a) => {
            const id = String(a.Id);
            const label = this.escape(a.ComputerName || a.Hostname || id);
            return `<option value="${this.escape(id)}" ${sel.has(id) ? 'selected' : ''}>${label}</option>`;
        }).join('');
    },

    async refresh() {
        await this.loadAgents();
        const res = await API.request('automation/status', 'GET', null, 12000, { silent: false });
        const summaryEl = document.getElementById('auto-summary');
        const rulesEl = document.getElementById('auto-rules');
        const histEl = document.getElementById('auto-history');
        if (!res.Success || !res.Data) {
            if (rulesEl) rulesEl.innerHTML = `<p class="text-slate-500">${this.escape(res.Message || 'Failed')}</p>`;
            return;
        }
        const d = res.Data;
        const handlers = API.asArray(d.Handlers);
        const rules = API.asArray(d.Rules).slice().sort((a, b) => {
            const ae = a.Enabled ? 0 : 1;
            const be = b.Enabled ? 0 : 1;
            if (ae !== be) return ae - be;
            const cat = String(a.Category || '').localeCompare(String(b.Category || ''), undefined, { sensitivity: 'base' });
            if (cat !== 0) return cat;
            return String(a.Title || a.RuleId || '').localeCompare(String(b.Title || b.RuleId || ''), undefined, { sensitivity: 'base' });
        });
        const history = API.asArray(d.History);
        this._rulesById = {};
        rules.forEach((r) => { if (r && r.RuleId) this._rulesById[r.RuleId] = r; });
        if (summaryEl) {
            summaryEl.innerHTML = [
                ['Handlers', handlers.length, 'text-cyan-400'],
                ['Playbooks', rules.length, 'text-slate-200'],
                ['Enabled', d.EnabledCount || 0, 'text-emerald-400'],
                ['History', history.length, 'text-amber-400']
            ].map(([l, v, c]) => `
                <div class="glass-panel p-3 text-center">
                    <div class="text-[11px] text-slate-500 uppercase">${l}</div>
                    <div class="text-2xl font-bold ${c} mt-1">${v}</div>
                </div>`).join('');
        }
        if (rulesEl) {
            if (!rules.length) {
                rulesEl.innerHTML = `<p class="text-slate-500">No rules define automation blocks yet.</p>`;
            } else {
                rulesEl.innerHTML = rules.map((r) => {
                    const id = this.escape(r.RuleId || '');
                    const on = !!r.Enabled;
                    const scope = String(r.Scope || 'local');
                    const showAgents = scope === 'fleet' || scope === 'both';
                    const fleetHint = r.SupportsFleet
                        ? `fleet <span class="text-slate-300">${this.escape(r.FleetCommand || '')}</span>`
                        : '<span class="text-slate-500">no fleet map</span>';
                    return `
                    <div class="p-3 rounded-lg border border-slate-800 bg-slate-950/40 space-y-2">
                        <div class="flex items-start justify-between gap-3">
                            <div class="min-w-0">
                                <div class="font-semibold text-slate-100 flex items-center gap-2 flex-wrap">
                                    <span>${this.escape(r.Title || r.RuleId)}</span>
                                    ${this.riskBadge(r.Risk)}
                                </div>
                                <div class="text-slate-500 mt-1">${this.escape(r.Category || '')} · action <span class="text-cyan-400">${this.escape(r.Action)}</span>
                                    ${r.Service ? ` · service <span class="text-slate-300">${this.escape(r.Service)}</span>` : ''}
                                    · ${fleetHint}</div>
                                ${r.Description ? `<div class="text-slate-400 mt-1">${this.escape(r.Description)}</div>` : ''}
                            </div>
                            <label class="flex flex-col items-end gap-1 shrink-0 cursor-pointer select-none" title="Enable or disable this playbook">
                                <span class="badge ${on ? 'badge-ok' : 'badge-muted'}">${on ? 'ENABLED' : 'OFF'}</span>
                                <span class="loc-switch">
                                    <input type="checkbox" data-rule-id="${id}" ${on ? 'checked' : ''}
                                           onchange="AutomationView.toggle('${id}', this.checked, this)" />
                                    <span class="loc-switch-track"></span>
                                </span>
                            </label>
                        </div>
                        <div class="flex flex-wrap items-end gap-2 pt-1 border-t border-slate-800/80">
                            <div>
                                <label class="text-[10px] text-slate-500 block mb-0.5">Scope</label>
                                <select class="px-2 py-1 rounded-lg bg-slate-950 border border-slate-700 text-[11px] text-slate-200"
                                        onchange="AutomationView.changeScope('${id}', this.value)">
                                    <option value="local" ${scope === 'local' ? 'selected' : ''}>This PC</option>
                                    <option value="fleet" ${scope === 'fleet' ? 'selected' : ''}>Fleet</option>
                                    <option value="both" ${scope === 'both' ? 'selected' : ''}>Both</option>
                                </select>
                            </div>
                            <div class="${showAgents ? '' : 'hidden'}" id="auto-agents-${id}" style="min-width:10rem;max-width:16rem;">
                                <label class="text-[10px] text-slate-500 block mb-0.5">Fleet agents (empty = all online)</label>
                                <select multiple size="3" class="w-full px-2 py-1 rounded-lg bg-slate-950 border border-slate-700 text-[11px] font-mono text-slate-200"
                                        onchange="AutomationView.changeAgents('${id}', this)">
                                    ${this.agentOptionsHtml(r.AgentIds)}
                                </select>
                            </div>
                            <button type="button" class="action-btn cyan text-[11px] ml-auto"
                                    onclick="AutomationView.runNow('${id}')"
                                    title="Run playbook on scoped targets now">Run now</button>
                        </div>
                    </div>`;
                }).join('');
            }
        }
        if (histEl) {
            if (!history.length) {
                histEl.innerHTML = `<p class="text-slate-500">No automation runs logged yet.</p>`;
            } else {
                histEl.innerHTML = history.slice().reverse().map((h) => `
                    <div class="border-l-2 border-cyan-500/40 pl-3 py-1">
                        <div class="text-slate-500 text-[10px]">${this.escape(h.Timestamp || h.ts || '')}</div>
                        <div class="text-slate-200">${this.escape(h.Action)} — ${this.escape(h.Detail || h.Message || '')}</div>
                    </div>`).join('');
            }
        }
    },

    async savePrefs(ruleId, patch) {
        const rule = (this._rulesById && this._rulesById[ruleId]) || {};
        const body = {
            enabled: patch.enabled != null ? !!patch.enabled : !!rule.Enabled,
            scope: patch.scope != null ? patch.scope : (rule.Scope || 'local'),
            agentIds: patch.agentIds != null ? patch.agentIds : API.asArray(rule.AgentIds)
        };
        return API.request(
            `automation/playbooks/${encodeURIComponent(ruleId)}`,
            'POST',
            body,
            10000
        );
    },

    async toggle(ruleId, enabled, el) {
        if (!ruleId) return;
        if (enabled) {
            const rule = (this._rulesById && this._rulesById[ruleId]) || { RuleId: ruleId };
            const ok = confirm(this.confirmMessage(rule));
            if (!ok) {
                if (el) el.checked = false;
                return;
            }
        }
        const res = await this.savePrefs(ruleId, { enabled: !!enabled });
        if (!res.Success) {
            if (el) el.checked = !enabled;
            LiveConsole.log(res.Message || 'Playbook toggle failed', 'ERROR');
            alert(res.Message || 'Failed to update playbook');
            return;
        }
        LiveConsole.log(res.Message || `Playbook ${ruleId} updated`, 'SUCCESS');
        await this.refresh();
    },

    async changeScope(ruleId, scope) {
        const res = await this.savePrefs(ruleId, { scope: scope || 'local' });
        if (!res.Success) {
            LiveConsole.log(res.Message || 'Scope update failed', 'ERROR');
            alert(res.Message || 'Failed to update scope');
        }
        await this.refresh();
    },

    async changeAgents(ruleId, selectEl) {
        const ids = selectEl ? [].map.call(selectEl.selectedOptions, (o) => o.value).filter(Boolean) : [];
        const res = await this.savePrefs(ruleId, { agentIds: ids });
        if (!res.Success) {
            LiveConsole.log(res.Message || 'Agent list update failed', 'ERROR');
            return;
        }
        if (this._rulesById[ruleId]) this._rulesById[ruleId].AgentIds = ids;
    },

    async runNow(ruleId) {
        const rule = (this._rulesById && this._rulesById[ruleId]) || { RuleId: ruleId };
        const scope = rule.Scope || 'local';
        const title = rule.Title || ruleId;
        let msg = `Run "${title}" now on scope "${scope}"?`;
        if (scope === 'fleet' || scope === 'both') {
            msg += '\n\nFleet targets will queue agent commands (one Running job blocks that PC’s queue).';
        }
        if (!confirm(msg)) return;

        this.setRunStatus(`<span class="spinner"></span> <span class="badge badge-muted">Queuing</span> <span>Run now: ${this.escape(title)}…</span>`, 'busy');
        LiveConsole.log(`Playbook RunNow ${ruleId}`, 'INFO');

        const body = {};
        const wrap = document.getElementById('auto-agents-' + ruleId);
        const selectEl = wrap ? wrap.querySelector('select') : null;
        if (selectEl && (scope === 'fleet' || scope === 'both')) {
            const ids = [].map.call(selectEl.selectedOptions, (o) => o.value).filter(Boolean);
            if (ids.length) body.agentIds = ids;
        }

        const res = await API.request(
            `automation/playbooks/${encodeURIComponent(ruleId)}/run`,
            'POST',
            body,
            60000
        );

        if (!res.Success || !res.Data) {
            this.setRunStatus(`<span class="badge badge-warn">Failed</span> <span>${this.escape(res.Message || 'Run failed')}</span>`, 'err');
            LiveConsole.log(res.Message || 'Run failed', 'ERROR');
            return;
        }

        const targets = API.asArray(res.Data.Targets);
        const lines = targets.map((t) => {
            const who = t.Target === 'local' ? 'This PC' : (t.AgentId || 'fleet');
            return `${who}: ${t.Status}${t.Message ? ' — ' + t.Message : ''}`;
        });
        const anyFail = targets.some((t) => !t.Success);
        const anyPending = targets.some((t) => t.Status === 'Pending' || t.Status === 'Running');

        this.setRunStatus(
            `<span class="badge ${anyFail ? 'badge-warn' : 'badge-ok'}">${anyFail ? 'Partial' : (anyPending ? 'Queued' : 'Done')}</span> <span>${this.escape(lines.join(' · ') || res.Message)}</span>`,
            anyFail ? 'err' : (anyPending ? 'busy' : 'ok')
        );
        LiveConsole.log(res.Message || 'Run now complete', anyFail ? 'WARN' : 'SUCCESS', res.Data);

        // Poll fleet targets sequentially for sticky updates
        const fleetTargets = targets.filter((t) => t.AgentId && t.CommandId && t.Success);
        if (fleetTargets.length && typeof FleetTarget !== 'undefined') {
            await this.pollFleetTargets(fleetTargets, title);
        }
        await this.refresh();
    },

    async pollFleetTargets(fleetTargets, title) {
        for (const t of fleetTargets) {
            this.setRunStatus(
                `<span class="spinner"></span> <span class="badge badge-muted">Waiting</span> <span>${this.escape(title)} on ${this.escape(t.AgentId)}…</span>`,
                'busy'
            );
            // Lightweight poll via agent detail
            const started = Date.now();
            const timeoutMs = 180000;
            while (Date.now() - started < timeoutMs) {
                await new Promise((r) => setTimeout(r, 2000));
                try {
                    const detail = await API.request(`fleet/agents/${encodeURIComponent(t.AgentId)}`, 'GET', null, 15000, { silent: true });
                    const cmds = detail.Success && detail.Data ? API.asArray(detail.Data.Commands || detail.Data.commands) : [];
                    const cmd = cmds.find((c) => String(c.Id) === String(t.CommandId));
                    if (!cmd) continue;
                    const st = String(cmd.Status || '');
                    if (st === 'Completed' || st === 'Failed' || st === 'Cancelled') {
                        const msg = (cmd.Result && cmd.Result.Message) || st;
                        this.setRunStatus(
                            `<span class="badge ${st === 'Completed' ? 'badge-ok' : 'badge-warn'}">${this.escape(st)}</span> <span>${this.escape(t.AgentId)}: ${this.escape(msg)}</span>`,
                            st === 'Completed' ? 'ok' : 'err'
                        );
                        break;
                    }
                    this.setRunStatus(
                        `<span class="spinner"></span> <span class="badge badge-muted">${this.escape(st)}</span> <span>${this.escape(t.AgentId)} · ${this.escape(t.Type || '')}</span>`,
                        'busy'
                    );
                } catch (e) { /* keep waiting */ }
            }
        }
    }
};

const AutomationView = {
    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Automation</h2>
                        <p class="text-xs text-slate-400">Opt-in playbooks defined in rules. Every run is audited on the incident timeline.</p>
                    </div>
                    <button type="button" class="action-btn cyan" onclick="AutomationView.refresh()">Refresh</button>
                </div>
                <div id="auto-summary" class="grid grid-cols-2 md:grid-cols-4 gap-3"></div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Playbooks</h3>
                    <div id="auto-rules" class="space-y-2 text-xs"></div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Recent automation history</h3>
                    <div id="auto-history" class="space-y-2 text-xs max-h-64 overflow-y-auto"></div>
                </div>
                <p class="text-[11px] text-slate-500">To enable a playbook, set <code class="text-cyan-400">automation.enabled: true</code> on the rule JSON under <code class="text-slate-400">rules/</code>, then restart the console.</p>
            </div>`;
        await this.refresh();
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    async refresh() {
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
        const rules = API.asArray(d.Rules);
        const history = API.asArray(d.History);
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
                rulesEl.innerHTML = rules.map((r) => `
                    <div class="p-3 rounded-lg border border-slate-800 bg-slate-950/40 flex items-start justify-between gap-3">
                        <div class="min-w-0">
                            <div class="font-semibold text-slate-100">${this.escape(r.Title || r.RuleId)}</div>
                            <div class="text-slate-500 mt-1">${this.escape(r.Category || '')} · action <span class="text-cyan-400">${this.escape(r.Action)}</span>
                                ${r.Service ? ` · service <span class="text-slate-300">${this.escape(r.Service)}</span>` : ''}</div>
                            ${r.Description ? `<div class="text-slate-400 mt-1">${this.escape(r.Description)}</div>` : ''}
                        </div>
                        <span class="badge ${r.Enabled ? 'badge-ok' : 'badge-muted'} shrink-0">${r.Enabled ? 'ENABLED' : 'OPT-IN'}</span>
                    </div>`).join('');
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
    }
};

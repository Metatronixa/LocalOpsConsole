const IncidentsView = {
    _pollTimer: null,
    _selected: null,
    _filter: 'all',

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Incident Center</h2>
                        <p class="text-xs text-slate-400">Correlated incidents with severity, root cause timeline, and remediation actions.</p>
                    </div>
                    <div class="flex items-center gap-2 flex-wrap">
                        <div class="flex gap-1" id="inc-filters">
                            <button type="button" data-filter="all" class="sev-chip active" onclick="IncidentsView.setFilter('all')">All</button>
                            <button type="button" data-filter="Critical" class="sev-chip sev-critical" onclick="IncidentsView.setFilter('Critical')">Critical</button>
                            <button type="button" data-filter="Warning" class="sev-chip sev-warning" onclick="IncidentsView.setFilter('Warning')">Warning</button>
                            <button type="button" data-filter="resolved" class="sev-chip" onclick="IncidentsView.setFilter('resolved')">Resolved</button>
                        </div>
                        <button type="button" class="action-btn cyan" onclick="IncidentsView.refresh()">Refresh</button>
                    </div>
                </div>
                <div id="inc-summary" class="grid grid-cols-2 md:grid-cols-4 gap-3"></div>
                <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
                    <div class="xl:col-span-2 glass-panel p-4">
                        <h3 class="text-sm font-bold text-slate-100 mb-3">Incidents</h3>
                        <div id="inc-list" class="space-y-2 text-xs"></div>
                    </div>
                    <div id="inc-detail" class="glass-panel p-4 text-xs">
                        <p class="text-slate-500">Select an incident to view timeline and remediation.</p>
                    </div>
                </div>
                <div class="glass-panel p-4">
                    <h3 class="text-sm font-bold text-slate-100 mb-3">Alert Heatmap</h3>
                    <div id="inc-heatmap" class="flex flex-wrap gap-4 text-xs"></div>
                </div>
            </div>
        `;
        await this.refresh();
        this.startPoll();
    },

    setFilter(f) {
        this._filter = f;
        document.querySelectorAll('#inc-filters .sev-chip').forEach((btn) => {
            btn.classList.toggle('active', btn.dataset.filter === f);
        });
        this.refresh();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        this._pollTimer = setInterval(() => this.refresh(true), 15000);
    },

    stopPoll() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    sevClass(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return 'text-rose-400';
        if (s === 'warning') return 'text-amber-400';
        return 'text-sky-400';
    },

    heatBars(n) {
        const c = Math.min(8, Math.max(0, Number(n) || 0));
        let html = '';
        for (let i = 0; i < 8; i++) {
            html += `<span class="inline-block w-2 h-4 rounded-sm ${i < c ? 'bg-cyan-400' : 'bg-slate-800'}"></span>`;
        }
        return html;
    },

    async refresh(silent) {
        const statusQ = this._filter === 'resolved' ? 'resolved' : 'active';
        const sevQ = (this._filter === 'Critical' || this._filter === 'Warning')
            ? `&severity=${this._filter}` : '';
        const [res, heat] = await Promise.all([
            API.request(`incidents?status=${statusQ}${sevQ}`, 'GET', null, 12000, { silent: !!silent }),
            API.request('heatmap', 'GET', null, 8000, { silent: true })
        ]);
        const summaryEl = document.getElementById('inc-summary');
        const listEl = document.getElementById('inc-list');
        const heatEl = document.getElementById('inc-heatmap');
        if (!res.Success) {
            if (listEl && !silent) listEl.innerHTML = `<p class="text-slate-500">${this.escape(res.Message)}</p>`;
            return;
        }
        const summary = res.Data.Summary || {};
        let items = API.asArray(res.Data.Items);
        if (this._filter === 'Critical' || this._filter === 'Warning') {
            items = items.filter((i) => String(i.Severity) === this._filter);
        }
        if (summaryEl) {
            summaryEl.innerHTML = [
                ['Open', summary.Open, 'text-cyan-400'],
                ['Critical', summary.Critical, 'text-rose-400'],
                ['Warnings', summary.Warnings, 'text-amber-400'],
                ['Resolved Today', summary.ResolvedToday, 'text-emerald-400']
            ].map(([l, v, c]) => `
                <div class="glass-panel p-3 text-center">
                    <div class="text-[11px] text-slate-500 uppercase">${l}</div>
                    <div class="text-2xl font-bold ${c} mt-1">${v == null ? 0 : v}</div>
                </div>
            `).join('');
        }
        if (listEl) {
            if (!items.length) {
                listEl.innerHTML = `<p class="text-slate-500">No incidents match this filter.</p>`;
            } else {
                listEl.innerHTML = items.map((i) => `
                    <button type="button" class="w-full text-left p-3 rounded-lg border border-slate-800 bg-slate-950/40 hover:border-cyan-500/40 transition"
                        onclick="IncidentsView.select('${this.escape(i.Id)}')">
                        <div class="flex justify-between gap-2">
                            <span class="font-semibold text-slate-100 truncate">${this.escape(i.Title)}</span>
                            <span class="${this.sevClass(i.Severity)}">${this.escape(i.Severity)} · ${i.Score || 0}</span>
                        </div>
                        <div class="text-slate-500 mt-1 flex gap-2 flex-wrap">
                            <span>${this.escape(i.Category || '')}</span>
                            <span>·</span>
                            <span>${i.EventCount || 1} event(s)</span>
                            ${i.Status ? `<span class="badge badge-muted">${this.escape(i.Status)}</span>` : ''}
                        </div>
                    </button>
                `).join('');
            }
        }
        if (heat.Success && heat.Data && heatEl) {
            const d = heat.Data;
            heatEl.innerHTML = [
                ['Security', d.Security], ['Network', d.Network], ['Storage', d.Storage],
                ['Printing', d.Printing], ['Services', d.Services]
            ].map(([name, n]) => `
                <div>
                    <div class="text-slate-400 mb-1">${name}</div>
                    <div class="flex gap-0.5">${this.heatBars(n)}</div>
                </div>
            `).join('');
        }
        if (this._selected) await this.select(this._selected, true);
    },

    async select(id, silent) {
        this._selected = id;
        const res = await API.request(`incidents/${id}`, 'GET', null, 10000, { silent: !!silent });
        const detail = document.getElementById('inc-detail');
        if (!detail) return;
        if (!res.Success || !res.Data) {
            detail.innerHTML = `<p class="text-slate-500">${this.escape(res.Message || 'Not found')}</p>`;
            return;
        }
        const i = res.Data;
        const timeline = API.asArray(i.Timeline).slice().reverse();
        const remediations = API.asArray(i.SuggestedRemediation || i.Remediation || i.Recommendations);
        detail.innerHTML = `
            <div class="space-y-3">
                <div>
                    <h3 class="text-sm font-bold text-slate-100">${this.escape(i.Title)}</h3>
                    <p class="${this.sevClass(i.Severity)} mt-1">${this.escape(i.Severity)} · Score ${i.Score || 0}</p>
                    ${i.RootCause ? `<p class="text-slate-400 mt-2"><span class="text-slate-500">Root cause:</span> ${this.escape(i.RootCause)}</p>` : ''}
                </div>
                <div class="flex gap-2 flex-wrap">
                    <button type="button" class="action-btn emerald text-[11px]" onclick="IncidentsView.resolve('${this.escape(i.Id)}')">Resolve</button>
                    <button type="button" class="action-btn amber text-[11px]" onclick="IncidentsView.ack('${this.escape(i.Id)}')">Ack</button>
                    <button type="button" class="action-btn cyan text-[11px]" onclick="Router.loadModuleView('timeline')">Timeline</button>
                </div>
                ${remediations.length ? `
                <div class="border-t border-slate-800 pt-3">
                    <div class="text-[11px] text-slate-500 uppercase mb-2">Suggested remediation</div>
                    <ul class="space-y-1 text-slate-300 list-disc list-inside">
                        ${remediations.map((r) => `<li>${this.escape(typeof r === 'string' ? r : (r.Title || r.Detail || JSON.stringify(r)))}</li>`).join('')}
                    </ul>
                </div>` : ''}
                <div class="border-t border-slate-800 pt-3 space-y-2 max-h-80 overflow-y-auto">
                    <div class="text-[11px] text-slate-500 uppercase mb-1">Timeline</div>
                    ${timeline.length ? timeline.map((t) => `
                        <div class="border-l-2 border-cyan-500/40 pl-3">
                            <div class="text-slate-500 text-[10px]">${this.escape(t.Timestamp)}</div>
                            <div class="text-slate-200">${this.escape(t.Title)}</div>
                            <div class="text-slate-500">${this.escape(t.Detail || '')}</div>
                        </div>
                    `).join('') : '<p class="text-slate-500">No timeline entries.</p>'}
                </div>
            </div>
        `;
    },

    async resolve(id) {
        await API.request(`incidents/${id}/resolve`, 'POST', { Note: 'Resolved from dashboard' });
        this._selected = null;
        await this.refresh();
        const detail = document.getElementById('inc-detail');
        if (detail) detail.innerHTML = `<p class="text-emerald-400">Incident resolved.</p>`;
    },

    async ack(id) {
        await API.request(`incidents/${id}/ack`, 'POST', {});
        await this.select(id);
    }
};

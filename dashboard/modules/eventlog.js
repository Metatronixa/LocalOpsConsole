const EventLogView = {
    async render(container, mod) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">${mod.name || 'Event Log'}</h2>
                        <p class="text-xs text-slate-400">${mod.description || 'Recent Critical and Error events (bounded query)'}</p>
                    </div>
                    <div class="flex gap-2 flex-wrap">
                        <button type="button" class="action-btn slate text-[11px]" onclick="Router.loadModuleView('timeline')">Timeline</button>
                        <button type="button" class="action-btn cyan" onclick="EventLogView.refresh()">Refresh</button>
                    </div>
                </div>
                <div class="glass-panel p-4">
                    <div class="section-title">Summary (24h sample)</div>
                    <div id="elog-summary" class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs">
                        <div class="text-slate-400">Loading…</div>
                    </div>
                </div>
                <div class="glass-panel p-4">
                    <div class="section-title">Recent errors / critical</div>
                    <div id="elog-list" class="space-y-2 text-xs max-h-96 overflow-y-auto text-slate-400">Loading…</div>
                </div>
            </div>`;
        setTimeout(() => this.refresh(), 0);
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    async refresh() {
        const sumEl = document.getElementById('elog-summary');
        const listEl = document.getElementById('elog-list');
        if (sumEl) sumEl.innerHTML = '<div class="result-busy col-span-full"><span class="spinner"></span> Summarizing…</div>';
        if (listEl) listEl.innerHTML = '<div class="result-busy"><span class="spinner"></span> Loading recent errors…</div>';

        // Parallel, short timeouts — Event Log queries must stay bounded server-side
        const [sum, recent] = await Promise.all([
            API.diagnostic('eventlog', 'GetLogSummary', '', 15000),
            API.diagnostic('eventlog', 'GetRecentErrors', 'MaxEvents=40&Hours=48', 15000)
        ]);

        if (sumEl) {
            if (!sum.Success) {
                sumEl.innerHTML = `<p class="text-rose-400 col-span-full">${this.escape(sum.Message || 'Failed')}</p>`;
            } else {
                const rows = API.asArray(sum.Data);
                sumEl.innerHTML = rows.map((r) => `
                    <div class="p-3 rounded-lg bg-slate-950/50 border border-slate-800">
                        <div class="text-slate-200 font-semibold">${this.escape(r.LogName)}</div>
                        <div class="text-2xl font-bold ${r.Accessible === false ? 'text-amber-400' : 'text-cyan-400'} mt-1">
                            ${r.Accessible === false ? '—' : (r.Capped ? `${r.ErrorsLast24h}+` : (r.ErrorsLast24h ?? 0))}
                        </div>
                        <div class="text-slate-500 mt-1">${r.Accessible === false ? this.escape(r.Note || 'Unavailable') : (r.Capped ? 'Sample capped' : 'errors/critical')}</div>
                    </div>`).join('');
            }
        }

        if (listEl) {
            if (!recent.Success) {
                listEl.innerHTML = `<p class="text-rose-400">${this.escape(recent.Message || 'Failed')}</p>`;
            } else {
                const items = API.asArray(recent.Data);
                if (!items.length) {
                    listEl.innerHTML = '<p class="text-emerald-400">No recent Critical/Error events in the window.</p>';
                } else {
                    listEl.innerHTML = items.map((e) => `
                        <div class="p-2.5 rounded-lg border border-slate-800 bg-slate-950/40">
                            <div class="flex justify-between gap-2 flex-wrap">
                                <span class="text-slate-200 font-medium">${this.escape(e.Provider || e.LogName)}</span>
                                <span class="text-slate-500 font-mono">${this.escape(e.TimeCreated)}</span>
                            </div>
                            <div class="text-slate-500 mt-0.5">${this.escape(e.Level)} · ${this.escape(e.LogName)} · ID ${this.escape(e.Id)}</div>
                            <div class="text-slate-300 mt-1">${this.escape(e.Message || '')}</div>
                        </div>`).join('');
                }
            }
        }
    }
};

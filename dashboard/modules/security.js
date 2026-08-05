const SecurityToolsView = {
    async render(container, mod) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">${mod.name || 'Security'}</h2>
                        <p class="text-xs text-slate-400">${mod.description || 'Firewall and Microsoft Defender status'}</p>
                    </div>
                    <div class="flex gap-2 flex-wrap">
                        <button type="button" class="action-btn slate text-[11px]" onclick="Router.loadModuleView('securitycenter')">Security Center</button>
                        <button type="button" class="action-btn cyan" onclick="SecurityToolsView.refresh()">Refresh</button>
                        <button type="button" class="action-btn amber" id="sec-quickscan"
                                onclick="SecurityToolsView.quickScan()" ${window.__LOC_ADMIN ? '' : 'disabled title="Requires Administrator"'}>
                            Quick Scan${window.__LOC_ADMIN ? '' : ' 🔒'}
                        </button>
                    </div>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="glass-panel p-4">
                        <div class="section-title">Firewall</div>
                        <div id="sec-fw" class="text-xs text-slate-400">Loading…</div>
                    </div>
                    <div class="glass-panel p-4">
                        <div class="section-title">Microsoft Defender</div>
                        <div id="sec-def" class="text-xs text-slate-400">Loading…</div>
                    </div>
                </div>
                <div id="sec-extra" class="result-panel text-slate-400 text-xs">Run Refresh to load live status. Quick Scan requires elevation.</div>
            </div>`;
        // Don't block navigation — fetch after paint
        setTimeout(() => this.refresh(), 0);
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    boolBadge(v) {
        if (v === true) return '<span class="badge badge-ok">On</span>';
        if (v === false) return '<span class="badge badge-err">Off</span>';
        return '<span class="badge badge-muted">—</span>';
    },

    async refresh() {
        const fwEl = document.getElementById('sec-fw');
        const defEl = document.getElementById('sec-def');
        if (fwEl) fwEl.innerHTML = '<div class="result-busy"><span class="spinner"></span> Querying firewall…</div>';
        if (defEl) defEl.innerHTML = '<div class="result-busy"><span class="spinner"></span> Querying Defender…</div>';

        const [fw, def] = await Promise.all([
            API.diagnostic('security', 'GetFirewall', '', 12000),
            API.diagnostic('security', 'GetDefender', '', 12000)
        ]);

        if (fwEl) {
            if (!fw.Success) {
                fwEl.innerHTML = `<p class="text-rose-400">${this.escape(fw.Message || 'Failed')}</p>`;
            } else {
                const rows = API.asArray(fw.Data);
                fwEl.innerHTML = rows.length ? rows.map((p) => `
                    <div class="flex items-center justify-between py-2 border-b border-slate-800">
                        <span class="text-slate-200 font-medium">${this.escape(p.Name)}</span>
                        <span>${p.Enabled ? '<span class="badge badge-ok">Enabled</span>' : '<span class="badge badge-err">Disabled</span>'}</span>
                    </div>
                    <div class="text-slate-500 mb-2">In: ${this.escape(p.DefaultInbound)} · Out: ${this.escape(p.DefaultOutbound)}</div>
                `).join('') : '<p class="text-slate-500">No profiles returned.</p>';
            }
        }

        if (defEl) {
            if (!def.Success) {
                defEl.innerHTML = `<p class="text-rose-400">${this.escape(def.Message || 'Failed')}</p>`;
            } else {
                const d = def.Data || {};
                defEl.innerHTML = `
                    <div class="space-y-2">
                        <div class="flex justify-between"><span>Antivirus</span>${this.boolBadge(d.AntivirusEnabled)}</div>
                        <div class="flex justify-between"><span>Realtime</span>${this.boolBadge(d.RealTimeProtection)}</div>
                        <div class="flex justify-between"><span>AM Service</span>${this.boolBadge(d.AMServiceEnabled)}</div>
                        <div class="flex justify-between"><span>Signature age</span><span class="text-slate-300">${this.escape(d.AntivirusSignatureAge ?? '—')}d</span></div>
                        <div class="flex justify-between"><span>Last quick scan</span><span class="text-slate-300">${this.escape(d.LastQuickScan || '—')}</span></div>
                        ${d.Note ? `<p class="text-amber-400 mt-2">${this.escape(d.Note)}</p>` : ''}
                    </div>`;
            }
        }

        const extra = document.getElementById('sec-extra');
        if (extra) {
            extra.classList.remove('text-slate-500');
            extra.innerHTML = `<span class="text-emerald-400">Updated</span> · ${new Date().toLocaleTimeString()}`;
        }
    },

    async quickScan() {
        if (!confirm('Start a Defender Quick Scan? This can take several minutes.')) return;
        const extra = document.getElementById('sec-extra');
        if (extra) extra.innerHTML = '<div class="result-busy"><span class="spinner"></span> Quick Scan starting…</div>';
        LiveConsole.log('security / actions / QuickScan', 'INFO');
        const res = await API.action('security', 'QuickScan', {}, 120000);
        if (extra) {
            if (typeof ResultRenderer !== 'undefined') ResultRenderer.mount(extra, res.Message, res.Data);
            else extra.textContent = res.Message || (res.Success ? 'OK' : 'Failed');
        }
        if (res.Success) LiveConsole.log(res.Message || 'OK', 'SUCCESS');
        else LiveConsole.log(res.Message || 'Failed', 'ERROR');
    }
};

/* Alias used by ModuleView naming */
const SecurityView = SecurityToolsView;

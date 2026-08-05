/** Manifest-driven Diagnostics / Actions view */
const ModuleView = {
    async render(container, mod) {
        const isAdmin = window.__LOC_ADMIN === true;
        const diagButtons = (mod.diagnostics || []).map((name) => `
            <button class="action-btn cyan" onclick="ModuleView.runDiag('${mod.id}', '${name}')">${name}</button>
        `).join('');

        const actionButtons = (mod.actions || []).map((name) => {
            const needsAdmin = (mod.requiresAdmin || []).some((a) => a.toLowerCase() === name.toLowerCase());
            const disabled = needsAdmin && !isAdmin ? 'disabled title="Requires Administrator"' : '';
            return `<button class="action-btn amber" ${disabled} onclick="ModuleView.runAction('${mod.id}', '${name}')">${name}${needsAdmin ? ' 🔒' : ''}</button>`;
        }).join('');

        const computerBox = (mod.id || '').toLowerCase() === 'remote' ? `
            <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 mb-4">
                <label class="text-xs font-mono text-slate-400">Computer name or IP</label>
                <div class="flex gap-2 mt-2">
                    <input id="remote-computer" type="text" placeholder="PC-NAME or 192.168.1.10"
                        class="px-3 py-1.5 rounded-lg bg-slate-900 border border-slate-800 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50 flex-1" />
                </div>
                <p class="text-[11px] text-slate-500 mt-2">Used by ListShares, ListOpenFiles, ListSessions, GetRemoteRegistry.</p>
            </div>
        ` : '';

        const caps = (mod.capabilities || []).map((c) =>
            `<span class="badge badge-muted">${c}</span>`
        ).join(' ');

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">${mod.name}</h2>
                        <p class="text-xs text-slate-400">${mod.description || ''}</p>
                        ${caps ? `<div class="flex flex-wrap gap-1 mt-2">${caps}</div>` : ''}
                    </div>
                    <span class="badge badge-muted">v${mod.version || '1.0.0'}</span>
                </div>
                ${computerBox}
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="glass-panel p-5">
                        <div class="section-title">Diagnostics</div>
                        <div class="flex flex-wrap gap-2" style="flex-wrap:wrap;display:flex;">${diagButtons || '<span class="text-slate-500 text-xs">None</span>'}</div>
                    </div>
                    <div class="glass-panel p-5">
                        <div class="section-title">Remediation</div>
                        <div class="flex flex-wrap gap-2" style="flex-wrap:wrap;display:flex;">${actionButtons || '<span class="text-slate-500 text-xs">None</span>'}</div>
                    </div>
                </div>

                <div id="module-result" class="result-panel text-slate-500">Run a diagnostic or action to see results here.</div>
            </div>
        `;
    },

    setBusy(message) {
        const el = document.getElementById('module-result');
        if (!el) return;
        el.classList.remove('text-slate-500');
        el.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${ResultRenderer ? ResultRenderer.escape(message) : message}</div>`;
    },

    showResult(message, data) {
        const el = document.getElementById('module-result');
        if (!el) return;
        if (typeof ResultRenderer !== 'undefined') {
            ResultRenderer.mount(el, message, data);
        } else {
            el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
        }
    },

    collectParams(moduleId, name) {
        const params = {};
        if ((moduleId || '').toLowerCase() === 'remote') {
            const el = document.getElementById('remote-computer');
            if (el && el.value.trim()) params.ComputerName = el.value.trim();
        }
        if (/GetRemoteRegistry/i.test(name)) {
            params.Hive = params.Hive || 'HKLM';
            params.Path = params.Path || 'SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion';
        }
        return params;
    },

    async runDiag(moduleId, name) {
        LiveConsole.log(`${moduleId} / diagnostics / ${name}`, 'INFO');
        this.setBusy(`Running ${name}…`);
        const params = this.collectParams(moduleId, name);
        const q = Object.keys(params).map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`).join('&');
        const res = await API.diagnostic(moduleId, name, q);
        if (res.Success) {
            LiveConsole.log(res.Message || 'OK', 'SUCCESS');
            this.showResult(res.Message, res.Data && res.Data.Output && Object.keys(res.Data).length <= 3 ? res.Data.Output : res.Data);
        } else {
            LiveConsole.log(res.Message || 'Failed', 'ERROR', res.Data);
            this.showResult(res.Message || 'Failed', res.Data);
        }
    },

    async runAction(moduleId, name) {
        if (!confirm(`Run action ${name} on ${moduleId}?`)) return;
        LiveConsole.log(`${moduleId} / actions / ${name}`, 'INFO');
        this.setBusy(`Running ${name}…`);
        const params = this.collectParams(moduleId, name);
        if (/OpenVendorUpdatePage/i.test(name) && params.Vendor == null) {
            params.Vendor = 'NVIDIA';
        }
        const longRunning = /SfcScanNow|DismRestoreHealth|ClearSoftwareDistribution/i.test(name);
        const res = await API.action(moduleId, name, params, longRunning ? 600000 : undefined);
        if (res.Success) {
            LiveConsole.log(res.Message || 'OK', 'SUCCESS');
            if (res.Data && res.Data.Url) {
                window.open(res.Data.Url, '_blank');
            }
            this.showResult(res.Message, res.Data && res.Data.Output ? res.Data.Output : res.Data);
        } else {
            LiveConsole.log(res.Message || 'Failed', 'ERROR', res.Data);
            this.showResult(res.Message || 'Failed', res.Data);
        }
    }
};

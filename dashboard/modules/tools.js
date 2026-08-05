const ToolsView = {
    _busy: false,

    async render(container, mod) {
        const tools = (mod.diagnostics || []);
        const actions = (mod.actions || []);
        const admin = window.__LOC_ADMIN;
        const buttons = tools.map((name) => {
            const needsAdmin = (mod.requiresAdmin || []).some((a) => a.toLowerCase() === name.toLowerCase());
            const disabled = needsAdmin && !admin ? 'disabled' : '';
            return `<button class="action-btn cyan tools-run-btn" data-tool="${name}" ${disabled} onclick="ToolsView.run('${name}')">${name}</button>`;
        }).join('');
        const actionBtns = actions.map((name) => {
            const needsAdmin = (mod.requiresAdmin || []).some((a) => a.toLowerCase() === name.toLowerCase());
            const disabled = needsAdmin && !admin ? 'disabled' : '';
            return `<button class="action-btn amber tools-run-btn" data-tool="${name}" ${disabled} onclick="ToolsView.runAction('${name}')">${name}</button>`;
        }).join('');

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">IT Tools</h2>
                        <p class="text-xs text-slate-400">Classic support commands and OS repair without a separate shell.</p>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                    <div class="section-title">Nslookup target</div>
                    <label class="text-[11px] text-slate-500 block mb-1">Host / IP (used by Nslookup)</label>
                    <input id="tools-nslookup-host" type="text" placeholder="www.microsoft.com"
                        class="w-full max-w-md px-3 py-2 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50"
                        value="www.microsoft.com" />
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                    <div class="section-title">Diagnostics</div>
                    <div style="display:flex;flex-wrap:wrap;gap:0.5rem;">${buttons}</div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                    <div class="section-title">Actions / Repair</div>
                    <p class="text-[11px] text-slate-500 mb-2">SfcScanNow and DismRestoreHealth can take a long time — other tools should return in seconds.</p>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-3">
                        <div>
                            <label class="text-[11px] text-slate-500 block mb-1">Route destination</label>
                            <input id="tools-route-dest" type="text" placeholder="192.168.50.10"
                                class="w-full px-3 py-2 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50" />
                        </div>
                        <div>
                            <label class="text-[11px] text-slate-500 block mb-1">Gateway</label>
                            <input id="tools-route-gw" type="text" placeholder="192.168.1.1"
                                class="w-full px-3 py-2 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50" />
                        </div>
                        <div>
                            <label class="text-[11px] text-slate-500 block mb-1">Mask (default host route)</label>
                            <input id="tools-route-mask" type="text" placeholder="255.255.255.255"
                                class="w-full px-3 py-2 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50"
                                value="255.255.255.255" />
                        </div>
                        <div class="flex items-end">
                            <label class="flex items-center gap-2 text-xs text-slate-300 cursor-pointer">
                                <input id="tools-route-permanent" type="checkbox" class="rounded border-slate-600" />
                                Permanent (survives reboot)
                            </label>
                        </div>
                    </div>
                    <div style="display:flex;flex-wrap:wrap;gap:0.5rem;">${actionBtns}</div>
                </div>

                <div id="tools-output" class="tool-output">Select a tool to run…</div>
            </div>
        `;
        this._busy = false;
    },

    setBusy(message) {
        const out = document.getElementById('tools-output');
        if (!out) return;
        out.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${this.escape(message)}</div>`;
    },

    setOutput(text) {
        const out = document.getElementById('tools-output');
        if (!out) return;
        out.innerHTML = `<pre class="tool-output-pre m-0">${this.escape(text || '(no output)')}</pre>`;
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    setRunning(running) {
        this._busy = !!running;
        document.querySelectorAll('.tools-run-btn').forEach((btn) => {
            if (running) {
                btn.dataset.wasDisabled = btn.disabled ? '1' : '0';
                btn.disabled = true;
            } else if (btn.dataset.wasDisabled === '0') {
                btn.disabled = false;
            }
        });
    },

    async run(name) {
        if (this._busy) return;
        LiveConsole.log(`Tools / ${name}`, 'INFO');
        this.setRunning(true);
        this.setBusy(`Running ${name}…`);
        try {
            let q = '';
            if (/^Nslookup$/i.test(name)) {
                const hostEl = document.getElementById('tools-nslookup-host');
                const host = hostEl && hostEl.value.trim() ? hostEl.value.trim() : '';
                if (host) q = `HostName=${encodeURIComponent(host)}`;
            }
            const long = /SystemInfo|GpResult|DismGetHealth|SfcVerifyOnly|ChkdskStatus/i.test(name);
            const res = await API.diagnostic('tools', name, q, long ? 120000 : 25000);
            if (res.Success) {
                const text = res.Data?.Output || JSON.stringify(res.Data, null, 2);
                this.setOutput(text || '(no output)');
                LiveConsole.log(res.Message, 'SUCCESS');
            } else {
                this.setOutput(res.Message || 'Failed');
                LiveConsole.log(res.Message, 'ERROR', res.Data);
            }
        } finally {
            this.setRunning(false);
        }
    },

    async runAction(name) {
        if (this._busy) return;

        let params = {};
        if (/^RouteAdd$/i.test(name)) {
            const dest = (document.getElementById('tools-route-dest')?.value || '').trim();
            const gw = (document.getElementById('tools-route-gw')?.value || '').trim();
            const mask = (document.getElementById('tools-route-mask')?.value || '').trim() || '255.255.255.255';
            const permanent = !!(document.getElementById('tools-route-permanent')?.checked);
            if (!dest || !gw) {
                this.setOutput('RouteAdd requires Destination and Gateway.');
                return;
            }
            params = { Destination: dest, Gateway: gw, Mask: mask, Permanent: permanent ? 'true' : 'false' };
        }

        const warn = /SfcScanNow|DismRestoreHealth/i.test(name)
            ? 'This can take 15–60+ minutes. Continue?'
            : /^RouteAdd$/i.test(name)
                ? `Add route ${params.Destination} via ${params.Gateway}${params.Permanent === 'true' ? ' (permanent)' : ''}?`
                : `Run ${name}?`;
        if (!confirm(warn)) return;

        LiveConsole.log(`Tools / ${name}`, 'INFO');
        this.setRunning(true);
        this.setBusy(`Running ${name}…`);
        try {
            const long = /SfcScanNow|DismRestoreHealth/i.test(name);
            const res = await API.action('tools', name, params, long ? 600000 : 60000);
            this.setOutput(res.Data?.Output || res.Message || '(no output)');
            LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        } finally {
            this.setRunning(false);
        }
    }
};

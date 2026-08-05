const NetworkView = {
    async render(container) {
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Network & Adapters</h2>
                        <p class="text-xs text-slate-400">Interfaces, hosts file, WINS/NetBIOS, DNS, and ICMP. ${admin ? '' : '<span class="text-amber-400">Hosts edits need elevation.</span>'}</p>
                    </div>
                    <div class="flex items-center gap-2 flex-wrap">
                        <button onclick="NetworkView.flushDNS()" class="action-btn amber" ${needsElev}>Flush DNS</button>
                        <button onclick="NetworkView.renewIP()" class="action-btn cyan" ${needsElev}>Release / Renew IP</button>
                        <button onclick="NetworkView.ping()" class="action-btn emerald">Ping 8.8.8.8</button>
                    </div>
                </div>
                <div id="adapter-grid" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 text-slate-500 text-xs font-mono">Loading adapters...</div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <div class="flex items-center justify-between">
                        <h3 class="text-sm font-bold text-slate-100">Hosts file</h3>
                        <button onclick="NetworkView.loadHosts()" class="action-btn cyan text-[11px]">Refresh</button>
                    </div>
                    <p class="text-[11px] text-slate-500 font-mono" id="hosts-path">—</p>
                    <div class="overflow-x-auto">
                        <table class="w-full text-xs font-mono text-left">
                            <thead class="text-slate-500"><tr>
                                <th class="py-1 pr-2">#</th><th class="py-1 pr-2">On</th><th class="py-1 pr-2">IP</th><th class="py-1 pr-2">Hostnames</th><th class="py-1">Actions</th>
                            </tr></thead>
                            <tbody id="hosts-tbody"><tr><td colspan="5" class="text-slate-500 py-2">Loading…</td></tr></tbody>
                        </table>
                    </div>
                    <div class="flex flex-wrap gap-2 items-end ${admin ? '' : 'opacity-60'}">
                        <label class="text-[11px] text-slate-400">IP<br/><input id="hosts-ip" class="px-2 py-1 rounded bg-slate-950 border border-slate-700 text-slate-200" placeholder="127.0.0.1" ${needsElev}/></label>
                        <label class="text-[11px] text-slate-400">Hostname<br/><input id="hosts-name" class="px-2 py-1 rounded bg-slate-950 border border-slate-700 text-slate-200" placeholder="local.dev" ${needsElev}/></label>
                        <button onclick="NetworkView.addHost()" class="action-btn emerald" ${needsElev}>Add entry</button>
                    </div>
                    ${admin ? '' : '<p class="text-[11px] text-amber-400">Needs elevation — relaunch start.bat as Administrator to edit hosts.</p>'}
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">WINS / NetBIOS</h3>
                            <button onclick="NetworkView.loadWins()" class="action-btn cyan text-[11px]">Refresh</button>
                        </div>
                        <div id="wins-panel" class="text-xs text-slate-400 font-mono">Loading…</div>
                    </div>
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">nbtstat</h3>
                            <button onclick="NetworkView.loadNbstat()" class="action-btn cyan text-[11px]">Run nbtstat</button>
                        </div>
                        <pre id="nbstat-panel" class="text-[11px] text-slate-400 font-mono whitespace-pre-wrap max-h-64 overflow-auto">Click Run nbtstat.</pre>
                    </div>
                </div>

                <div id="network-result" class="result-panel text-slate-500">Ping and actions show results here.</div>
            </div>
        `;
        this.loadAdapters();
        this.loadHosts();
        this.loadWins();
    },

    showResult(message, data) {
        const el = document.getElementById('network-result');
        if (!el) return;
        if (typeof ResultRenderer !== 'undefined') {
            ResultRenderer.mount(el, message, data);
        } else {
            el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
        }
    },

    setBusy(msg) {
        const el = document.getElementById('network-result');
        if (el) el.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${msg}</div>`;
    },

    async loadAdapters() {
        LiveConsole.log('Fetching network adapter topology...', 'INFO');
        const grid = document.getElementById('adapter-grid');
        const res = await API.diagnostic('network', 'GetStatus', '', 15000);
        if (!res.Success) {
            if (grid) grid.innerHTML = `<div class="p-4 rounded-xl bg-slate-900/60 border border-rose-500/40 text-rose-300 text-xs">${res.Message || 'Failed to load adapters'}</div>`;
            LiveConsole.log(res.Message || 'GetStatus failed', 'ERROR');
            return;
        }
        const rows = API.asArray(res.Data);
        if (!grid) return;
        grid.innerHTML = rows.map((a) => `
            <div class="p-5 rounded-xl bg-slate-900/60 border ${a.IsConnected ? 'border-emerald-500/30' : 'border-slate-800'} backdrop-blur-md">
                <div class="flex items-center justify-between mb-3">
                    <span class="font-bold text-sm text-slate-100">${a.InterfaceAlias || a.Name || 'Adapter'}</span>
                    <span class="badge ${a.IsConnected ? 'badge-ok' : 'badge-muted'}">${a.Status || ''}</span>
                </div>
                <div class="space-y-1.5 font-mono text-xs text-slate-400">
                    <div><strong class="text-slate-300">IPv4:</strong> ${a.IPv4Address || '—'}</div>
                    <div><strong class="text-slate-300">Gateway:</strong> ${a.Gateway || '—'}</div>
                    <div><strong class="text-slate-300">DNS:</strong> ${a.DNSServers || '—'}</div>
                    <div><strong class="text-slate-300">WINS:</strong> ${[a.WINSPrimary, a.WINSSecondary].filter(Boolean).join(' / ') || '—'}</div>
                    <div><strong class="text-slate-300">NetBIOS:</strong> ${a.NetbiosMode || '—'}</div>
                    <div><strong class="text-slate-300">Speed:</strong> ${a.LinkSpeed || '—'}</div>
                </div>
            </div>
        `).join('') || '<div class="text-slate-500 text-xs">No adapters found.</div>';
        LiveConsole.log(`Discovered ${rows.length} network interface(s).`, 'SUCCESS');
    },

    async loadHosts() {
        const tbody = document.getElementById('hosts-tbody');
        const pathEl = document.getElementById('hosts-path');
        const res = await API.diagnostic('network', 'GetHostsFile', '', 10000);
        if (!res.Success) {
            if (tbody) tbody.innerHTML = `<tr><td colspan="5" class="text-rose-300 py-2">${res.Message || 'Failed'}</td></tr>`;
            return;
        }
        if (pathEl) pathEl.textContent = res.Data.Path || '';
        const entries = (res.Data && res.Data.Entries) ? res.Data.Entries : [];
        const admin = !!window.__LOC_ADMIN;
        if (!tbody) return;
        if (!entries.length) {
            tbody.innerHTML = '<tr><td colspan="5" class="text-slate-500 py-2">No parsed entries.</td></tr>';
            return;
        }
        tbody.innerHTML = entries.map((e) => `
            <tr class="border-t border-slate-800/80">
                <td class="py-1 pr-2 text-slate-500">${e.LineNumber}</td>
                <td class="py-1 pr-2">${e.Enabled ? '<span class="text-emerald-400">Y</span>' : '<span class="text-slate-500">N</span>'}</td>
                <td class="py-1 pr-2 text-slate-200">${e.IP || ''}</td>
                <td class="py-1 pr-2 text-slate-300">${e.Hostnames || ''}</td>
                <td class="py-1 space-x-1">
                    <button class="action-btn amber text-[10px] px-1.5 py-0.5" ${admin ? '' : 'disabled'} onclick="NetworkView.toggleHost(${e.LineNumber})">Toggle</button>
                    <button class="action-btn rose text-[10px] px-1.5 py-0.5" ${admin ? '' : 'disabled'} onclick="NetworkView.removeHost(${e.LineNumber})">Remove</button>
                </td>
            </tr>
        `).join('');
    },

    async addHost() {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        const ip = (document.getElementById('hosts-ip') || {}).value || '';
        const name = (document.getElementById('hosts-name') || {}).value || '';
        if (!confirm(`Add hosts entry ${ip} → ${name}?`)) return;
        this.setBusy('Adding hosts entry…');
        const res = await API.action('network', 'AddHostsEntry', { IP: ip.trim(), Hostname: name.trim() });
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message || 'AddHostsEntry', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) this.loadHosts();
    },

    async removeHost(lineNumber) {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        if (!confirm(`Remove hosts line ${lineNumber}?`)) return;
        this.setBusy('Removing hosts entry…');
        const res = await API.action('network', 'RemoveHostsEntry', { LineNumber: lineNumber });
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message || 'RemoveHostsEntry', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) this.loadHosts();
    },

    async toggleHost(lineNumber) {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        this.setBusy('Toggling hosts entry…');
        const res = await API.action('network', 'ToggleHostsEntry', { LineNumber: lineNumber });
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message || 'ToggleHostsEntry', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) this.loadHosts();
    },

    async loadWins() {
        const el = document.getElementById('wins-panel');
        const res = await API.diagnostic('network', 'GetWins', '', 12000);
        if (!el) return;
        if (!res.Success) {
            el.innerHTML = `<span class="text-rose-300">${res.Message || 'Failed'}</span>`;
            return;
        }
        const rows = API.asArray(res.Data);
        el.innerHTML = rows.map((r) => `
            <div class="mb-3 pb-2 border-b border-slate-800/60">
                <div class="text-slate-200 font-semibold">${r.Description || 'Adapter'}</div>
                <div>Primary WINS: ${r.WINSPrimaryServer || '—'}</div>
                <div>Secondary WINS: ${r.WINSSecondaryServer || '—'}</div>
                <div>NetBIOS: ${r.NetbiosMode || '—'}</div>
            </div>
        `).join('') || 'No IP-enabled adapters.';
    },

    async loadNbstat() {
        const el = document.getElementById('nbstat-panel');
        if (el) el.innerHTML = '<span class="spinner"></span> Running nbtstat…';
        const res = await API.diagnostic('network', 'GetNbstat', '', 20000);
        if (!el) return;
        if (!res.Success) {
            el.textContent = res.Message || 'Failed';
            return;
        }
        const local = (res.Data && res.Data.LocalNameTable && res.Data.LocalNameTable.Output) || '';
        const cache = (res.Data && res.Data.ResolutionCache && res.Data.ResolutionCache.Output) || '';
        el.textContent = `=== nbtstat -n ===\n${local}\n\n=== nbtstat -r ===\n${cache}`;
    },

    async flushDNS() {
        LiveConsole.log('Flushing DNS cache...', 'INFO');
        this.setBusy('Flushing DNS…');
        const res = await API.action('network', 'FlushDNS');
        this.showResult(res.Message || (res.Success ? 'OK' : 'Failed'), res.Data);
        LiveConsole.log(res.Message || 'FlushDNS', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
    },

    async renewIP() {
        LiveConsole.log('DHCP release/renew...', 'INFO');
        this.setBusy('Release / renew IP (can take a few seconds)…');
        const res = await API.action('network', 'RenewIP', {}, 45000);
        this.showResult(res.Message || (res.Success ? 'OK' : 'Failed'), res.Data);
        LiveConsole.log(res.Message || 'RenewIP', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) this.loadAdapters();
    },

    async ping() {
        LiveConsole.log('Pinging 8.8.8.8...', 'INFO');
        this.setBusy('Pinging 8.8.8.8…');
        const res = await API.diagnostic('network', 'Ping', 'Target=8.8.8.8&Count=1', 10000);
        this.showResult(res.Message || (res.Success ? 'OK' : 'Failed'), res.Data);
        LiveConsole.log(res.Message || 'Ping', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
    }
};

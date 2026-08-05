const NetworkView = {
    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Network & Adapters</h2>
                        <p class="text-xs text-slate-400">Interface configurations, DNS controls, and ICMP diagnostics.</p>
                    </div>
                    <div class="flex items-center gap-2">
                        <button onclick="NetworkView.flushDNS()" class="action-btn amber" ${window.__LOC_ADMIN ? '' : 'disabled'}>Flush DNS</button>
                        <button onclick="NetworkView.renewIP()" class="action-btn cyan" ${window.__LOC_ADMIN ? '' : 'disabled'}>Release / Renew IP</button>
                        <button onclick="NetworkView.ping()" class="action-btn emerald">Ping 8.8.8.8</button>
                    </div>
                </div>
                <div id="adapter-grid" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 text-slate-500 text-xs font-mono">Loading adapters...</div>
                </div>
                <div id="network-result" class="result-panel text-slate-500">Ping and actions show results here.</div>
            </div>
        `;
        this.loadAdapters();
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
                    <div><strong class="text-slate-300">Speed:</strong> ${a.LinkSpeed || '—'}</div>
                </div>
            </div>
        `).join('') || '<div class="text-slate-500 text-xs">No adapters found.</div>';
        LiveConsole.log(`Discovered ${rows.length} network interface(s).`, 'SUCCESS');
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

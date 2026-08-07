const InternetHealthView = {
    _adapterName: null,

    async render(container) {
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';
        this._adapterName = null;

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Internet Health</h2>
                        <p class="text-xs text-slate-400">Network, VPN, DNS, and connectivity diagnostics.
                            ${admin ? '' : '<span class="text-amber-400">Repair actions need elevation.</span>'}
                        </p>
                    </div>
                    <button onclick="InternetHealthView.loadSummary(true)" class="action-btn cyan">Refresh summary</button>
                </div>

                <div id="ih-summary" class="space-y-3">
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 text-slate-500 text-xs font-mono">
                        <span class="spinner"></span> Loading health summary…
                    </div>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">Connection</h3>
                            <button onclick="InternetHealthView.loadConnection()" class="action-btn cyan text-[11px]">Load</button>
                        </div>
                        <div id="ih-connection" class="text-xs font-mono text-slate-400">Click Load after summary.</div>
                    </div>
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">Cable / Ethernet</h3>
                            <button onclick="InternetHealthView.loadCable()" class="action-btn cyan text-[11px]">Load</button>
                        </div>
                        <div id="ih-cable" class="text-xs font-mono text-slate-400">Click Load.</div>
                    </div>
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">Wi-Fi</h3>
                            <button onclick="InternetHealthView.loadWifi()" class="action-btn cyan text-[11px]">Load</button>
                        </div>
                        <div id="ih-wifi" class="text-xs font-mono text-slate-400">Click Load.</div>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <h3 class="text-sm font-bold text-slate-100">Connectivity tests</h3>
                    <div class="flex flex-wrap gap-2" id="ih-conn-tests">
                        ${this.connTestButtons()}
                    </div>
                    <div id="ih-conn-result" class="text-xs font-mono text-slate-400">Run a test above.</div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <div class="flex items-center justify-between flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100">DNS &amp; hosts</h3>
                        <div class="flex flex-wrap gap-2">
                            <button onclick="InternetHealthView.flushDns()" class="action-btn amber" ${needsElev}>Flush DNS</button>
                            <button onclick="InternetHealthView.runAction('RegisterDns')" class="action-btn emerald" ${needsElev}>Register DNS</button>
                            <button onclick="InternetHealthView.runAction('SetDnsCloudflare')" class="action-btn cyan" ${needsElev}>Cloudflare</button>
                            <button onclick="InternetHealthView.runAction('SetDnsGoogle')" class="action-btn cyan" ${needsElev}>Google</button>
                            <button onclick="InternetHealthView.runAction('SetDnsDhcp')" class="action-btn slate" ${needsElev}>DHCP DNS</button>
                            <button onclick="InternetHealthView.loadDns()" class="action-btn slate text-[11px]">Refresh DNS info</button>
                        </div>
                    </div>
                    <div id="ih-dns" class="text-xs font-mono text-slate-400">Click Refresh DNS info.</div>
                    <p class="text-[11px] text-slate-500 font-mono" id="ih-hosts-path">—</p>
                    <div class="overflow-x-auto">
                        <table class="w-full text-xs font-mono text-left">
                            <thead class="text-slate-500"><tr>
                                <th class="py-1 pr-2">#</th><th class="py-1 pr-2">On</th><th class="py-1 pr-2">IP</th><th class="py-1 pr-2">Hostnames</th><th class="py-1">Actions</th>
                            </tr></thead>
                            <tbody id="ih-hosts-tbody"><tr><td colspan="5" class="text-slate-500 py-2">Load hosts via Refresh DNS info.</td></tr></tbody>
                        </table>
                    </div>
                    <div class="flex flex-wrap gap-2 items-end ${admin ? '' : 'opacity-60'}">
                        <label class="text-[11px] text-slate-400">IP<br/><input id="ih-hosts-ip" class="px-2 py-1 rounded bg-slate-950 border border-slate-700 text-slate-200" placeholder="127.0.0.1" ${needsElev}/></label>
                        <label class="text-[11px] text-slate-400">Hostname<br/><input id="ih-hosts-name" class="px-2 py-1 rounded bg-slate-950 border border-slate-700 text-slate-200" placeholder="local.dev" ${needsElev}/></label>
                        <button onclick="InternetHealthView.addHost()" class="action-btn emerald" ${needsElev}>Add entry</button>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <div class="flex items-center justify-between flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100">VPN</h3>
                        <button onclick="InternetHealthView.loadVpn()" class="action-btn cyan text-[11px]">Refresh</button>
                    </div>
                    <div id="ih-vpn" class="text-xs font-mono text-slate-400">Click Refresh.</div>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    ${this.lazyPanel('Winsock', 'loadWinsock', 'ih-winsock')}
                    ${this.lazyPanel('TCP global', 'loadTcpGlobal', 'ih-tcp')}
                    ${this.lazyPanel('Adapters', 'loadAdapters', 'ih-adapters')}
                    ${this.lazyPanel('Routing', 'loadRoutes', 'ih-routes')}
                    ${this.lazyPanel('Statistics', 'loadStats', 'ih-stats')}
                    ${this.lazyPanel('Proxy', 'loadProxy', 'ih-proxy')}
                    ${this.lazyPanel('Network events', 'loadEvents', 'ih-events')}
                    ${this.lazyPanel('Timeline', 'loadTimeline', 'ih-timeline')}
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <div class="flex items-center justify-between flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100">Port &amp; browser tests</h3>
                        <div class="flex flex-wrap gap-2 items-end">
                            <label class="text-[11px] text-slate-400">Host<br/><input id="ih-port-host" class="px-2 py-1 rounded bg-slate-950 border border-slate-700 text-slate-200 w-32" value="1.1.1.1"/></label>
                            <label class="text-[11px] text-slate-400">Port<br/><input id="ih-port-num" type="number" class="px-2 py-1 rounded bg-slate-950 border border-slate-700 text-slate-200 w-20" value="443"/></label>
                            <button onclick="InternetHealthView.testPort()" class="action-btn cyan text-[11px]">Test port</button>
                            <button onclick="InternetHealthView.testBrowser()" class="action-btn emerald text-[11px]">Browser targets</button>
                        </div>
                    </div>
                    <div id="ih-port-result" class="text-xs font-mono text-slate-400">Run a test.</div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-amber-500/20 space-y-3">
                    <div class="flex items-center justify-between flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100">Automatic diagnosis</h3>
                        <button onclick="InternetHealthView.runDiagnosis()" class="action-btn amber">Run diagnosis</button>
                    </div>
                    <div id="ih-diagnosis" class="text-xs text-slate-400">Not run yet — click Run diagnosis.</div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <h3 class="text-sm font-bold text-slate-100">Quick repairs</h3>
                    <div class="flex flex-wrap gap-2">
                        <button onclick="InternetHealthView.flushDns()" class="action-btn amber" ${needsElev}>Flush DNS</button>
                        <button onclick="InternetHealthView.renewIp()" class="action-btn cyan" ${needsElev}>Renew IP</button>
                        <button onclick="InternetHealthView.runAction('ResetWinsock')" class="action-btn rose" ${needsElev}>Reset Winsock</button>
                        <button onclick="InternetHealthView.runAction('ResetTcpIp')" class="action-btn rose" ${needsElev}>Reset TCP/IP</button>
                        <button onclick="InternetHealthView.runAction('ClearArp')" class="action-btn slate" ${needsElev}>Clear ARP</button>
                        <button onclick="InternetHealthView.runAction('RestartAdapter')" class="action-btn emerald" ${needsElev}>Restart adapter</button>
                        <button onclick="InternetHealthView.runAction('ResetProxy')" class="action-btn slate" ${needsElev}>Reset proxy</button>
                        <button onclick="InternetHealthView.runAction('RestartDnsClient')" class="action-btn slate" ${needsElev}>Restart DNS client</button>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                    <div class="flex items-center justify-between">
                        <h3 class="text-sm font-bold text-slate-100">Speed test</h3>
                        <button onclick="InternetHealthView.runSpeedTest()" class="action-btn cyan">Run speed test</button>
                    </div>
                    <p class="text-[11px] text-slate-500">Opt-in download test (~15s max). Not run automatically.</p>
                    <div id="ih-speed" class="text-xs font-mono text-slate-400">—</div>
                </div>

                <div id="ih-result" class="result-panel text-slate-500">Action results appear here.</div>
            </div>
        `;

        await this.loadSummary(false);
    },

    lazyPanel(title, fn, id) {
        return `
            <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                <div class="flex items-center justify-between">
                    <h3 class="text-sm font-bold text-slate-100">${title}</h3>
                    <button onclick="InternetHealthView.${fn}()" class="action-btn cyan text-[11px]">Load</button>
                </div>
                <div id="${id}" class="text-xs font-mono text-slate-400 max-h-48 overflow-auto">Click Load.</div>
            </div>`;
    },

    connTestButtons() {
        const tests = [
            ['GatewayPing', 'Gateway'], ['GoogleDns', 'Google DNS'], ['CloudflareDns', 'Cloudflare'],
            ['Microsoft', 'Microsoft'], ['GitHub', 'GitHub'], ['DnsResolve', 'DNS resolve'],
            ['Https', 'HTTPS'], ['Tcp443', 'TCP 443'], ['Tcp80', 'TCP 80'], ['ProxyDetect', 'Proxy'], ['Ntp', 'NTP']
        ];
        return tests.map(([t, label]) =>
            `<button onclick="InternetHealthView.runConnTest('${t}')" class="action-btn slate text-[11px]">${label}</button>`
        ).join('');
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    },

    setBusy(msg) {
        const el = document.getElementById('ih-result');
        if (el) el.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${this.escape(msg)}</div>`;
    },

    showResult(message, data) {
        const el = document.getElementById('ih-result');
        if (!el) return;
        if (typeof ResultRenderer !== 'undefined') {
            ResultRenderer.mount(el, message, data);
        } else {
            el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
        }
    },

    statusBadge(st) {
        const s = String(st || '').toUpperCase();
        if (s === 'OK') return '<span class="badge badge-ok">OK</span>';
        if (s === 'WARN') return '<span class="badge badge-warn">WARN</span>';
        if (s === 'ERROR') return '<span class="badge badge-rose">ERROR</span>';
        return `<span class="badge badge-muted">${this.escape(st)}</span>`;
    },

    healthColor(pct) {
        const n = Number(pct) || 0;
        if (n >= 80) return 'text-emerald-400 border-emerald-500/40';
        if (n >= 50) return 'text-amber-400 border-amber-500/40';
        return 'text-rose-400 border-rose-500/40';
    },

    async loadSummary(refresh) {
        const el = document.getElementById('ih-summary');
        if (el) el.innerHTML = '<div class="text-xs text-slate-400"><span class="spinner"></span> Loading summary…</div>';
        const q = refresh ? 'refresh=1' : '';
        const res = await API.diagnostic('internetSlow', 'GetHealthSummary', q, 15000);
        if (!el) return;
        if (!res.Success) {
            el.innerHTML = `<div class="p-4 rounded-xl border border-rose-500/40 text-rose-300 text-xs">${this.escape(res.Message)}</div>`;
            return;
        }
        const d = res.Data || {};
        if (d.Adapter && d.Adapter.Name) this._adapterName = d.Adapter.Name;
        const checks = API.asArray(d.Checks);
        const pct = d.OverallHealthPct != null ? d.OverallHealthPct : '—';
        const hc = this.healthColor(pct);
        el.innerHTML = `
            <div class="flex flex-wrap items-center gap-4">
                <div class="p-5 rounded-xl bg-slate-900/60 border ${hc.split(' ')[1]} min-w-[120px] text-center">
                    <div class="text-3xl font-bold ${hc.split(' ')[0]}">${pct}%</div>
                    <div class="text-[11px] text-slate-500 uppercase tracking-wide">Overall health</div>
                </div>
                <div class="flex-1 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                    ${checks.map((c) => `
                        <div class="p-3 rounded-lg bg-slate-950/60 border border-slate-800/80 flex items-start justify-between gap-2">
                            <div>
                                <div class="text-xs font-semibold text-slate-200">${this.escape(c.Name)}</div>
                                <div class="text-[11px] text-slate-500 mt-0.5">${this.escape(c.Details || '')}</div>
                            </div>
                            ${this.statusBadge(c.Status)}
                        </div>
                    `).join('')}
                </div>
            </div>
            <p class="text-[11px] text-slate-500 font-mono">${this.escape(d.Summary || res.Message)} · ${d.ElapsedMs || '?'}ms</p>
        `;
        LiveConsole.log('Health summary loaded', 'SUCCESS', d);
    },

    async loadConnection() {
        const el = document.getElementById('ih-connection');
        if (el) el.innerHTML = '<span class="spinner"></span> Loading…';
        const res = await API.diagnostic('internetSlow', 'GetConnectionInfo', '', 10000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const d = res.Data || {};
        if (d.Name) this._adapterName = d.Name;
        if (!d.Connected) { el.innerHTML = 'No active connection.'; return; }
        el.innerHTML = `
            <div class="space-y-1">
                <div><strong class="text-slate-300">${this.escape(d.Name)}</strong> · ${this.escape(d.Type)} · ${this.escape(d.Status)}</div>
                <div>IPv4: ${this.escape(d.IPv4 || '—')}</div>
                <div>Gateway: ${this.escape(d.Gateway || '—')}</div>
                <div>DNS: ${this.escape(d.DnsServers || '—')}</div>
                <div>DHCP: ${d.DhcpEnabled ? 'Yes' : 'No'} · MTU: ${d.Mtu || '—'}</div>
                <div>MAC: ${this.escape(d.MacAddress || '—')} · Speed: ${this.escape(d.LinkSpeed || '—')}</div>
                <div>IPv6: ${this.escape(d.IPv6 || '—')}</div>
            </div>`;
    },

    async loadCable() {
        const el = document.getElementById('ih-cable');
        if (el) el.innerHTML = '<span class="spinner"></span> Loading…';
        const res = await API.diagnostic('internetSlow', 'GetCableStatus', '', 10000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const rows = API.asArray(res.Data);
        el.innerHTML = rows.length ? rows.map((r) => `
            <div class="mb-2 pb-2 border-b border-slate-800/60">
                <div class="text-slate-200">${this.escape(r.Name)} · ${this.escape(r.Status)}</div>
                <div>Media: ${r.MediaConnected ? '<span class="text-emerald-400">Connected</span>' : '<span class="text-rose-400">Disconnected</span>'}</div>
                <div>Speed: ${this.escape(r.LinkSpeed || '—')}</div>
            </div>
        `).join('') : 'No physical Ethernet adapters.';
    },

    async loadWifi() {
        const el = document.getElementById('ih-wifi');
        if (el) el.innerHTML = '<span class="spinner"></span> Loading…';
        const res = await API.diagnostic('internetSlow', 'GetWifiInfo', '', 10000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const d = res.Data || {};
        if (!d.HasWifi) { el.textContent = res.Message || 'No Wi-Fi adapter active.'; return; }
        const fields = d.Fields || {};
        el.innerHTML = `
            <div class="space-y-1">
                <div class="text-slate-200">${this.escape(d.Adapter || 'Wi-Fi')}</div>
                <div>SSID: ${this.escape(fields['SSID'] || fields['Name'] || '—')}</div>
                <div>Signal: ${this.escape(fields['Signal'] || '—')}</div>
                <div>Channel: ${this.escape(fields['Channel'] || '—')}</div>
                <div>State: ${this.escape(fields['State'] || '—')}</div>
            </div>
            <pre class="mt-2 text-[10px] text-slate-500 whitespace-pre-wrap">${this.escape(d.Snippet || '')}</pre>`;
    },

    async runConnTest(test) {
        const el = document.getElementById('ih-conn-result');
        if (el) el.innerHTML = `<span class="spinner"></span> Running ${this.escape(test)}…`;
        const res = await API.diagnostic('internetSlow', 'RunConnectivityTest', `Test=${encodeURIComponent(test)}`, 8000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const d = res.Data || {};
        const pass = d.Passed ? 'text-emerald-400' : 'text-rose-400';
        el.innerHTML = `<span class="${pass}">${d.Passed ? 'PASS' : 'FAIL'}</span> · ${this.escape(test)} — ${this.escape(res.Message)}`;
        if (typeof ResultRenderer !== 'undefined') {
            el.innerHTML += `<pre class="mt-2 text-[10px] text-slate-500">${this.escape(JSON.stringify(d.Result, null, 2))}</pre>`;
        }
    },

    async loadDns() {
        const dnsEl = document.getElementById('ih-dns');
        if (dnsEl) dnsEl.innerHTML = '<span class="spinner"></span> Loading DNS…';
        const res = await API.diagnostic('internetSlow', 'GetDnsInfo', '', 12000);
        if (dnsEl) {
            if (!res.Success) dnsEl.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`;
            else {
                const d = res.Data || {};
                const servers = API.asArray(d.DnsServers);
                dnsEl.innerHTML = `
                    <div>Suffix: ${this.escape(d.ConnectionSuffix || '—')}</div>
                    <div>Hosts: ${this.escape(d.HostsFilePath || '')} (${d.HostsEntryCount || 0} entries)</div>
                    ${servers.map((s) => `<div>${this.escape(s.InterfaceAlias)}: ${this.escape(s.Servers)}</div>`).join('') || '<div>No DNS servers listed.</div>'}
                `;
            }
        }
        await this.loadHosts();
    },

    async loadHosts() {
        const tbody = document.getElementById('ih-hosts-tbody');
        const pathEl = document.getElementById('ih-hosts-path');
        const res = await API.diagnostic('network', 'GetHostsFile', '', 10000);
        if (!res.Success) {
            if (tbody) tbody.innerHTML = `<tr><td colspan="5" class="text-rose-300 py-2">${this.escape(res.Message)}</td></tr>`;
            return;
        }
        if (pathEl) pathEl.textContent = (res.Data && res.Data.Path) ? res.Data.Path : '';
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
                <td class="py-1 pr-2 text-slate-200">${this.escape(e.IP || '')}</td>
                <td class="py-1 pr-2 text-slate-300">${this.escape(e.Hostnames || '')}</td>
                <td class="py-1 space-x-1">
                    <button class="action-btn amber text-[10px] px-1.5 py-0.5" ${admin ? '' : 'disabled'} onclick="InternetHealthView.toggleHost(${e.LineNumber})">Toggle</button>
                    <button class="action-btn rose text-[10px] px-1.5 py-0.5" ${admin ? '' : 'disabled'} onclick="InternetHealthView.removeHost(${e.LineNumber})">Remove</button>
                </td>
            </tr>
        `).join('');
    },

    async addHost() {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        const ip = (document.getElementById('ih-hosts-ip') || {}).value || '';
        const name = (document.getElementById('ih-hosts-name') || {}).value || '';
        if (!confirm(`Add hosts entry ${ip} → ${name}?`)) return;
        this.setBusy('Adding hosts entry…');
        const res = await API.action('network', 'AddHostsEntry', { IP: ip.trim(), Hostname: name.trim() });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadHosts();
    },

    async removeHost(lineNumber) {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        if (!confirm(`Remove hosts line ${lineNumber}?`)) return;
        this.setBusy('Removing…');
        const res = await API.action('network', 'RemoveHostsEntry', { LineNumber: lineNumber });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadHosts();
    },

    async toggleHost(lineNumber) {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        this.setBusy('Toggling…');
        const res = await API.action('network', 'ToggleHostsEntry', { LineNumber: lineNumber });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadHosts();
    },

    async loadVpn() {
        const el = document.getElementById('ih-vpn');
        if (el) el.innerHTML = '<span class="spinner"></span> Loading VPN…';
        const [health, conns] = await Promise.all([
            API.diagnostic('internetSlow', 'GetVpnHealth', '', 12000),
            API.diagnostic('vpn', 'GetConnections', '', 12000)
        ]);
        if (!el) return;
        let html = '';
        if (health.Success && health.Data) {
            const d = health.Data;
            const list = API.asArray(d.Connections);
            html += list.map((v) => `
                <div class="mb-2 pb-2 border-b border-slate-800/60 flex justify-between items-start gap-2">
                    <div>
                        <div class="text-slate-200 font-semibold">${this.escape(v.Name)}</div>
                        <div>${this.escape(v.ConnectionStatus)} · ${this.escape(v.TunnelType || '')}</div>
                        <div class="text-slate-500">${this.escape(v.ServerAddress || '')}</div>
                    </div>
                    ${v.ConnectionStatus === 'Connected' ? `<button onclick="InternetHealthView.disconnectVpn('${this.escape(v.Name).replace(/'/g, "\\'")}')" class="action-btn rose text-[10px]">Disconnect</button>` : ''}
                </div>
            `).join('') || '<div>No VPN profiles.</div>';
        } else {
            html += `<div class="text-rose-300">${this.escape(health.Message)}</div>`;
        }
        if (conns.Success && conns.Data && conns.Data.Adapters) {
            const adapters = API.asArray(conns.Data.Adapters);
            if (adapters.length) {
                html += '<div class="mt-2 text-slate-500">Tunnel adapters:</div>';
                html += adapters.map((a) => `<div>${this.escape(a.Name)} · ${this.escape(a.Status)}</div>`).join('');
            }
        }
        el.innerHTML = html;
    },

    async disconnectVpn(name) {
        if (!confirm(`Disconnect VPN "${name}"?`)) return;
        this.setBusy('Disconnecting VPN…');
        const res = await API.action('vpn', 'Disconnect', { ConnectionName: name });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadVpn();
    },

    async loadWinsock() {
        await this.loadDiagInto('ih-winsock', 'GetWinsockInfo', (d) => `<pre class="whitespace-pre-wrap">${this.escape(d.Snippet || '')}</pre><div>LSP count: ${d.LspCount}</div>`);
    },
    async loadTcpGlobal() {
        await this.loadDiagInto('ih-tcp', 'GetTcpGlobal', (d) => {
            const settings = d.Settings || {};
            return Object.keys(settings).map((k) => `<div>${this.escape(k)}: ${this.escape(settings[k])}</div>`).join('') || `<pre>${this.escape(d.Raw || '')}</pre>`;
        });
    },
    async loadAdapters() {
        await this.loadDiagInto('ih-adapters', 'GetAdaptersDetail', (rows) =>
            API.asArray(rows).map((a) => `<div class="mb-1">${this.escape(a.Name)} · ${this.escape(a.Status)} · ${this.escape(a.LinkSpeed || '')} ${a.MediaConnected ? '🔗' : ''}</div>`).join('')
        , true);
    },
    async loadRoutes() {
        await this.loadDiagInto('ih-routes', 'GetRoutes', (d) => {
            const dr = d.DefaultRoute;
            let html = dr ? `<div class="text-slate-200 mb-2">Default: ${this.escape(dr.NextHop)} via ${this.escape(dr.InterfaceAlias)}</div>` : '';
            html += API.asArray(d.StaticRoutes).map((r) =>
                `<div>${this.escape(r.DestinationPrefix)} → ${this.escape(r.NextHop)} (${this.escape(r.InterfaceAlias)})</div>`
            ).join('');
            return html || 'No routes.';
        });
    },
    async loadStats() {
        await this.loadDiagInto('ih-stats', 'GetNetStatistics', (rows) =>
            API.asArray(rows).slice(0, 8).map((s) => {
                const rx = s.ReceivedBytes != null ? Math.round(s.ReceivedBytes / 1048576) : '?';
                const tx = s.SentBytes != null ? Math.round(s.SentBytes / 1048576) : '?';
                return `<div>${this.escape(s.Name)}: ↓${rx}MB ↑${tx}MB</div>`;
            }).join('')
        , true);
    },
    async loadProxy() {
        await this.loadDiagInto('ih-proxy', 'GetProxyInfo', (d) => `
            <div>IE proxy: ${d.ProxyEnable ? 'ON' : 'off'} ${this.escape(d.ProxyServer || '')}</div>
            <div>Auto-config: ${this.escape(d.AutoConfigURL || '—')}</div>
            <pre class="mt-1 text-[10px] whitespace-pre-wrap">${this.escape(d.WinHttpProxy || '')}</pre>
        `);
    },
    async loadEvents() {
        await this.loadDiagInto('ih-events', 'GetNetworkEvents', (rows) =>
            API.asArray(rows).map((e) => `<div class="mb-1 pb-1 border-b border-slate-800/40"><span class="text-slate-500">${this.escape(e.TimeCreated)}</span> [${this.escape(e.Provider)}] ${this.escape(e.Message)}</div>`).join('')
        , true);
    },
    async loadTimeline() {
        await this.loadDiagInto('ih-timeline', 'GetInternetTimeline', (rows) =>
            API.asArray(rows).map((e) => `<div class="mb-1"><span class="text-slate-500">${this.escape(e.At)}</span> <span class="text-amber-400">${this.escape(e.Severity)}</span> ${this.escape(e.Message)}</div>`).join('') || 'No events yet.'
        , true);
    },

    async loadDiagInto(elId, diag, renderFn, dataIsArray) {
        const el = document.getElementById(elId);
        if (el) el.innerHTML = '<span class="spinner"></span> Loading…';
        const res = await API.diagnostic('internetSlow', diag, '', 15000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        el.innerHTML = dataIsArray ? renderFn(res.Data) : renderFn(res.Data || {});
    },

    async testPort() {
        const host = (document.getElementById('ih-port-host') || {}).value || '1.1.1.1';
        const port = (document.getElementById('ih-port-num') || {}).value || '443';
        const el = document.getElementById('ih-port-result');
        if (el) el.innerHTML = '<span class="spinner"></span> Testing port…';
        const res = await API.diagnostic('internetSlow', 'TestPort', `HostName=${encodeURIComponent(host)}&Port=${encodeURIComponent(port)}`, 8000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const d = res.Data || {};
        el.innerHTML = `${d.Success ? '<span class="text-emerald-400">Open</span>' : '<span class="text-rose-400">Closed</span>'} ${this.escape(host)}:${port} (${d.ElapsedMs}ms)`;
    },

    async testBrowser() {
        const el = document.getElementById('ih-port-result');
        if (el) el.innerHTML = '<span class="spinner"></span> Testing browser targets…';
        const res = await API.diagnostic('internetSlow', 'TestBrowserTargets', '', 20000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        el.innerHTML = API.asArray(res.Data).map((t) =>
            `<div>${t.Success ? '✓' : '✗'} ${this.escape(t.Url)} — ${t.StatusCode || '—'} (${t.ElapsedMs}ms)</div>`
        ).join('');
    },

    async runDiagnosis() {
        const el = document.getElementById('ih-diagnosis');
        if (el) el.innerHTML = '<span class="spinner"></span> Running automatic diagnosis…';
        const res = await API.diagnostic('internetSlow', 'RunAutomaticDiagnosis', '', 20000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const d = res.Data || {};
        const admin = !!window.__LOC_ADMIN;
        const actions = API.asArray(d.RecommendedActions);
        el.innerHTML = `
            <div class="space-y-2">
                <div class="text-slate-200 font-semibold">${this.escape(d.Diagnosis || res.Message)}</div>
                <div class="text-slate-400">Likely cause: ${this.escape(d.LikelyCause || '—')}</div>
                <div class="text-slate-500">Fix probability: ${Math.round((d.FixProbability || 0) * 100)}%</div>
                <div class="flex flex-wrap gap-2 mt-2">
                    ${actions.map((a) => {
                        const id = a.ActionId;
                        if (id === 'DisconnectVpn') {
                            return `<button onclick="InternetHealthView.loadVpn()" class="action-btn amber text-[11px]">${this.escape(a.Label)}</button>`;
                        }
                        const needsAdmin = ['RegisterDns', 'SetDnsCloudflare', 'SetDnsGoogle', 'ResetWinsock', 'ResetTcpIp', 'ClearArp', 'RestartAdapter', 'ResetProxy', 'RestartDnsClient'].includes(id);
                        const dis = needsAdmin && !admin ? 'disabled title="Needs elevation"' : '';
                        const fn = id === 'RegisterDns' || !['FlushDNS', 'RenewIP'].includes(id)
                            ? `InternetHealthView.runAction('${id}')`
                            : (id === 'FlushDNS' ? 'InternetHealthView.flushDns()' : 'InternetHealthView.renewIp()');
                        return `<button onclick="${fn}" class="action-btn emerald text-[11px]" ${dis}>${this.escape(a.Label)}</button>`;
                    }).join('')}
                </div>
                <details class="mt-2"><summary class="cursor-pointer text-slate-500">Checks &amp; decision table</summary>
                    <pre class="text-[10px] mt-2 whitespace-pre-wrap text-slate-500">${this.escape(JSON.stringify({ Checks: d.Checks, DecisionTable: d.DecisionTable }, null, 2))}</pre>
                </details>
            </div>`;
        LiveConsole.log('Diagnosis complete', 'INFO', d);
    },

    async runSpeedTest() {
        const el = document.getElementById('ih-speed');
        if (el) el.innerHTML = '<span class="spinner"></span> Running speed test (up to 15s)…';
        const res = await API.diagnostic('internetSlow', 'RunSpeedTest', '', 18000);
        if (!el) return;
        if (!res.Success) { el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`; return; }
        const d = res.Data || {};
        el.innerHTML = `Download: <strong class="text-cyan-400">${d.DownloadMbps ?? '—'}</strong> Mbps · Upload: <strong class="text-emerald-400">${d.UploadMbps ?? '—'}</strong> Mbps · Latency: ${d.LatencyMs ?? '—'} ms`;
    },

    async flushDns() {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        if (!confirm('Flush DNS cache?')) return;
        this.setBusy('Flushing DNS…');
        const res = await API.action('network', 'FlushDNS', {});
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message || 'FlushDNS', res.Success ? 'SUCCESS' : 'ERROR');
    },

    async renewIp() {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        if (!confirm('Release and renew IP (DHCP)?')) return;
        this.setBusy('Renewing IP…');
        const res = await API.action('network', 'RenewIP', {});
        this.showResult(res.Message, res.Data);
    },

    async runAction(name) {
        if (!window.__LOC_ADMIN) { alert('Needs elevation'); return; }
        const warnReboot = ['ResetWinsock', 'ResetTcpIp', 'ResetNetsh'].includes(name);
        const msg = warnReboot
            ? `Run ${name}? A reboot may be required afterward.`
            : `Run ${name}?`;
        if (!confirm(msg)) return;
        this.setBusy(`Running ${name}…`);
        const payload = {};
        if (['RestartAdapter', 'DisableAdapter', 'EnableAdapter', 'SetDnsCloudflare', 'SetDnsGoogle', 'SetDnsDhcp'].includes(name) && this._adapterName) {
            payload.InterfaceAlias = this._adapterName;
        }
        const res = await API.action('internetSlow', name, payload, 30000);
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message || name, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success && name.startsWith('SetDns')) await this.loadDns();
    }
};

const InternetSlowView = InternetHealthView;

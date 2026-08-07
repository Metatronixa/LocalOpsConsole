const RemoteView = {
    _selected: null, // connect address (prefer IP)
    _selectedMeta: null, // { connect, display, name, ip }
    _hosts: [],

    async render(container) {
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';
        this._selected = null;
        this._selectedMeta = null;
        this._hosts = [];

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Remote</h2>
                        <p class="text-xs text-slate-400">LAN admin queries from this console (not fleet agents). Prefers LAN IP — hostnames often time out when DNS/NetBIOS is weak.</p>
                    </div>
                    <button type="button" onclick="RemoteView.discover()" class="action-btn cyan">Discover computers</button>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <div class="lg:col-span-1 p-4 rounded-xl bg-slate-900/60 border border-slate-800 flex flex-col gap-3 min-h-0 max-h-[70vh]">
                        <h3 class="text-sm font-bold text-slate-100 shrink-0">Discovered PCs</h3>
                        <p class="text-[11px] text-slate-500 shrink-0">Click a row to select. Connection uses LAN IP when known.</p>
                        <div class="shrink-0 space-y-2 border-b border-slate-800 pb-3">
                            <label class="text-[11px] text-slate-400">Or type name / IP</label>
                            <div class="flex gap-2">
                                <input id="remote-manual" type="text" placeholder="PC-NAME or 192.168.1.10"
                                    class="flex-1 px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200" />
                                <button type="button" class="action-btn emerald text-[11px]" onclick="RemoteView.selectManual()">Use</button>
                            </div>
                        </div>
                        <div id="remote-host-list" class="flex-1 min-h-0 overflow-y-auto space-y-1 text-xs font-mono">
                            <div class="text-slate-500">Click Discover computers to scan ARP / SMB neighbors.</div>
                        </div>
                    </div>

                    <div class="lg:col-span-2 space-y-4">
                        <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                            <div class="flex items-center justify-between flex-wrap gap-2">
                                <div>
                                    <h3 class="text-sm font-bold text-slate-100">Selected target</h3>
                                    <p id="remote-selected-label" class="text-lg font-mono text-cyan-300 mt-1">None — select a PC first</p>
                                    <p id="remote-selected-sub" class="text-[11px] text-slate-500 mt-0.5"></p>
                                </div>
                                <span id="remote-selected-badge" class="badge badge-muted">no target</span>
                            </div>
                            <div class="flex flex-wrap gap-2">
                                <button type="button" class="action-btn cyan" onclick="RemoteView.run('ListShares')">List shares</button>
                                <button type="button" class="action-btn cyan" ${needsElev} onclick="RemoteView.run('ListOpenFiles')">List open files${admin ? '' : ' 🔒'}</button>
                                <button type="button" class="action-btn cyan" ${needsElev} onclick="RemoteView.run('ListSessions')">List sessions${admin ? '' : ' 🔒'}</button>
                                <button type="button" class="action-btn cyan" ${needsElev} onclick="RemoteView.run('GetRemoteRegistry')">Remote registry${admin ? '' : ' 🔒'}</button>
                                <button type="button" class="action-btn amber" ${needsElev} onclick="RemoteView.ensureRemoteRegistry()">Ensure Remote Registry${admin ? '' : ' 🔒'}</button>
                            </div>
                            ${admin ? '<p class="text-[11px] text-slate-500">Open files / sessions need admin rights and WMI/RPC on the target (SMB browse alone is not enough).</p>' : '<p class="text-[11px] text-amber-400">Needs elevation for open files, sessions, and remote registry.</p>'}
                        </div>

                        <div id="remote-result" class="result-panel text-slate-500">Discover → select a PC → List shares.</div>
                    </div>
                </div>
            </div>
        `;
    },

    setBusy(msg) {
        const el = document.getElementById('remote-result');
        if (el) el.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${this.escape(msg)}</div>`;
    },

    showResult(message, data) {
        const el = document.getElementById('remote-result');
        if (!el) return;
        if (typeof ResultRenderer !== 'undefined') {
            ResultRenderer.mount(el, message, data);
        } else {
            el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
        }
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    isIp(s) {
        return /^\d{1,3}(\.\d{1,3}){3}$/.test(String(s || '').trim());
    },

    target() {
        return this._selected ? String(this._selected).trim() : '';
    },

    fallbackIp() {
        const m = this._selectedMeta;
        if (!m || !m.ip) return '';
        const ip = String(m.ip).trim();
        if (!this.isIp(ip)) return '';
        if (ip.toLowerCase() === String(this.target()).toLowerCase()) return '';
        return ip;
    },

    selectHost(name, ip) {
        const n = (name || '').trim();
        const i = (ip || '').trim();
        // Prefer LAN IP for CIM/net view — hostnames often stall when DNS/NetBIOS is broken
        const connect = (i && this.isIp(i)) ? i : (n || i);
        if (!connect) return;

        this._selected = connect;
        this._selectedMeta = {
            connect,
            name: n,
            ip: i && this.isIp(i) ? i : (this.isIp(n) ? n : ''),
            display: (n && i && n !== i) ? `${n} · ${i}` : connect
        };

        const label = document.getElementById('remote-selected-label');
        const sub = document.getElementById('remote-selected-sub');
        const badge = document.getElementById('remote-selected-badge');
        if (label) label.textContent = this._selectedMeta.display;
        if (sub) {
            sub.textContent = this.isIp(connect)
                ? `Connecting as ${connect} (LAN IP)`
                : `Connecting as ${connect} — if this times out, type the LAN IP and click Use`;
        }
        if (badge) {
            badge.className = 'badge badge-ok';
            badge.textContent = 'selected';
        }
        const manual = document.getElementById('remote-manual');
        if (manual) manual.value = connect;
        this.renderHostList();
        LiveConsole.log(`Remote target selected: ${this._selectedMeta.display} (connect=${connect})`, 'INFO');
    },

    selectManual() {
        const el = document.getElementById('remote-manual');
        const v = el && el.value ? el.value.trim() : '';
        if (!v) {
            alert('Enter a computer name or IP first.');
            return;
        }
        if (this.isIp(v)) this.selectHost('', v);
        else this.selectHost(v, '');
    },

    renderHostList() {
        const box = document.getElementById('remote-host-list');
        if (!box) return;
        if (!this._hosts.length) {
            box.innerHTML = '<div class="text-slate-500">No hosts yet. Click Discover computers.</div>';
            return;
        }
        const sel = this.target().toLowerCase();
        box.innerHTML = this._hosts.map((h, idx) => {
            const name = h.Name || h.IPAddress || 'host';
            const ip = h.IPAddress || '';
            const active = sel && (
                String(ip).toLowerCase() === sel ||
                String(name).toLowerCase() === sel
            );
            const online = h.Online ? 'text-emerald-400' : 'text-slate-500';
            return `
                <button type="button" data-idx="${idx}"
                    class="w-full text-left px-3 py-2 rounded-lg border ${active ? 'border-cyan-500/50 bg-cyan-500/10' : 'border-slate-800 hover:border-slate-600'} transition"
                    onclick="RemoteView.pickIndex(${idx})">
                    <div class="flex items-center justify-between gap-2">
                        <span class="text-slate-100 font-semibold truncate">${this.escape(name)}</span>
                        <span class="${online} text-[10px]">${h.Online ? 'up' : '—'}</span>
                    </div>
                    <div class="text-slate-500 mt-0.5 truncate">${this.escape(ip)}${h.Source ? ' · ' + this.escape(h.Source) : ''}</div>
                </button>
            `;
        }).join('');
    },

    pickIndex(idx) {
        const h = this._hosts[idx];
        if (!h) return;
        const name = h.Name || '';
        const ip = h.IPAddress || '';
        this.selectHost(name, ip);
    },

    looksLikeTimeout(res) {
        const msg = String((res && res.Message) || '');
        const code = res && (res.StatusCode || (res.Data && res.Data.StatusCode));
        return code === 504 || /timed?\s*out/i.test(msg) || /did not respond/i.test(msg) || /unreachable/i.test(msg);
    },

    async discover() {
        this.setBusy('Discovering computers (ARP / SMB)…');
        LiveConsole.log('Remote / DiscoverComputers', 'INFO');
        const res = await API.diagnostic('remote', 'DiscoverComputers', '', 20000);
        if (!res.Success) {
            this.showResult(res.Message || 'Discover failed', res.Data);
            LiveConsole.log(res.Message || 'Failed', 'ERROR');
            return;
        }
        this._hosts = API.asArray(res.Data);
        this.renderHostList();
        this.showResult(res.Message || `Found ${this._hosts.length} host(s)`, this._hosts);
        LiveConsole.log(res.Message || 'OK', 'SUCCESS');
        if (this._hosts.length === 1) {
            this.pickIndex(0);
        }
    },

    async runOnce(diagName, computerName, timeout) {
        const q = `ComputerName=${encodeURIComponent(computerName)}`;
        const extra = /GetRemoteRegistry/i.test(diagName)
            ? `&Hive=HKLM&Path=${encodeURIComponent('SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion')}`
            : '';
        return API.diagnostic('remote', diagName, q + extra, timeout);
    },

    async run(diagName) {
        const target = this.target();
        if (!target) {
            alert('Select a PC from Discover first (or type a name/IP and click Use).');
            return;
        }
        const adminOnly = /ListOpenFiles|ListSessions|GetRemoteRegistry/i.test(diagName);
        if (adminOnly && !window.__LOC_ADMIN) {
            alert('Needs elevation for this diagnostic.');
            return;
        }
        this.setBusy(`${diagName} on ${target}…`);
        LiveConsole.log(`Remote / ${diagName} → ${target}`, 'INFO');
        const timeout = /ListShares/i.test(diagName) ? 22000 : 28000;
        let res = await this.runOnce(diagName, target, timeout);

        // If hostname/path failed and we know a different LAN IP, retry once (common when Explorer works via \\IP)
        const altIp = this.fallbackIp();
        const canRetry = altIp && /ListShares|ListOpenFiles|ListSessions|GetRemoteRegistry|EnsureRemoteRegistry/i.test(diagName);
        if (!res.Success && canRetry && this.looksLikeTimeout(res)) {
            this.setBusy(`${diagName} retry via LAN IP ${altIp}…`);
            LiveConsole.log(`Remote / ${diagName} retry → ${altIp}`, 'WARN');
            res = await this.runOnce(diagName, altIp, timeout);
            if (res.Success) {
                // Stick to working IP for subsequent clicks
                const name = (this._selectedMeta && this._selectedMeta.name) || '';
                this.selectHost(name, altIp);
            }
        }

        if (res.Success) {
            LiveConsole.log(res.Message || 'OK', 'SUCCESS');
            this.showResult(res.Message, res.Data);
        } else {
            LiveConsole.log(res.Message || 'Failed', 'ERROR', res.Data);
            let msg = res.Message || 'Failed';
            if (this.looksLikeTimeout(res) && !this.isIp(target)) {
                msg += ' Tip: use the LAN IP (as in \\\\192.168.x.x) — hostname/WMI often times out while SMB-by-IP works.';
            }
            this.showResult(msg, res.Data);
        }
    },

    async ensureRemoteRegistry() {
        const target = this.target();
        if (!target) {
            alert('Select a PC first.');
            return;
        }
        if (!window.__LOC_ADMIN) {
            alert('Needs elevation.');
            return;
        }
        if (!confirm(`Start Remote Registry on ${target}?`)) return;
        this.setBusy(`Ensure Remote Registry on ${target}…`);
        let res = await API.action('remote', 'EnsureRemoteRegistry', { ComputerName: target }, 20000);
        const altIp = this.fallbackIp();
        if (!res.Success && altIp && this.looksLikeTimeout(res)) {
            this.setBusy(`Ensure Remote Registry retry via ${altIp}…`);
            res = await API.action('remote', 'EnsureRemoteRegistry', { ComputerName: altIp }, 20000);
        }
        this.showResult(res.Message || (res.Success ? 'OK' : 'Failed'), res.Data);
        LiveConsole.log(res.Message || 'EnsureRemoteRegistry', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
    }
};

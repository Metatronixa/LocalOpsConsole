const RemoteView = {
    _selected: null,
    _hosts: [],

    async render(container) {
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';
        this._selected = null;
        this._hosts = [];

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Remote</h2>
                        <p class="text-xs text-slate-400">Discover PCs on the LAN, select one, then list shares / sessions / open files.</p>
                    </div>
                    <button type="button" onclick="RemoteView.discover()" class="action-btn cyan">Discover computers</button>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <div class="lg:col-span-1 p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                        <h3 class="text-sm font-bold text-slate-100">Discovered PCs</h3>
                        <p class="text-[11px] text-slate-500">Click a row to select the target for share/session queries.</p>
                        <div id="remote-host-list" class="space-y-1 max-h-96 overflow-auto text-xs font-mono">
                            <div class="text-slate-500">Click Discover computers to scan ARP / SMB neighbors.</div>
                        </div>
                        <div class="pt-2 border-t border-slate-800 space-y-2">
                            <label class="text-[11px] text-slate-400">Or type name / IP</label>
                            <div class="flex gap-2">
                                <input id="remote-manual" type="text" placeholder="PC-NAME or 192.168.1.10"
                                    class="flex-1 px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200" />
                                <button type="button" class="action-btn emerald text-[11px]" onclick="RemoteView.selectManual()">Use</button>
                            </div>
                        </div>
                    </div>

                    <div class="lg:col-span-2 space-y-4">
                        <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                            <div class="flex items-center justify-between flex-wrap gap-2">
                                <div>
                                    <h3 class="text-sm font-bold text-slate-100">Selected target</h3>
                                    <p id="remote-selected-label" class="text-lg font-mono text-cyan-300 mt-1">None — select a PC first</p>
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
                            ${admin ? '' : '<p class="text-[11px] text-amber-400">Needs elevation for open files, sessions, and remote registry.</p>'}
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

    target() {
        return this._selected ? String(this._selected).trim() : '';
    },

    selectHost(name, ip) {
        const t = (name || ip || '').trim();
        if (!t) return;
        this._selected = t;
        const label = document.getElementById('remote-selected-label');
        const badge = document.getElementById('remote-selected-badge');
        if (label) label.textContent = t;
        if (badge) {
            badge.className = 'badge badge-ok';
            badge.textContent = 'selected';
        }
        const manual = document.getElementById('remote-manual');
        if (manual) manual.value = t;
        this.renderHostList();
        LiveConsole.log(`Remote target selected: ${t}`, 'INFO');
    },

    selectManual() {
        const el = document.getElementById('remote-manual');
        const v = el && el.value ? el.value.trim() : '';
        if (!v) {
            alert('Enter a computer name or IP first.');
            return;
        }
        this.selectHost(v, v);
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
            const key = String(name);
            const active = sel && (key.toLowerCase() === sel || String(ip).toLowerCase() === sel);
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
        // Prefer hostname-like Name when different from IP; else IP
        const name = h.Name || '';
        const ip = h.IPAddress || '';
        const prefer = (name && name !== ip) ? name : (ip || name);
        this.selectHost(prefer, ip);
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
        const q = `ComputerName=${encodeURIComponent(target)}`;
        // Shares path is bounded server-side (~8–10s); keep client slightly above that
        const timeout = /ListShares/i.test(diagName) ? 20000 : 25000;
        const extra = /GetRemoteRegistry/i.test(diagName)
            ? `&Hive=HKLM&Path=${encodeURIComponent('SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion')}`
            : '';
        const res = await API.diagnostic('remote', diagName, q + extra, timeout);
        if (res.Success) {
            LiveConsole.log(res.Message || 'OK', 'SUCCESS');
            this.showResult(res.Message, res.Data);
        } else {
            LiveConsole.log(res.Message || 'Failed', 'ERROR', res.Data);
            this.showResult(res.Message || 'Failed', res.Data);
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
        const res = await API.action('remote', 'EnsureRemoteRegistry', { ComputerName: target }, 20000);
        this.showResult(res.Message || (res.Success ? 'OK' : 'Failed'), res.Data);
        LiveConsole.log(res.Message || 'EnsureRemoteRegistry', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
    }
};

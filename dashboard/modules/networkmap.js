const NetworkMapView = {
    _data: null,
    _selected: null,

    async render(container) {
        this._selected = null;
        container.innerHTML = `
            <div class="space-y-4 fade-in networkmap-page">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Network Map</h2>
                        <p class="text-xs text-slate-400">Agents and LAN neighbors plotted by gateway. Click a node for details.</p>
                    </div>
                    <button type="button" class="action-btn cyan" onclick="NetworkMapView.refresh()">Refresh</button>
                </div>
                <div class="networkmap-legend text-[10px] font-mono text-slate-400 flex flex-wrap gap-3">
                    <span><i class="nmap-dot nmap-agent"></i> Agent</span>
                    <span><i class="nmap-dot nmap-lan"></i> LAN discovery</span>
                    <span><i class="nmap-dot nmap-gw"></i> Gateway</span>
                    <span><i class="nmap-dot nmap-console"></i> Console</span>
                    <span><i class="nmap-dot nmap-off"></i> Offline</span>
                </div>
                <div class="networkmap-shell glass-panel">
                    <div id="networkmap-canvas" class="networkmap-canvas"></div>
                    <aside id="networkmap-detail" class="networkmap-detail">
                        <p class="text-[11px] text-slate-500">Select a node</p>
                    </aside>
                </div>
            </div>
        `;
        await this.refresh();
    },

    async refresh() {
        const canvas = document.getElementById('networkmap-canvas');
        if (canvas) canvas.innerHTML = '<p class="text-slate-500 text-xs p-4">Loading topology…</p>';
        const res = await API.request('fleet/topology', 'GET', null, 45000);
        if (!res.Success || !res.Data) {
            if (canvas) canvas.innerHTML = `<p class="text-rose-400 text-xs p-4">${this.escape(res.Message || 'Failed to load topology')}</p>`;
            return;
        }
        this._data = res.Data;
        this.draw();
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    layoutNodes(nodes, edges, w, h) {
        const hubs = nodes.filter((n) => n.Kind === 'gateway');
        const consoleNode = nodes.find((n) => n.Kind === 'console');
        const leaves = nodes.filter((n) => n.Kind === 'agent' || n.Kind === 'lan');
        const pos = {};
        const cx = w / 2;
        const cy = h / 2;

        if (!hubs.length) {
            pos['hub-lan'] = { x: cx, y: cy };
        } else {
            hubs.forEach((hub, i) => {
                const angle = (Math.PI * 2 * i) / Math.max(hubs.length, 1) - Math.PI / 2;
                const r = hubs.length === 1 ? 0 : Math.min(w, h) * 0.18;
                pos[hub.Id] = { x: cx + Math.cos(angle) * r, y: cy + Math.sin(angle) * r };
            });
        }

        if (consoleNode) {
            const hubId = (edges.find((e) => e.From === consoleNode.Id) || {}).To;
            const hp = pos[hubId] || { x: cx, y: cy };
            pos[consoleNode.Id] = { x: hp.x, y: hp.y - Math.min(h, w) * 0.22 };
        }

        const byHub = {};
        leaves.forEach((n) => {
            const e = edges.find((x) => x.From === n.Id);
            const hubId = e ? e.To : (hubs[0] && hubs[0].Id) || 'hub-lan';
            if (!byHub[hubId]) byHub[hubId] = [];
            byHub[hubId].push(n);
        });

        Object.keys(byHub).forEach((hubId) => {
            const group = byHub[hubId];
            const hp = pos[hubId] || { x: cx, y: cy };
            const ring = Math.min(w, h) * 0.32;
            group.forEach((n, i) => {
                const angle = (Math.PI * 2 * i) / Math.max(group.length, 1) - Math.PI / 2;
                pos[n.Id] = {
                    x: hp.x + Math.cos(angle) * ring,
                    y: hp.y + Math.sin(angle) * ring
                };
            });
        });

        nodes.forEach((n) => {
            if (!pos[n.Id]) pos[n.Id] = { x: cx + (Math.random() - 0.5) * 80, y: cy + (Math.random() - 0.5) * 80 };
        });
        return pos;
    },

    kindClass(n) {
        if (!n.Online && (n.Kind === 'agent' || n.Kind === 'lan')) return 'nmap-off';
        if (n.Kind === 'agent') return 'nmap-agent';
        if (n.Kind === 'lan') return 'nmap-lan';
        if (n.Kind === 'gateway') return 'nmap-gw';
        if (n.Kind === 'console') return 'nmap-console';
        return 'nmap-lan';
    },

    draw() {
        const canvas = document.getElementById('networkmap-canvas');
        if (!canvas || !this._data) return;
        const nodes = API.asArray(this._data.Nodes);
        const edges = API.asArray(this._data.Edges);
        const w = Math.max(canvas.clientWidth || 720, 640);
        const h = Math.max(420, Math.min(640, 280 + nodes.length * 12));
        const pos = this.layoutNodes(nodes, edges, w, h);

        let lines = '';
        edges.forEach((e) => {
            const a = pos[e.From];
            const b = pos[e.To];
            if (!a || !b) return;
            lines += `<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" class="nmap-edge nmap-edge-${this.escape(e.Kind || 'lan')}" />`;
        });

        let circles = '';
        nodes.forEach((n) => {
            const p = pos[n.Id];
            if (!p) return;
            const r = n.Kind === 'gateway' ? 16 : (n.Kind === 'console' ? 14 : 11);
            const label = `${n.Label || ''}${n.IPv4 ? '\\n' + n.IPv4 : ''}`;
            const linesOf = String(n.Label || n.Id).slice(0, 18);
            const ipLine = n.IPv4 ? String(n.IPv4) : '';
            circles += `
              <g class="nmap-node ${this.kindClass(n)}" data-id="${this.escape(n.Id)}" onclick="NetworkMapView.selectNode('${this.escape(n.Id)}')" style="cursor:pointer">
                <circle cx="${p.x}" cy="${p.y}" r="${r}" />
                <text x="${p.x}" y="${p.y + r + 12}" text-anchor="middle" class="nmap-label">${this.escape(linesOf)}</text>
                ${ipLine ? `<text x="${p.x}" y="${p.y + r + 24}" text-anchor="middle" class="nmap-ip">${this.escape(ipLine)}</text>` : ''}
              </g>`;
        });

        canvas.innerHTML = `
            <div class="text-[10px] text-slate-500 font-mono px-3 pt-2">${nodes.length} nodes · ${this._data.Agents || 0} agents · ${this._data.LanHosts || 0} LAN</div>
            <svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" class="networkmap-svg">${lines}${circles}</svg>
        `;

        if (this._selected) this.selectNode(this._selected, true);
    },

    selectNode(id, silent) {
        this._selected = id;
        const n = API.asArray(this._data && this._data.Nodes).find((x) => x.Id === id);
        const box = document.getElementById('networkmap-detail');
        if (!box) return;
        if (!n) {
            box.innerHTML = '<p class="text-[11px] text-slate-500">Select a node</p>';
            return;
        }
        const openFleet = n.Kind === 'agent' && n.AgentId
            ? `<button type="button" class="action-btn cyan text-[11px] mt-3" onclick="NetworkMapView.openInComputers('${this.escape(n.AgentId)}')">Open in Computers</button>`
            : '';
        box.innerHTML = `
            <div class="section-title">${this.escape(n.Kind)}</div>
            <h3 class="text-sm font-bold text-slate-100">${this.escape(n.Label || n.Id)}</h3>
            <dl class="mt-3 space-y-1 text-[11px] font-mono">
                <div class="flex justify-between gap-2"><dt class="text-slate-500">IP</dt><dd class="text-slate-200">${this.escape(n.IPv4 || '—')}</dd></div>
                <div class="flex justify-between gap-2"><dt class="text-slate-500">Gateway</dt><dd class="text-slate-200">${this.escape(n.Gateway || '—')}</dd></div>
                <div class="flex justify-between gap-2"><dt class="text-slate-500">Online</dt><dd class="text-slate-200">${n.Online ? 'yes' : 'no'}</dd></div>
                ${n.UserName ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">User</dt><dd class="text-slate-200">${this.escape(n.UserName)}</dd></div>` : ''}
                ${n.WindowsVersion ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">OS</dt><dd class="text-slate-200">${this.escape(n.WindowsVersion)}</dd></div>` : ''}
                ${n.MACAddress ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">MAC</dt><dd class="text-slate-200">${this.escape(n.MACAddress)}</dd></div>` : ''}
            </dl>
            ${openFleet}
        `;
        if (!silent) {
            document.querySelectorAll('.nmap-node').forEach((el) => {
                el.classList.toggle('is-selected', el.getAttribute('data-id') === id);
            });
        }
    },

    openInComputers(agentId) {
        if (typeof Router !== 'undefined' && Router.loadModuleView) {
            Router.loadModuleView('fleet').then(() => {
                if (typeof FleetView !== 'undefined' && FleetView.select) {
                    setTimeout(() => FleetView.select(agentId), 350);
                }
            });
        }
    }
};

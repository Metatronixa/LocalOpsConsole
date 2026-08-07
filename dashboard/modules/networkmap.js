const NetworkMapView = {
    _data: null,
    _selected: null,
    _mode: 'map', // map | list
    _filters: { agents: true, lan: true, offline: true },
    _listSort: { key: 'Label', dir: 1 },

    deviceTypes: [
        { value: 'auto', label: 'Auto (detect)' },
        { value: 'pc', label: 'PC' },
        { value: 'router', label: 'Router / AP' },
        { value: 'switch', label: 'Switch' },
        { value: 'nas', label: 'NAS' },
        { value: 'playstation', label: 'PlayStation' },
        { value: 'xbox', label: 'Xbox' },
        { value: 'unknown', label: 'Unknown' }
    ],

    async render(container) {
        this._selected = null;
        container.innerHTML = `
            <div class="space-y-4 fade-in networkmap-page">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Network Map</h2>
                        <p class="text-xs text-slate-400">Agents and LAN neighbors by gateway cluster. Use List when the LAN is crowded.</p>
                    </div>
                    <div class="flex flex-wrap items-center gap-2">
                        <div class="nmap-mode-toggle" role="group" aria-label="View mode">
                            <button type="button" id="nmap-mode-map" class="nmap-mode-btn is-active" onclick="NetworkMapView.setMode('map')">Map</button>
                            <button type="button" id="nmap-mode-list" class="nmap-mode-btn" onclick="NetworkMapView.setMode('list')">List</button>
                        </div>
                        <button type="button" class="action-btn cyan" onclick="NetworkMapView.refresh()">Refresh</button>
                    </div>
                </div>
                <div class="networkmap-toolbar flex flex-wrap items-center gap-2 text-[10px] font-mono">
                    <span class="text-slate-500 mr-1">Show:</span>
                    <button type="button" class="nmap-filter-chip is-on" data-filter="agents" onclick="NetworkMapView.toggleFilter('agents')">Agents</button>
                    <button type="button" class="nmap-filter-chip is-on" data-filter="lan" onclick="NetworkMapView.toggleFilter('lan')">LAN</button>
                    <button type="button" class="nmap-filter-chip is-on" data-filter="offline" onclick="NetworkMapView.toggleFilter('offline')">Offline</button>
                    <span class="text-slate-600 mx-1">·</span>
                    <span class="networkmap-legend text-slate-400 flex flex-wrap gap-3">
                        <span><i class="nmap-dot nmap-agent"></i> Agent</span>
                        <span><i class="nmap-dot nmap-lan"></i> LAN</span>
                        <span><i class="nmap-dot nmap-gw"></i> Gateway</span>
                        <span><i class="nmap-dot nmap-console"></i> Console</span>
                        <span><i class="nmap-dot nmap-off"></i> Offline</span>
                    </span>
                </div>
                <div id="nmap-dense-hint" class="hidden text-[11px] text-amber-400/90 px-1"></div>
                <div class="networkmap-shell glass-panel">
                    <div id="networkmap-canvas" class="networkmap-canvas"></div>
                    <aside id="networkmap-detail" class="networkmap-detail">
                        <p class="text-[11px] text-slate-500">Select a node</p>
                    </aside>
                </div>
            </div>
        `;
        this.syncChrome();
        await this.refresh();
    },

    syncChrome() {
        const mapBtn = document.getElementById('nmap-mode-map');
        const listBtn = document.getElementById('nmap-mode-list');
        if (mapBtn) mapBtn.classList.toggle('is-active', this._mode === 'map');
        if (listBtn) listBtn.classList.toggle('is-active', this._mode === 'list');
        document.querySelectorAll('.nmap-filter-chip').forEach((el) => {
            const key = el.getAttribute('data-filter');
            el.classList.toggle('is-on', !!this._filters[key]);
        });
    },

    setMode(mode) {
        this._mode = mode === 'list' ? 'list' : 'map';
        this.syncChrome();
        this.draw();
    },

    toggleFilter(key) {
        if (!Object.prototype.hasOwnProperty.call(this._filters, key)) return;
        this._filters[key] = !this._filters[key];
        this.syncChrome();
        this.draw();
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
        const n = API.asArray(this._data.Nodes).length;
        const hint = document.getElementById('nmap-dense-hint');
        if (hint) {
            if (n > 25 && this._mode === 'map') {
                hint.classList.remove('hidden');
                hint.innerHTML = `${n} nodes — Map can get crowded. <button type="button" class="underline text-amber-300" onclick="NetworkMapView.setMode('list')">Switch to List</button>`;
            } else {
                hint.classList.add('hidden');
                hint.innerHTML = '';
            }
        }
        this.draw();
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    nodePassesFilter(n) {
        const f = this._filters;
        if (n.Kind === 'gateway' || n.Kind === 'console') return true;
        const offline = !n.Online && (n.Kind === 'agent' || n.Kind === 'lan');
        if (offline && !f.offline) return false;
        if (n.Kind === 'agent' && !f.agents) return false;
        if (n.Kind === 'lan' && !f.lan) return false;
        return true;
    },

    filteredGraph() {
        const allNodes = API.asArray(this._data && this._data.Nodes);
        const allEdges = API.asArray(this._data && this._data.Edges);
        const nodes = allNodes.filter((n) => this.nodePassesFilter(n));
        const ids = new Set(nodes.map((n) => n.Id));
        const edges = allEdges.filter((e) => ids.has(e.From) && ids.has(e.To));
        return { nodes, edges };
    },

    /** Minimum ring radius so chord between neighbors stays above node diameter + gap. */
    ringRadius(count, nodeSize, gap, base) {
        const n = Math.max(count, 1);
        if (n <= 1) return base;
        const needed = ((nodeSize + gap) * n) / (2 * Math.PI);
        return Math.max(base, needed);
    },

    /**
     * Place nodes on one or more concentric rings; spill when a single ring would still be tight.
     * Returns array of { id, x, y, angle } relative to hub center (0,0).
     */
    placeOnRings(items, nodeSize, gap, baseRadius) {
        const out = [];
        if (!items.length) return out;
        const maxPerRing = Math.max(6, Math.floor((2 * Math.PI * baseRadius) / (nodeSize + gap)));
        let remaining = items.slice();
        let ringIndex = 0;
        while (remaining.length) {
            const capacity = Math.max(maxPerRing + ringIndex * 4, 8);
            const take = remaining.splice(0, Math.min(capacity, remaining.length));
            const r = this.ringRadius(take.length, nodeSize, gap, baseRadius + ringIndex * (nodeSize + gap + 8));
            take.forEach((n, i) => {
                const angle = (Math.PI * 2 * i) / Math.max(take.length, 1) - Math.PI / 2;
                out.push({
                    id: n.Id,
                    x: Math.cos(angle) * r,
                    y: Math.sin(angle) * r,
                    angle,
                    ring: ringIndex
                });
            });
            ringIndex++;
        }
        return out;
    },

    clusterFootprint(agents, lan) {
        const nodeSize = 13;
        const gap = 16;
        const agentPlaced = this.placeOnRings(agents, nodeSize, gap, 56);
        const lanBase = 56 + (agents.length ? this.ringRadius(Math.min(agents.length, 12), nodeSize, gap, 56) + nodeSize + gap + 12 : 0);
        const lanPlaced = this.placeOnRings(lan, nodeSize, gap, Math.max(lanBase, 88));
        let maxR = 40;
        agentPlaced.concat(lanPlaced).forEach((p) => {
            const d = Math.sqrt(p.x * p.x + p.y * p.y) + 36;
            if (d > maxR) maxR = d;
        });
        return { agentPlaced, lanPlaced, radius: maxR };
    },

    layoutNodes(nodes, edges, w, h) {
        const hubs = nodes.filter((n) => n.Kind === 'gateway');
        const consoleNode = nodes.find((n) => n.Kind === 'console');
        const leaves = nodes.filter((n) => n.Kind === 'agent' || n.Kind === 'lan');
        const pos = {};
        const padX = 48;
        const padY = 56;

        const byHub = {};
        leaves.forEach((n) => {
            const e = edges.find((x) => x.From === n.Id);
            const hubId = e ? e.To : (hubs[0] && hubs[0].Id) || 'hub-lan';
            if (!byHub[hubId]) byHub[hubId] = [];
            byHub[hubId].push(n);
        });

        const hubList = hubs.length ? hubs.slice() : [{ Id: 'hub-lan', Kind: 'gateway', Label: 'LAN' }];
        const footprints = hubList.map((hub) => {
            const group = byHub[hub.Id] || [];
            const agents = group.filter((n) => n.Kind === 'agent');
            const lan = group.filter((n) => n.Kind === 'lan');
            const fp = this.clusterFootprint(agents, lan);
            return { hub, agents, lan, ...fp };
        });

        const gapBetween = 36;
        const widths = footprints.map((fp) => Math.max(fp.radius * 2, 120));
        const totalW = widths.reduce((a, b) => a + b, 0) + gapBetween * Math.max(footprints.length - 1, 0);
        const contentW = Math.max(w - padX * 2, totalW);
        const scaleX = totalW > 0 && totalW > contentW ? contentW / totalW : 1;

        let maxClusterH = 160;
        footprints.forEach((fp) => {
            const ch = fp.radius * 2 + 48;
            if (ch > maxClusterH) maxClusterH = ch;
        });

        let cursorX = padX + (Math.max(w - padX * 2 - totalW * scaleX, 0) / 2);
        const hubY = padY + maxClusterH / 2;

        footprints.forEach((fp, i) => {
            const colW = widths[i] * scaleX;
            const hx = cursorX + colW / 2;
            const hy = hubY;
            pos[fp.hub.Id] = { x: hx, y: hy };

            fp.agentPlaced.forEach((p) => {
                pos[p.id] = { x: hx + p.x * scaleX, y: hy + p.y, angle: p.angle };
            });
            fp.lanPlaced.forEach((p) => {
                pos[p.id] = { x: hx + p.x * scaleX, y: hy + p.y, angle: p.angle };
            });

            cursorX += colW + gapBetween * scaleX;
        });

        if (consoleNode) {
            const hubId = (edges.find((e) => e.From === consoleNode.Id) || {}).To;
            const hp = pos[hubId] || pos[hubList[0].Id] || { x: w / 2, y: hubY };
            pos[consoleNode.Id] = { x: hp.x, y: Math.max(28, hp.y - Math.max(72, maxClusterH * 0.42)) };
        }

        nodes.forEach((n) => {
            if (!pos[n.Id]) pos[n.Id] = { x: w / 2, y: hubY };
        });

        return { pos, contentHeight: Math.ceil(padY + maxClusterH + padY + 40) };
    },

    labelOffsets(p, r) {
        const angle = typeof p.angle === 'number' ? p.angle : -Math.PI / 2;
        // Push labels radially outward to reduce overlap with neighbors
        const lx = Math.cos(angle) * (r + 8);
        const ly = Math.sin(angle) * (r + 8);
        const anchor = Math.cos(angle) > 0.25 ? 'start' : (Math.cos(angle) < -0.25 ? 'end' : 'middle');
        return {
            labelX: p.x + lx * 0.15,
            labelY: p.y + r + 12 + Math.max(0, Math.sin(angle) * 4),
            ipY: p.y + r + 24 + Math.max(0, Math.sin(angle) * 4),
            anchor
        };
    },

    kindClass(n) {
        if (!n.Online && (n.Kind === 'agent' || n.Kind === 'lan')) return 'nmap-off';
        if (n.Kind === 'agent') return 'nmap-agent';
        if (n.Kind === 'lan') return 'nmap-lan';
        if (n.Kind === 'gateway') return 'nmap-gw';
        if (n.Kind === 'console') return 'nmap-console';
        return 'nmap-lan';
    },

    deviceType(n) {
        return String(n.DeviceType || n.deviceType || 'unknown').toLowerCase();
    },

    iconPaths(type) {
        switch (type) {
            case 'pc':
                return '<rect x="4" y="5" width="16" height="11" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 19h8M12 16v3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>';
            case 'router':
                return '<path d="M5 15h14v4H5z" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="8" cy="17" r="1" fill="currentColor"/><circle cx="12" cy="17" r="1" fill="currentColor"/><path d="M7 11c2-3 8-3 10 0M8.5 8.5c1.5-2 5.5-2 7 0M10 6c1-1.2 3-1.2 4 0" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>';
            case 'switch':
                return '<rect x="3" y="8" width="18" height="8" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M6 11h2M10 11h2M14 11h2M18 11h1M6 14h2M10 14h2M14 14h2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>';
            case 'nas':
                return '<rect x="5" y="4" width="14" height="16" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 8h8M8 12h8M8 16h5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="15.5" cy="16" r="1" fill="currentColor"/>';
            case 'playstation':
            case 'xbox':
                return '<rect x="3" y="8" width="18" height="10" rx="3" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="8" cy="13" r="1.4" fill="none" stroke="currentColor" stroke-width="1.3"/><circle cx="16" cy="13" r="1.4" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M11 12h2M12 11v2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>';
            default:
                return '<circle cx="12" cy="12" r="6" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M12 9v3M12 15.5v.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>';
        }
    },

    nodeIconSvg(n, x, y, r) {
        const type = this.deviceType(n);
        const scale = (r * 1.15) / 12;
        const paths = this.iconPaths(type);
        return `<g class="nmap-icon nmap-dtype-${this.escape(type)}" transform="translate(${x - 12 * scale}, ${y - 12 * scale}) scale(${scale})">${paths}</g>`;
    },

    draw() {
        if (!this._data) return;
        this.syncChrome();
        const hint = document.getElementById('nmap-dense-hint');
        const allCount = API.asArray(this._data.Nodes).length;
        if (hint) {
            if (allCount > 25 && this._mode === 'map') {
                hint.classList.remove('hidden');
                hint.innerHTML = `${allCount} nodes — Map can get crowded. <button type="button" class="underline text-amber-300" onclick="NetworkMapView.setMode('list')">Switch to List</button>`;
            } else {
                hint.classList.add('hidden');
                hint.innerHTML = '';
            }
        }
        if (this._mode === 'list') this.drawList();
        else this.drawMap();
        if (this._selected) this.selectNode(this._selected, true);
    },

    drawMap() {
        const canvas = document.getElementById('networkmap-canvas');
        if (!canvas || !this._data) return;
        const { nodes, edges } = this.filteredGraph();
        const w = Math.max(canvas.clientWidth || 720, 640);

        // Pre-layout to learn needed height, then layout again with room
        const probe = this.layoutNodes(nodes, edges, w, 800);
        const h = Math.max(420, probe.contentHeight || 420, 280 + nodes.length * 8);
        const { pos } = this.layoutNodes(nodes, edges, w, h);

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
            const r = n.Kind === 'gateway' ? 18 : (n.Kind === 'console' ? 16 : 13);
            const linesOf = String(n.Label || n.Id).slice(0, 18);
            const ipLine = n.IPv4 ? String(n.IPv4) : '';
            const dtype = this.deviceType(n);
            const lo = this.labelOffsets(p, r);
            circles += `
              <g class="nmap-node ${this.kindClass(n)}" data-id="${this.escape(n.Id)}" onclick="NetworkMapView.selectNode('${this.escape(n.Id)}')" style="cursor:pointer">
                <circle cx="${p.x}" cy="${p.y}" r="${r}" />
                ${this.nodeIconSvg(n, p.x, p.y, r)}
                <title>${this.escape(n.Label || n.Id)} · ${this.escape(dtype)}${ipLine ? ' · ' + this.escape(ipLine) : ''}</title>
                <text x="${lo.labelX}" y="${lo.labelY}" text-anchor="${lo.anchor}" class="nmap-label">${this.escape(linesOf)}</text>
                ${ipLine ? `<text x="${lo.labelX}" y="${lo.ipY}" text-anchor="${lo.anchor}" class="nmap-ip">${this.escape(ipLine)}</text>` : ''}
              </g>`;
        });

        canvas.innerHTML = `
            <div class="text-[10px] text-slate-500 font-mono px-3 pt-2">${nodes.length} shown · ${this._data.Agents || 0} agents · ${this._data.LanHosts || 0} LAN · gateway clusters</div>
            <div class="networkmap-svg-wrap">
                <svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" class="networkmap-svg">${lines}${circles}</svg>
            </div>
        `;
    },

    sortList(key) {
        if (this._listSort.key === key) this._listSort.dir *= -1;
        else this._listSort = { key, dir: 1 };
        this.drawList();
    },

    drawList() {
        const canvas = document.getElementById('networkmap-canvas');
        if (!canvas || !this._data) return;
        const { nodes } = this.filteredGraph();
        const key = this._listSort.key;
        const dir = this._listSort.dir;
        const sorted = nodes.slice().sort((a, b) => {
            const av = a[key] != null ? a[key] : (key === 'Online' ? !!a.Online : (a.Label || a.Id || ''));
            const bv = b[key] != null ? b[key] : (key === 'Online' ? !!b.Online : (b.Label || b.Id || ''));
            if (key === 'Online') {
                const an = av ? 1 : 0;
                const bn = bv ? 1 : 0;
                return (an - bn) * dir;
            }
            return String(av).localeCompare(String(bv), undefined, { sensitivity: 'base', numeric: true }) * dir;
        });

        const mark = (k) => (this._listSort.key === k ? (this._listSort.dir > 0 ? ' ▲' : ' ▼') : '');
        const rows = sorted.map((n) => {
            const sel = this._selected === n.Id ? 'is-selected' : '';
            const on = n.Online ? 'yes' : 'no';
            const onCls = n.Online ? 'text-emerald-400' : 'text-slate-500';
            return `<tr class="nmap-list-row ${sel}" data-id="${this.escape(n.Id)}" onclick="NetworkMapView.selectNode('${this.escape(n.Id)}')">
                <td><span class="nmap-dot ${this.kindClass(n)}"></span>${this.escape(n.Kind)}</td>
                <td class="text-slate-100">${this.escape(n.Label || n.Id)}</td>
                <td class="font-mono text-slate-300">${this.escape(n.IPv4 || '—')}</td>
                <td class="${onCls}">${on}</td>
                <td class="text-slate-400">${this.escape(this.deviceType(n))}</td>
                <td class="text-slate-500 font-mono">${this.escape(n.Gateway || '—')}</td>
            </tr>`;
        }).join('');

        canvas.innerHTML = `
            <div class="text-[10px] text-slate-500 font-mono px-3 pt-2">${sorted.length} shown · click a row for details</div>
            <div class="nmap-list-wrap">
                <table class="nmap-list-table">
                    <thead>
                        <tr>
                            <th onclick="NetworkMapView.sortList('Kind')">Kind${mark('Kind')}</th>
                            <th onclick="NetworkMapView.sortList('Label')">Label${mark('Label')}</th>
                            <th onclick="NetworkMapView.sortList('IPv4')">IP${mark('IPv4')}</th>
                            <th onclick="NetworkMapView.sortList('Online')">Online${mark('Online')}</th>
                            <th onclick="NetworkMapView.sortList('DeviceType')">Type${mark('DeviceType')}</th>
                            <th onclick="NetworkMapView.sortList('Gateway')">Gateway${mark('Gateway')}</th>
                        </tr>
                    </thead>
                    <tbody>${rows || '<tr><td colspan="6" class="text-slate-500 p-4">No nodes match filters</td></tr>'}</tbody>
                </table>
            </div>
        `;
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
        const dtype = this.deviceType(n);
        const inferred = String(n.DeviceTypeInferred || n.deviceTypeInferred || dtype);
        const override = n.DeviceTypeOverride || n.deviceTypeOverride || '';
        const selectVal = override ? String(override).toLowerCase() : 'auto';
        const options = this.deviceTypes.map((t) =>
            `<option value="${t.value}" ${selectVal === t.value ? 'selected' : ''}>${t.label}</option>`
        ).join('');
        const openFleet = n.Kind === 'agent' && n.AgentId
            ? `<button type="button" class="action-btn cyan text-[11px] mt-3 w-full" onclick="NetworkMapView.openInComputers('${this.escape(n.AgentId)}')">Open in Computers</button>`
            : '';
        box.innerHTML = `
            <div class="section-title flex items-center gap-2">
                <span class="nmap-detail-badge nmap-dtype-${this.escape(dtype)}">${this.escape(dtype)}</span>
                <span class="text-slate-500">${this.escape(n.Kind)}</span>
            </div>
            <h3 class="text-sm font-bold text-slate-100 mt-1">${this.escape(n.Label || n.Id)}</h3>
            <dl class="mt-3 space-y-1.5 text-[11px] font-mono">
                <div class="flex justify-between gap-2"><dt class="text-slate-500">IP</dt><dd class="text-slate-200">${this.escape(n.IPv4 || '—')}</dd></div>
                <div class="flex justify-between gap-2"><dt class="text-slate-500">MAC</dt><dd class="text-slate-200 break-all text-right">${this.escape(n.MACAddress || '—')}</dd></div>
                <div class="flex justify-between gap-2"><dt class="text-slate-500">Gateway</dt><dd class="text-slate-200">${this.escape(n.Gateway || '—')}</dd></div>
                <div class="flex justify-between gap-2"><dt class="text-slate-500">Online</dt><dd class="${n.Online ? 'text-emerald-400' : 'text-slate-400'}">${n.Online ? 'yes' : 'no'}</dd></div>
                <div class="flex justify-between gap-2"><dt class="text-slate-500">Source</dt><dd class="text-slate-200">${this.escape(n.Source || '—')}</dd></div>
                ${n.NeighborState ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">Neighbor</dt><dd class="text-slate-200">${this.escape(n.NeighborState)}</dd></div>` : ''}
                ${n.UserName ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">User</dt><dd class="text-slate-200">${this.escape(n.UserName)}</dd></div>` : ''}
                ${n.WindowsVersion ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">OS</dt><dd class="text-slate-200 text-right">${this.escape(n.WindowsVersion)}</dd></div>` : ''}
                ${n.AgentId ? `<div class="flex justify-between gap-2"><dt class="text-slate-500">Agent</dt><dd class="text-cyan-300 break-all text-right">${this.escape(n.AgentId)}</dd></div>` : ''}
                <div class="flex justify-between gap-2"><dt class="text-slate-500">Detected</dt><dd class="text-slate-200">${this.escape(inferred)}</dd></div>
            </dl>
            <label class="block mt-4 text-[11px] text-slate-400">
                Device type
                <select id="nmap-dtype-select" class="mt-1 w-full px-2 py-1.5 rounded-lg bg-slate-900 border border-slate-800 text-slate-200 text-xs"
                        onchange="NetworkMapView.saveDeviceType('${this.escape(n.Id)}', this.value)">
                    ${options}
                </select>
            </label>
            <p class="text-[10px] text-slate-500 mt-2">Override is saved locally. Choose Auto to clear.</p>
            <div id="nmap-dtype-status" class="text-[10px] text-slate-500 mt-1"></div>
            ${openFleet}
        `;
        if (!silent) {
            document.querySelectorAll('.nmap-node').forEach((el) => {
                el.classList.toggle('is-selected', el.getAttribute('data-id') === id);
            });
            document.querySelectorAll('.nmap-list-row').forEach((el) => {
                el.classList.toggle('is-selected', el.getAttribute('data-id') === id);
            });
        } else {
            document.querySelectorAll('.nmap-list-row').forEach((el) => {
                el.classList.toggle('is-selected', el.getAttribute('data-id') === id);
            });
            document.querySelectorAll('.nmap-node').forEach((el) => {
                el.classList.toggle('is-selected', el.getAttribute('data-id') === id);
            });
        }
    },

    async saveDeviceType(nodeId, deviceType) {
        const n = API.asArray(this._data && this._data.Nodes).find((x) => x.Id === nodeId);
        const status = document.getElementById('nmap-dtype-status');
        if (status) status.textContent = 'Saving…';
        const res = await API.request('fleet/topology/device-type', 'POST', {
            NodeId: nodeId,
            DeviceType: deviceType,
            MACAddress: n && n.MACAddress ? n.MACAddress : '',
            IPv4: n && n.IPv4 ? n.IPv4 : ''
        }, 10000);
        if (!res.Success) {
            if (status) {
                status.textContent = res.Message || 'Save failed';
                status.className = 'text-[10px] text-rose-400 mt-1';
            }
            return;
        }
        if (status) {
            status.textContent = res.Message || 'Saved';
            status.className = 'text-[10px] text-emerald-400 mt-1';
        }
        await this.refresh();
        this.selectNode(nodeId, true);
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

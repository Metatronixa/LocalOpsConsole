const FleetView = {
    _agents: [],
    _selected: null,
    _selectedCmdId: null,
    _pollTimer: null,
    _lastLatency: null,
    _scripts: [],
    _drawerOpen: false,
    _detailCache: null,

    // Wave B–D backlog moved to docs/AGENT_ROADMAP.md

    async render(container) {
        this._selected = null;
        this._selectedCmdId = null;
        this._lastLatency = null;
        this._drawerOpen = false;
        this._detailCache = null;
        this._packages = [];
        this._agentPackage = null;
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Computers</h2>
                        <p class="text-xs text-slate-400">Select a PC for live telemetry and grouped remote actions. Tailscale: set fleetPublicUrl to http://&lt;tailscale-ip&gt;:8787.</p>
                    </div>
                    <button type="button" onclick="FleetView.refresh()" class="action-btn cyan">Refresh</button>
                </div>

                <details class="fleet-enroll glass-panel p-4">
                    <summary class="text-sm font-bold text-slate-100 cursor-pointer select-none">Enrollment</summary>
                    <div class="mt-3 grid grid-cols-1 lg:grid-cols-2 gap-4 text-xs">
                        <div>
                            <label class="text-slate-400">Enrollment token</label>
                            <div class="flex gap-2 mt-1">
                                <input id="fleet-token" readonly class="flex-1 px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 font-mono text-slate-200" />
                                <button type="button" class="action-btn emerald" onclick="FleetView.copyToken()">Copy</button>
                                <button type="button" class="action-btn amber" onclick="FleetView.rotateToken()">Rotate</button>
                            </div>
                            <p class="text-[10px] text-slate-500 mt-1">One shared enroll token for new PCs. After enroll each PC gets its own AgentSecret (HMAC). Rotate if the token leaks.</p>
                        </div>
                        <div>
                            <label class="text-slate-400">Install one-liner (run as Admin on target PC)</label>
                            <textarea id="fleet-install-cmd" readonly rows="2" class="w-full mt-1 px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 font-mono text-[11px] text-slate-300"></textarea>
                            <button type="button" class="action-btn cyan mt-1 text-[11px]" onclick="FleetView.copyInstall()">Copy install command</button>
                        </div>
                    </div>
                    <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
                        <span class="text-slate-400">Published agent package:</span>
                        <span id="fleet-pkg-version" class="font-mono text-cyan-300">—</span>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.publishAgentPackage()">Publish agent package</button>
                    </div>
                    <p class="text-[10px] text-slate-500 mt-1">Publish copies agent/LocalOpsAgent.ps1 into data/fleet/agent-package for drawer self-update. Pre-2.2.0 agents need one manual install first.</p>
                    <p id="fleet-url-hint" class="text-[11px] text-slate-500 mt-2"></p>
                    <p id="fleet-bind-warn" class="hidden text-[11px] text-rose-400 font-semibold mt-1"></p>
                </details>

                <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800">
                    <div class="flex items-center justify-between mb-3 gap-2 flex-wrap">
                        <h3 class="text-sm font-bold text-slate-100">Managed computers</h3>
                        <p class="text-[11px] text-slate-500">Click a row to open the agent drawer</p>
                    </div>
                    <div class="overflow-x-auto">
                        <table class="w-full text-xs">
                            <thead>
                                <tr class="text-slate-500 text-left border-b border-slate-800">
                                    <th class="py-2 pr-2">Name</th>
                                    <th class="py-2 pr-2">Online</th>
                                    <th class="py-2 pr-2">CPU</th>
                                    <th class="py-2 pr-2">RAM</th>
                                    <th class="py-2 pr-2">Disk free</th>
                                    <th class="py-2 pr-2">Disk R/W</th>
                                    <th class="py-2 pr-2">Net</th>
                                    <th class="py-2 pr-2">Last seen</th>
                                    <th class="py-2">Agent</th>
                                </tr>
                            </thead>
                            <tbody id="fleet-agent-rows">
                                <tr><td colspan="9" class="py-4 text-slate-500">Loading…</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <div id="fleet-drawer-overlay" class="fleet-drawer-overlay" onclick="FleetView.closeDrawer()"></div>
            <aside id="fleet-drawer" class="fleet-drawer" aria-hidden="true">
                <div class="fleet-drawer-inner" id="fleet-drawer-body">
                    <p class="text-slate-500 text-xs p-4">Select a computer to view telemetry and queue commands.</p>
                </div>
            </aside>
        `;

        await this.loadEnrollInfo();
        await this.loadScripts();
        await this.loadPackages();
        await this.loadAgentPackage();
        await this.refresh();
        this.startPoll();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        const ms = this._drawerOpen ? 5000 : 15000;
        this._pollTimer = setInterval(() => this.refresh(true), ms);
    },

    stopPoll() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
        // Leave page cleanly — hide drawer chrome if still open
        const drawer = document.getElementById('fleet-drawer');
        const overlay = document.getElementById('fleet-drawer-overlay');
        if (drawer) {
            drawer.classList.remove('open');
            drawer.setAttribute('aria-hidden', 'true');
        }
        if (overlay) overlay.classList.remove('open');
        this._drawerOpen = false;
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    fmtPct(v) {
        if (v == null || v === '') return '—';
        return `${Number(v).toFixed(0)}%`;
    },

    fmtIo(v) {
        if (v == null || v === '') return '—';
        return `${Number(v).toFixed(2)}`;
    },

    fmtUptime(sec) {
        if (sec == null || sec === '') return '—';
        const s = Math.max(0, Number(sec));
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (d > 0) return `${d}d ${h}h`;
        if (h > 0) return `${h}h ${m}m`;
        return `${m}m`;
    },

    metricClass(kind, value) {
        if (value == null || value === '') return '';
        const n = Number(value);
        if (kind === 'cpu' || kind === 'ram') {
            if (n >= 90) return 'fleet-metric-bad';
            if (n >= 75) return 'fleet-metric-warn';
            return 'fleet-metric-ok';
        }
        if (kind === 'disk') {
            if (n < 10) return 'fleet-metric-bad';
            if (n < 20) return 'fleet-metric-warn';
            return 'fleet-metric-ok';
        }
        return '';
    },

    latestResultData(cmds, type) {
        const list = API.asArray(cmds);
        for (const c of list) {
            if (c.Type === type && c.Result && c.Result.Data != null && (c.Status === 'Completed' || c.Status === 'Failed')) {
                return c.Result.Data;
            }
        }
        return null;
    },

    async loadScripts() {
        try {
            const res = await API.request('fleet/scripts', 'GET', null, 10000, { silent: true });
            this._scripts = res.Success ? API.asArray(res.Data) : [];
        } catch {
            this._scripts = [];
        }
    },

    async loadPackages() {
        try {
            const res = await API.request('fleet/packages', 'GET', null, 10000, { silent: true });
            this._packages = res.Success ? API.asArray(res.Data) : [];
        } catch {
            this._packages = [];
        }
    },

    async loadAgentPackage() {
        try {
            const res = await API.request('fleet/agent-package', 'GET', null, 15000, { silent: true });
            this._agentPackage = (res.Success && res.Data) ? res.Data : null;
        } catch {
            this._agentPackage = null;
        }
        const el = document.getElementById('fleet-pkg-version');
        if (el) {
            if (this._agentPackage && this._agentPackage.Version) {
                el.textContent = `${this._agentPackage.Version}${this._agentPackage.Sha256 ? ' · ' + String(this._agentPackage.Sha256).slice(0, 12) + '…' : ''}`;
            } else {
                el.textContent = 'not published';
            }
        }
    },

    agentOutdated(agentVersion) {
        const pkg = this._agentPackage && this._agentPackage.Version ? String(this._agentPackage.Version) : '';
        const ver = String(agentVersion || '');
        if (!pkg || !ver) return false;
        return ver !== pkg;
    },

    supportsSelfUpdate(agentVersion) {
        const ver = String(agentVersion || '');
        return /^2\.2\./.test(ver) || /^2\.[3-9]/.test(ver) || /^[3-9]/.test(ver);
    },

    async loadEnrollInfo() {
        const res = await API.request('fleet/enroll-token');
        if (!res.Success || !res.Data) {
            const warn = document.getElementById('fleet-bind-warn');
            if (warn) {
                warn.classList.remove('hidden');
                warn.textContent = `Could not load enrollment info: ${res.Message || 'Failed to fetch'}. Is the API running? Open http://localhost:8787/api/v1/health`;
            }
            return;
        }
        const tokenEl = document.getElementById('fleet-token');
        const cmdEl = document.getElementById('fleet-install-cmd');
        const hint = document.getElementById('fleet-url-hint');
        const warn = document.getElementById('fleet-bind-warn');
        const url = res.Data.SuggestedUrl || 'http://localhost:8787';
        if (tokenEl) tokenEl.value = res.Data.Token || '';
        const cmd = `powershell -ExecutionPolicy Bypass -File .\\Install-LocalOpsAgent.ps1 -ServerUrl "${url}" -EnrollToken "${res.Data.Token || ''}"`;
        if (cmdEl) cmdEl.value = cmd;
        if (hint) {
            const bind = res.Data.BindHost || 'localhost';
            const lan = res.Data.DetectedLanIp || '';
            if (res.Data.PublicUrl) {
                hint.textContent = `Install uses fleetPublicUrl (${res.Data.PublicUrl}). Agents must reach that host (LAN or Tailscale); bindHost is currently "${bind}".`;
            } else if (res.Data.AllowsRemote) {
                hint.textContent = `Install uses a reachable console URL (${url}). bindHost="${bind}" accepts remote agents.`;
            } else if (lan) {
                hint.textContent = `Install uses this PC's LAN IP (${lan}) so other PCs can enroll. Also set bindHost to 0.0.0.0 in settings.json — localhost-only bind blocks remote agents.`;
            } else {
                hint.textContent = 'Could not detect a LAN IP. Set fleetPublicUrl (LAN or Tailscale IP) and bindHost to 0.0.0.0 for remote agents.';
            }
        }
        if (warn) {
            if (res.Data.BindMismatch && res.Data.BindWarning) {
                warn.classList.remove('hidden');
                warn.textContent = res.Data.BindWarning;
                LiveConsole.log(res.Data.BindWarning, 'ERROR');
            } else {
                warn.classList.add('hidden');
                warn.textContent = '';
            }
        }
    },

    async refresh(silent) {
        const res = await API.request('fleet/agents', 'GET', null, 15000, { silent: !!silent });
        if (!res.Success) {
            if (!silent) LiveConsole.log(res.Message || 'Failed to load agents', 'WARN');
            return;
        }
        this._agents = API.asArray(res.Data);
        if (!silent) await this.loadAgentPackage();
        this.renderTable();
        if (this._selected && this._drawerOpen) {
            await this.loadDrawer(this._selected, true);
        }
    },

    renderTable() {
        const tbody = document.getElementById('fleet-agent-rows');
        if (!tbody) return;
        if (!this._agents.length) {
            tbody.innerHTML = '<tr><td colspan="9" class="py-4 text-slate-500">No enrolled agents yet. Expand Enrollment above to add a PC.</td></tr>';
            return;
        }
        tbody.innerHTML = this._agents.map((a) => {
            const pulse = a.Online ? '<span class="fleet-online-dot" title="online"></span>' : '';
            const online = a.Online
                ? `<span class="badge badge-ok inline-flex items-center gap-1">${pulse}online</span>`
                : '<span class="badge badge-muted">offline</span>';
            const net = a.InternetOk === true ? '<span class="text-emerald-400">OK</span>' : (a.InternetOk === false ? '<span class="text-rose-400">DOWN</span>' : '—');
            const cpuCls = this.metricClass('cpu', a.CpuPct);
            const ramCls = this.metricClass('ram', a.RamPct);
            const diskCls = this.metricClass('disk', a.DiskFreePct);
            const sel = this._selected === a.Id ? 'fleet-row-selected' : '';
            const spike = a.SpikeActive || (Number(a.CpuPct) >= 90) || (Number(a.RamPct) >= 90);
            const spikeCue = spike
                ? `<span class="badge badge-warn ml-1" title="${this.escape((a.LastOffender && a.LastOffender.Summary) || 'High CPU/RAM')}">SPIKE</span>`
                : '';
            const io = `${this.fmtIo(a.DiskReadMBps)}/${this.fmtIo(a.DiskWriteMBps)}`;
            return `<tr class="border-b border-slate-800/60 hover:bg-slate-800/40 cursor-pointer ${sel}${spike ? ' fleet-row-spike' : ''}" data-agent-id="${this.escape(a.Id)}" onclick="FleetView.select(this.getAttribute('data-agent-id'))">
                <td class="py-2 pr-2 font-mono text-cyan-300">${this.escape(a.ComputerName || a.Id)}${spikeCue}</td>
                <td class="py-2 pr-2">${online}</td>
                <td class="py-2 pr-2 ${cpuCls}">${this.fmtPct(a.CpuPct)}</td>
                <td class="py-2 pr-2 ${ramCls}">${this.fmtPct(a.RamPct)}</td>
                <td class="py-2 pr-2 ${diskCls}">${this.fmtPct(a.DiskFreePct)}</td>
                <td class="py-2 pr-2 text-slate-400 font-mono text-[10px]">${io}</td>
                <td class="py-2 pr-2">${net}</td>
                <td class="py-2 pr-2 text-slate-400">${this.escape(a.LastSeen || '—')}</td>
                <td class="py-2">${this.escape(a.AgentVersion || '—')}${this.agentOutdated(a.AgentVersion) ? ' <span class="badge badge-warn">outdated</span>' : ''}</td>
            </tr>`;
        }).join('');
    },

    async select(agentId) {
        const id = String(agentId || '').trim();
        if (!id) {
            LiveConsole.log('[API] fleet/agents: missing agent id', 'ERROR');
            return;
        }
        this._selected = id;
        this._lastLatency = null;
        this.renderTable();
        this.openDrawer();
        await this.loadDrawer(id);
    },

    openDrawer() {
        this._drawerOpen = true;
        const drawer = document.getElementById('fleet-drawer');
        const overlay = document.getElementById('fleet-drawer-overlay');
        if (drawer) {
            drawer.classList.add('open');
            drawer.setAttribute('aria-hidden', 'false');
        }
        if (overlay) overlay.classList.add('open');
        this.startPoll();
    },

    closeDrawer() {
        this._drawerOpen = false;
        this._selected = null;
        this._detailCache = null;
        const drawer = document.getElementById('fleet-drawer');
        const overlay = document.getElementById('fleet-drawer-overlay');
        if (drawer) {
            drawer.classList.remove('open');
            drawer.setAttribute('aria-hidden', 'true');
        }
        if (overlay) overlay.classList.remove('open');
        this.renderTable();
        this.startPoll();
    },

    metricCard(label, value, extraClass) {
        return `<div class="fleet-metric ${extraClass || ''}">
            <div class="fleet-metric-label">${label}</div>
            <div class="fleet-metric-value">${value}</div>
        </div>`;
    },

    async loadDrawer(agentId, silent) {
        const box = document.getElementById('fleet-drawer-body');
        if (!box) return;

        const scrollEl = box.querySelector('.fleet-drawer-scroll') || box;
        const prevScroll = silent ? scrollEl.scrollTop : 0;

        if (!silent) {
            box.innerHTML = '<div class="p-4 text-slate-500 text-xs">Loading…</div>';
        }

        const res = await API.request(`fleet/agents/${agentId}`, 'GET', null, 15000, { silent: !!silent });
        if (!res.Success || !res.Data) {
            box.innerHTML = `<div class="p-4"><p class="text-rose-400 text-xs">${this.escape(res.Message || 'Failed')}</p></div>`;
            return;
        }

        const d = res.Data;
        const a = d.Agent || d.agent || {};
        const cmds = API.asArray(d.Commands || d.commands);
        const alerts = API.asArray(d.Alerts || d.alerts);
        this._detailCache = { agent: a, cmds, alerts };

        const inv = a.Inventory;
        const procData = this.latestResultData(cmds, 'GetProcesses');
        const processes = procData ? API.asArray(procData) : [];
        const servicesData = this.latestResultData(cmds, 'GetServices');
        const services = servicesData ? API.asArray(servicesData) : [];
        const printerBundle = this.latestResultData(cmds, 'GetPrinters') || (inv && inv.Printers ? { Printers: inv.Printers } : null);
        const printers = printerBundle ? API.asArray(printerBundle.Printers || printerBundle) : [];
        const netSmoke = this.latestResultData(cmds, 'NetHealthSmoke');
        const lat = this._lastLatency;
        const wuStatus = this.latestResultData(cmds, 'GetWindowsUpdateStatus');
        const rdStatus = this.latestResultData(cmds, 'GetRustDeskStatus');
        const eventTail = this.latestResultData(cmds, 'GetEventLogTail');
        const offenders = this.latestResultData(cmds, 'GetResourceOffenders') || a.LastOffender;
        const installPkg = this.latestResultData(cmds, 'InstallPackage');
        const baselineAudit = this.latestResultData(cmds, 'AuditSecurityBaseline');
        const policyApply = this.latestResultData(cmds, 'ApplySecurityPolicy');

        const pending = cmds.filter((c) => c.Status === 'Pending');
        const running = cmds.filter((c) => c.Status === 'Running');
        let stuckPending = false;
        const now = Date.now();
        for (const c of pending) {
            const t = Date.parse(c.CreatedAt);
            if (!isNaN(t) && (now - t) > 60000) { stuckPending = true; break; }
        }
        let stuckRunning = false;
        for (const c of running) {
            const t = Date.parse(c.ClaimedAt || c.CreatedAt);
            if (!isNaN(t) && (now - t) > 5 * 60 * 1000) { stuckRunning = true; break; }
        }
        const selectedCmd = this._selectedCmdId
            ? cmds.find((c) => String(c.Id) === String(this._selectedCmdId))
            : null;
        if (this._selectedCmdId && !selectedCmd) this._selectedCmdId = null;
        const ver = String(a.AgentVersion || '');
        const pkgVer = this._agentPackage && this._agentPackage.Version ? String(this._agentPackage.Version) : '';
        const outdated = this.agentOutdated(ver);
        const canSelfUpdate = this.supportsSelfUpdate(ver);
        const verOld = ver && !canSelfUpdate && !/^2\.1\.[6-9]/.test(ver) && !/^2\.[2-9]/.test(ver) && !/^[3-9]/.test(ver);

        const scriptOptions = this._scripts.length
            ? this._scripts.map((s) => `<option value="${this.escape(s.Id)}">${this.escape(s.Name || s.Id)}</option>`).join('')
            : '<option value="">No scripts in catalog</option>';
        const pkgOptions = this._packages.length
            ? this._packages.map((p) => `<option value="${this.escape(p.Id)}">${this.escape(p.Name || p.Id)}</option>`).join('')
            : '<option value="">No packages in catalog</option>';

        const netLabel = a.InternetOk === true ? 'OK' : (a.InternetOk === false ? 'DOWN' : '—');
        const latLabel = lat
            ? (lat.ProbeOk ? `${lat.AvgMs} ms` : 'fail')
            : '—';

        const scriptPick = document.getElementById('fleet-script-pick');
        const prevScript = silent && scriptPick ? scriptPick.value : '';
        const pkgPick = document.getElementById('fleet-pkg-pick');
        const prevPkg = silent && pkgPick ? pkgPick.value : '';

        const wuPending = wuStatus ? API.asArray(wuStatus.PendingUpdates || wuStatus.pendingUpdates) : [];
        const eventEntries = eventTail ? API.asArray(eventTail.Entries || eventTail.entries) : [];
        const offenderProcs = offenders
            ? API.asArray(offenders.TopProcesses || (offenders.TopProcess ? [offenders.TopProcess] : []))
            : [];

        box.innerHTML = `
            <div class="fleet-drawer-head">
                <div>
                    <h3 class="text-base font-bold text-slate-100">${this.escape(a.ComputerName || agentId)}</h3>
                    <div class="flex flex-wrap gap-2 text-[11px] mt-1">
                        <span class="badge ${a.Online ? 'badge-ok' : 'badge-muted'}">${a.Online ? 'online' : 'offline'}</span>
                        <span class="badge badge-muted">${this.escape(a.IPv4 || 'no IP')}</span>
                        <span class="badge badge-muted">${this.escape(a.UserName || '')}</span>
                        <span class="badge badge-muted">agent ${this.escape(ver || '?')}</span>
                        ${outdated ? '<span class="badge badge-warn">outdated</span>' : ''}
                        ${a.SpikeActive ? '<span class="badge badge-warn">SPIKE</span>' : ''}
                    </div>
                </div>
                <button type="button" class="action-btn slate text-[11px]" onclick="FleetView.closeDrawer()">Close</button>
            </div>

            <div class="fleet-drawer-scroll space-y-4 p-4">
                ${!a.Online ? `<p class="text-[11px] text-rose-400 font-semibold">Agent offline — commands stay Pending until LocalOpsAgent is running and can reach ServerUrl.</p>` : ''}
                ${a.Online && stuckPending ? `<p class="text-[11px] text-amber-400 font-semibold">Commands Pending &gt;60s while online — restart scheduled task LocalOpsAgent; check logs and ServerUrl.</p>` : ''}
                ${running.length ? `<p class="text-[11px] text-slate-400">Running: ${this.escape(running.map((c) => c.Type).join(', '))} (blocks the next Pending command until it finishes or times out after 45m).</p>` : ''}
                ${stuckRunning || (running.length && pending.length) ? `<div class="flex flex-wrap items-center gap-2"><p class="text-[11px] text-amber-400 font-semibold m-0">Queue blocked by Running (or stale claim). Clear stuck commands to unblock Pending.</p><button type="button" class="action-btn amber text-[11px]" onclick="FleetView.clearStuckCommands()">Clear stuck</button></div>` : ''}
                ${verOld ? `<p class="text-[11px] text-amber-400 font-semibold">Agent version ${this.escape(ver)} may be outdated — reinstall LocalOpsAgent for full command support.</p>` : ''}
                ${outdated && !canSelfUpdate ? `<p class="text-[11px] text-amber-400 font-semibold">Published package is ${this.escape(pkgVer || '?')}; this agent is ${this.escape(ver || '?')} and cannot self-update yet — install 2.2.0+ manually once.</p>` : ''}
                ${outdated && canSelfUpdate ? `<p class="text-[11px] text-amber-400 font-semibold">Published package ${this.escape(pkgVer)} is newer than agent ${this.escape(ver)} — use Update agent below.</p>` : ''}

                <div>
                    <div class="section-title">Live telemetry</div>
                    <div class="fleet-metric-grid">
                        ${this.metricCard('CPU', this.fmtPct(a.CpuPct), this.metricClass('cpu', a.CpuPct))}
                        ${this.metricCard('RAM', this.fmtPct(a.RamPct), this.metricClass('ram', a.RamPct))}
                        ${this.metricCard('Disk free', this.fmtPct(a.DiskFreePct), this.metricClass('disk', a.DiskFreePct))}
                        ${this.metricCard('Disk R/W', `${this.fmtIo(a.DiskReadMBps)} / ${this.fmtIo(a.DiskWriteMBps)} MB/s`)}
                        ${this.metricCard('Net', netLabel, a.InternetOk === false ? 'fleet-metric-bad' : (a.InternetOk === true ? 'fleet-metric-ok' : ''))}
                        ${this.metricCard('Latency', latLabel)}
                        ${this.metricCard('Gateway', this.escape(a.Gateway || '—'))}
                        ${this.metricCard('Windows', this.escape(a.WindowsVersion || '—'))}
                        ${this.metricCard('Uptime', this.fmtUptime(a.UptimeSec))}
                        ${this.metricCard('Last seen', this.escape(a.LastSeen || '—'))}
                    </div>
                    ${netSmoke ? `<p class="text-[11px] text-emerald-300 mt-2">Agent internet: ping ${netSmoke.PingOk ? netSmoke.InternetLatencyMs + ' ms' : 'fail'} · down ${netSmoke.DownloadOk ? netSmoke.DownloadMbps + ' Mbps' : 'fail'} · up ${netSmoke.UploadOk ? netSmoke.UploadMbps + ' Mbps' : 'fail'}</p>` : ''}
                    ${lat && !lat.ProbeOk ? `<p class="text-[11px] text-amber-300 mt-1">${this.escape(lat.Error || 'ICMP failed / blocked')}</p>` : ''}
                </div>

                ${offenderProcs.length || (offenders && offenders.Summary) ? `
                <div class="fleet-spike-box">
                    <div class="section-title text-amber-400">Spike forensics</div>
                    <p class="text-[11px] text-slate-300 mb-2">${this.escape((offenders && offenders.Summary) || 'Top memory consumers')}</p>
                    <div class="flex flex-wrap gap-2 mb-2">
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.queueCmd('GetResourceOffenders')">Refresh offenders</button>
                    </div>
                    ${offenderProcs.length ? `
                    <div class="max-h-36 overflow-auto border border-slate-800 rounded-lg">
                        <table class="w-full text-[10px] font-mono">
                            <thead><tr class="text-slate-500 text-left"><th class="p-1">Name</th><th class="p-1">PID</th><th class="p-1">MB</th><th class="p-1">Service</th><th class="p-1"></th></tr></thead>
                            <tbody>
                                ${offenderProcs.slice(0, 8).map((p) => {
                                    const name = p.Name || p.name || '';
                                    const id = p.Id != null ? p.Id : p.id;
                                    const mb = p.WorkingSetMB != null ? p.WorkingSetMB : '';
                                    const svc = (p.RelatedService && (p.RelatedService.Name || p.RelatedService)) || '';
                                    return `<tr class="border-t border-slate-800/80">
                                        <td class="p-1">${this.escape(name)}</td>
                                        <td class="p-1">${this.escape(id)}</td>
                                        <td class="p-1">${this.escape(mb)}</td>
                                        <td class="p-1">${this.escape(svc)}</td>
                                        <td class="p-1 whitespace-nowrap">
                                            ${id != null ? `<button type="button" class="text-rose-400 hover:underline mr-1" onclick="FleetView.endProcess(${Number(id)}, '${this.escape(name)}')">End</button>` : ''}
                                            ${svc ? `<button type="button" class="text-amber-400 hover:underline" onclick="FleetView.queueCmd('RestartService', { ServiceName: '${this.escape(String(svc))}' })">Restart svc</button>` : ''}
                                        </td>
                                    </tr>`;
                                }).join('')}
                            </tbody>
                        </table>
                    </div>` : ''}
                </div>` : ''}

                <div>
                    <div class="section-title">Network</div>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('FlushDns')">Flush DNS</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('NetHealthSmoke')">Net smoke</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.pingAgent()">Ping PC</button>
                    </div>
                </div>

                <div>
                    <div class="section-title">Policy</div>
                    <p class="text-[10px] text-slate-500 mb-2">Remote security hardening (firewall + Defender). Wallpaper/theme lockdown is not included.</p>
                    <div class="flex flex-wrap gap-2 mb-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('AuditSecurityBaseline')">Audit baseline</button>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.applyHardeningBasic()">Apply hardening-basic</button>
                    </div>
                    ${baselineAudit ? `<p class="text-[11px] text-slate-300">Last audit score: <span class="text-cyan-300 font-mono">${this.escape(String(baselineAudit.Score != null ? baselineAudit.Score : '—'))}%</span> · pass ${this.escape(String(baselineAudit.Pass || 0))} / fail ${this.escape(String(baselineAudit.Fail || 0))}</p>
                    ${API.asArray(baselineAudit.Checks).length ? `<ul class="mt-1 text-[10px] text-slate-500 font-mono max-h-24 overflow-auto">${API.asArray(baselineAudit.Checks).slice(0, 8).map((ch) => `<li>${this.escape(ch.Name || '')}: ${this.escape(ch.Status || '')} — ${this.escape(ch.Detail || '')}</li>`).join('')}</ul>` : ''}` : ''}
                    ${policyApply && API.asArray(policyApply.Results).length ? `<ul class="mt-2 text-[10px] text-slate-400 font-mono">${API.asArray(policyApply.Results).map((r) => `<li>${r.Ok ? 'OK' : 'FAIL'} ${this.escape(r.Id || '')} — ${this.escape(r.Detail || '')}</li>`).join('')}</ul>` : ''}
                </div>

                <div>
                    <div class="section-title">Windows Update</div>
                    <div class="flex flex-wrap gap-2 mb-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetWindowsUpdateStatus')">Check status</button>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.confirmQueue('InstallWindowsUpdates', 'Download and install pending Windows Updates on this PC? May take a long time and may require reboot later.')">Install pending</button>
                    </div>
                    ${wuStatus ? `<p class="text-[11px] text-slate-400">Pending: ${this.escape(wuStatus.PendingCount != null ? wuStatus.PendingCount : wuPending.length)}${wuStatus.PendingReboot ? ' · reboot pending' : ''}${wuStatus.LastHistoryDate ? ' · last history ' + this.escape(wuStatus.LastHistoryDate) : ''}</p>
                    ${wuPending.length ? `<ul class="mt-1 text-[10px] text-slate-500 font-mono max-h-24 overflow-auto">${wuPending.slice(0, 8).map((u) => `<li>${this.escape(u.Title || '')}</li>`).join('')}</ul>` : ''}` : ''}
                </div>

                <div>
                    <div class="section-title">Remote Support (RustDesk)</div>
                    <div class="flex flex-wrap gap-2 mb-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetRustDeskStatus')">RustDesk status</button>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.confirmQueue('InstallRustDesk', 'Download and silently install RustDesk on this PC? Requires rustDeskInstallerUrl in settings.json.')">Install RustDesk</button>
                    </div>
                    ${rdStatus ? `<p class="text-[11px] text-slate-400">${rdStatus.Installed ? 'Installed' : 'Not installed'}${rdStatus.Id ? ' · ID ' + this.escape(rdStatus.Id) : ''}${rdStatus.ServiceStatus ? ' · svc ' + this.escape(rdStatus.ServiceStatus) : ''}${rdStatus.ProcessRunning ? ' · running' : ''}</p>` : ''}
                </div>

                <div>
                    <div class="section-title">Software</div>
                    <div class="flex flex-wrap items-end gap-2">
                        <div class="flex-1 min-w-[10rem]">
                            <label class="text-[11px] text-slate-500 block mb-1">Catalog package</label>
                            <select id="fleet-pkg-pick" class="w-full px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 text-xs">${pkgOptions}</select>
                        </div>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.installPackage()">Install</button>
                    </div>
                    ${installPkg ? `<p class="text-[11px] text-slate-400 mt-1">${this.escape(installPkg.Name || installPkg.PackageId || '')} via ${this.escape(installPkg.Method || '?')} · exit ${this.escape(installPkg.ExitCode)}</p>` : ''}
                    <p class="text-[10px] text-slate-600 mt-1">Edit data/fleet/packages.json to add favorites. Agent opens ProgramData\\LocalOpsAgent\\installs\\{id}\\</p>
                </div>

                <div>
                    <div class="section-title">Event Log</div>
                    <div class="flex flex-wrap gap-2 mb-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetEventLogTail', { LogName: 'System', Count: 40 })">System</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetEventLogTail', { LogName: 'Application', Count: 40 })">Application</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetEventLogTail', { LogName: 'Security', Count: 40 })">Security</button>
                    </div>
                    ${eventEntries.length ? `
                    <div class="max-h-40 overflow-auto border border-slate-800 rounded-lg">
                        <table class="w-full text-[10px] font-mono">
                            <thead><tr class="text-slate-500 text-left"><th class="p-1">Time</th><th class="p-1">Lvl</th><th class="p-1">Id</th><th class="p-1">Message</th></tr></thead>
                            <tbody>
                                ${eventEntries.map((e) => `<tr class="border-t border-slate-800/80">
                                    <td class="p-1 whitespace-nowrap">${this.escape(e.TimeCreated || '')}</td>
                                    <td class="p-1">${this.escape(e.Level || '')}</td>
                                    <td class="p-1">${this.escape(e.Id)}</td>
                                    <td class="p-1">${this.escape(e.Message || '')}</td>
                                </tr>`).join('')}
                            </tbody>
                        </table>
                    </div>` : ''}
                </div>

                <div>
                    <div class="section-title">Services / Print</div>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('RestartSpooler')">Restart Spooler</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetServices')">Get Services</button>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.restartService()">Restart Service…</button>
                    </div>
                </div>

                <div>
                    <div class="section-title">Inventory / Inspect</div>
                    <div class="flex flex-wrap gap-2 mb-2">
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('CollectInventory')">Collect Inventory</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetProcesses')">Processes</button>
                        <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetPrinters')">Printers</button>
                    </div>
                    <div class="flex flex-wrap items-end gap-2">
                        <div class="flex-1 min-w-[10rem]">
                            <label class="text-[11px] text-slate-500 block mb-1">Run script</label>
                            <select id="fleet-script-pick" class="w-full px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 text-xs">${scriptOptions}</select>
                        </div>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.runScript()">Run Script</button>
                    </div>
                </div>

                <div>
                    <div class="section-title">Message</div>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.queueMessage()">Message user</button>
                    </div>
                </div>

                <div>
                    <div class="section-title">Repair</div>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.confirmQueue('SfcScannow', 'Run SFC /scannow on the remote PC? This can take a long time and will block other agent commands until finished.')">SFC scan</button>
                        <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.confirmQueue('ChkdskScan', 'Run read-only CHKDSK on C: (no /F)?')">CHKDSK scan</button>
                        <button type="button" class="action-btn rose text-[11px]" onclick="FleetView.confirmQueue('ChkdskScheduleFix', 'Schedule CHKDSK /F on C: for next restart? This does NOT reboot the PC.')">CHKDSK schedule /F</button>
                    </div>
                </div>

                <div>
                    <div class="section-title">Agent update</div>
                    <p class="text-[11px] text-slate-400 mb-2">Console package: <span class="font-mono text-cyan-300">${this.escape(pkgVer || 'not published')}</span> · this PC: <span class="font-mono">${this.escape(ver || '?')}</span></p>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn ${outdated ? 'amber' : 'cyan'} text-[11px]" onclick="FleetView.selfUpdateAgent(false)">${outdated ? 'Update agent' : 'Re-check / update agent'}</button>
                        <button type="button" class="action-btn slate text-[11px]" onclick="FleetView.selfUpdateAgent(true)">Force update</button>
                    </div>
                    ${!canSelfUpdate ? `<p class="text-[10px] text-slate-500 mt-1">Self-update requires agent 2.2.0+. Older agents need a one-time manual reinstall.</p>` : ''}
                </div>

                <div>
                    <div class="section-title text-rose-400">Danger</div>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" class="action-btn rose text-[11px]" onclick="FleetView.restartComputer()">Restart Computer</button>
                        <button type="button" class="action-btn rose text-[11px]" onclick="FleetView.revokeAgent()">Remove agent</button>
                    </div>
                </div>

                ${processes.length ? `
                <details open class="fleet-result-panel">
                    <summary class="text-xs font-semibold text-slate-300">Processes (top by memory)</summary>
                    <div class="max-h-40 overflow-auto border border-slate-800 rounded-lg mt-2">
                        <table class="w-full text-[10px] font-mono">
                            <thead><tr class="text-slate-500 text-left"><th class="p-1">Name</th><th class="p-1">PID</th><th class="p-1">MB</th><th class="p-1"></th></tr></thead>
                            <tbody>
                                ${processes.map((p) => {
                                    const name = p.Name || p.name || '';
                                    const id = p.Id != null ? p.Id : p.id;
                                    const mb = p.WorkingSetMB != null ? p.WorkingSetMB : '';
                                    return `<tr class="border-t border-slate-800/80">
                                        <td class="p-1">${this.escape(name)}</td>
                                        <td class="p-1">${this.escape(id)}</td>
                                        <td class="p-1">${this.escape(mb)}</td>
                                        <td class="p-1"><button type="button" class="text-rose-400 hover:underline" onclick="FleetView.endProcess(${Number(id)}, '${this.escape(name)}')">End</button></td>
                                    </tr>`;
                                }).join('')}
                            </tbody>
                        </table>
                    </div>
                </details>` : ''}

                ${services.length ? `
                <details open class="fleet-result-panel">
                    <summary class="text-xs font-semibold text-slate-300">Services (${services.length})</summary>
                    <div class="max-h-48 overflow-auto border border-slate-800 rounded-lg mt-2">
                        <table class="w-full text-[10px] font-mono">
                            <thead><tr class="text-slate-500 text-left"><th class="p-1">Name</th><th class="p-1">Status</th><th class="p-1">Start</th><th class="p-1">Display</th></tr></thead>
                            <tbody>
                                ${services.slice(0, 80).map((s) => `<tr class="border-t border-slate-800/80">
                                    <td class="p-1">${this.escape(s.Name || '')}</td>
                                    <td class="p-1">${this.escape(s.Status || '')}</td>
                                    <td class="p-1">${this.escape(s.StartType || '')}</td>
                                    <td class="p-1">${this.escape(s.DisplayName || '')}</td>
                                </tr>`).join('')}
                            </tbody>
                        </table>
                    </div>
                </details>` : ''}

                ${printers.length ? `
                <details class="fleet-result-panel">
                    <summary class="text-xs font-semibold text-slate-300">Printers</summary>
                    <ul class="mt-2 space-y-1 text-[10px] text-slate-400 font-mono max-h-28 overflow-auto">
                        ${printers.map((pr) => `<li>${this.escape(pr.Name || '')} · ${this.escape(pr.DriverName || '')} · ${this.escape(pr.PortName || '')} · ${this.escape(pr.PrinterStatus != null ? pr.PrinterStatus : '')}</li>`).join('')}
                    </ul>
                </details>` : ''}

                ${alerts.length ? `
                <details open class="fleet-result-panel">
                    <summary class="text-xs font-semibold text-amber-400">Alerts</summary>
                    <ul class="mt-2 space-y-1 text-xs text-slate-400">${alerts.slice(0, 8).map((al) => `<li>${this.escape(al.Type)}: ${this.escape(al.Message)}</li>`).join('')}</ul>
                </details>` : ''}

                ${inv ? `
                <details class="fleet-result-panel">
                    <summary class="text-xs font-semibold text-emerald-400">Inventory JSON</summary>
                    <pre class="text-[10px] text-slate-400 max-h-32 overflow-auto mt-2">${this.escape(JSON.stringify(inv, null, 2))}</pre>
                </details>` : ''}

                <details open class="fleet-result-panel">
                    <summary class="text-xs font-semibold text-slate-300">Command history</summary>
                    <p class="text-[10px] text-slate-500 mt-1 mb-2">Click a row to open its result below (no scrolling the list).</p>
                    <div class="mt-2 max-h-40 overflow-auto space-y-1 font-mono text-[10px] text-slate-400">
                        ${cmds.length ? cmds.map((c) => {
                            const sel = this._selectedCmdId && String(c.Id) === String(this._selectedCmdId);
                            const extra = c.Result && c.Result.Message ? ' — ' + this.escape(c.Result.Message) : '';
                            const dur = c.Result && c.Result.DurationMs != null ? ` (${c.Result.DurationMs}ms)` : '';
                            return `<button type="button" class="fleet-cmd-row ${sel ? 'is-selected' : ''}" onclick="FleetView.selectCommand('${this.escape(c.Id)}')">${this.escape(c.CreatedAt)} · ${this.escape(c.Type)} · ${this.escape(c.Status)}${dur}${extra}</button>`;
                        }).join('') : '<div class="text-slate-500">No commands yet.</div>'}
                    </div>
                </details>

                <div class="fleet-result-panel fleet-cmd-detail" id="fleet-cmd-detail">
                    <div class="text-xs font-semibold text-cyan-300 mb-2">Command result</div>
                    ${selectedCmd ? this.renderCommandDetail(selectedCmd) : '<p class="text-[11px] text-slate-500">Select a command in history to view its status and payload here.</p>'}
                </div>
            </div>
        `;

        if (silent) {
            if (prevScript) {
                const pick = document.getElementById('fleet-script-pick');
                if (pick) pick.value = prevScript;
            }
            if (prevPkg) {
                const pick = document.getElementById('fleet-pkg-pick');
                if (pick) pick.value = prevPkg;
            }
            const newScroll = box.querySelector('.fleet-drawer-scroll');
            if (newScroll) {
                requestAnimationFrame(() => { newScroll.scrollTop = prevScroll; });
            }
        }
    },

    async queueCmd(type, payload) {
        if (!this._selected) return;
        const res = await API.request('fleet/commands', 'POST', { AgentId: this._selected, Type: type, Payload: payload || {} }, 20000);
        if (res.Success) {
            LiveConsole.log(`Queued ${type} for agent`, 'SUCCESS', res.Data);
            setTimeout(() => this.loadDrawer(this._selected, true), 4000);
            await this.loadDrawer(this._selected);
        } else {
            LiveConsole.log(res.Message || 'Queue failed', 'ERROR');
        }
    },

    selectCommand(cmdId) {
        this._selectedCmdId = cmdId;
        if (this._selected) this.loadDrawer(this._selected, true);
    },

    renderCommandDetail(c) {
        if (!c) return '';
        const res = c.Result || null;
        const hasData = res && res.Data != null;
        let dataHtml = '';
        if (hasData) {
            try {
                dataHtml = `<pre class="text-[10px] text-slate-300 max-h-56 overflow-auto mt-2 font-mono">${this.escape(JSON.stringify(res.Data, null, 2))}</pre>`;
            } catch (e) {
                dataHtml = `<pre class="text-[10px] text-slate-300 mt-2">${this.escape(String(res.Data))}</pre>`;
            }
        }
        const canCancel = c.Status === 'Pending' || c.Status === 'Running';
        return `
            <div class="space-y-2 text-[11px]">
                <div class="flex flex-wrap gap-2 items-center">
                    <span class="badge badge-muted">${this.escape(c.Type || '')}</span>
                    <span class="badge ${c.Status === 'Completed' ? 'badge-ok' : (c.Status === 'Failed' ? 'badge-err' : 'badge-warn')}">${this.escape(c.Status || '')}</span>
                    ${canCancel ? `<button type="button" class="action-btn amber text-[10px]" onclick="FleetView.cancelCommand('${this.escape(c.Id)}')">Cancel</button>` : ''}
                </div>
                <div class="text-slate-400 font-mono">Created ${this.escape(c.CreatedAt || '—')}${c.ClaimedAt ? ' · Claimed ' + this.escape(c.ClaimedAt) : ''}${c.CompletedAt ? ' · Done ' + this.escape(c.CompletedAt) : ''}</div>
                ${res && res.Message ? `<p class="text-slate-200 m-0">${this.escape(res.Message)}</p>` : (c.Status === 'Pending' || c.Status === 'Running' ? '<p class="text-slate-500 m-0">No result yet — still Pending/Running. A stuck Running job blocks the rest of the queue.</p>' : '<p class="text-slate-500 m-0">No result payload.</p>')}
                ${res && res.DurationMs != null ? `<p class="text-slate-500 m-0">Duration ${this.escape(String(res.DurationMs))} ms</p>` : ''}
                ${dataHtml}
            </div>
        `;
    },

    async cancelCommand(cmdId) {
        if (!this._selected || !cmdId) return;
        if (!confirm('Cancel this Pending/Running command?')) return;
        const res = await API.request(`fleet/commands/${encodeURIComponent(cmdId)}/cancel`, 'POST', { AgentId: this._selected }, 15000);
        if (res.Success) {
            LiveConsole.log('Command cancelled', 'SUCCESS', res.Data);
            await this.loadDrawer(this._selected);
        } else {
            LiveConsole.log(res.Message || 'Cancel failed', 'ERROR');
        }
    },

    async clearStuckCommands() {
        if (!this._selected) return;
        if (!confirm('Clear all Pending and Running commands for this PC? Completed history is kept.')) return;
        const res = await API.request('fleet/commands/clear-stuck', 'POST', { AgentId: this._selected }, 15000);
        if (res.Success) {
            LiveConsole.log(res.Message || 'Stuck commands cleared', 'SUCCESS', res.Data);
            this._selectedCmdId = null;
            await this.loadDrawer(this._selected);
        } else {
            LiveConsole.log(res.Message || 'Clear failed', 'ERROR');
        }
    },

    async applyHardeningBasic() {
        if (!this._selected) return;
        if (!confirm('Apply hardening-basic on this PC? Enables Windows Firewall (all profiles) and Defender realtime. Requires elevated agent. Wallpaper lockdown is not included.')) return;
        await this.queueCmd('ApplySecurityPolicy', { PackId: 'hardening-basic' });
    },

    async confirmQueue(type, promptText) {
        if (!this._selected) return;
        if (!confirm(promptText)) return;
        await this.queueCmd(type);
    },

    async restartService() {
        if (!this._selected) return;
        const name = prompt('Service name to restart (e.g. Spooler, wuauserv):');
        if (!name || !name.trim()) return;
        if (!confirm(`Restart service "${name.trim()}" on the remote PC?`)) return;
        await this.queueCmd('RestartService', { ServiceName: name.trim() });
    },

    async runScript() {
        if (!this._selected) return;
        const pick = document.getElementById('fleet-script-pick');
        const scriptId = pick && pick.value ? pick.value.trim() : '';
        if (!scriptId) {
            LiveConsole.log('Select a script from the catalog first', 'WARN');
            return;
        }
        const label = pick.options[pick.selectedIndex] ? pick.options[pick.selectedIndex].text : scriptId;
        if (!confirm(`Run script "${label}" on the remote PC?`)) return;
        await this.queueCmd('RunScript', { ScriptId: scriptId });
    },

    async restartComputer() {
        if (!this._selected) return;
        if (!confirm('Schedule a restart on this PC in 60 seconds? Users will see a shutdown warning.')) return;
        if (!confirm('Confirm Restart Computer — this will reboot the remote machine.')) return;
        await this.queueCmd('RestartComputer', { DelaySec: 60 });
    },

    async endProcess(pid, processName) {
        if (!this._selected) return;
        const label = processName ? `${processName} (${pid})` : `PID ${pid}`;
        if (!confirm(`End process ${label} on the remote PC?`)) return;
        const payload = { ProcessId: pid };
        if (processName) payload.ProcessName = processName;
        await this.queueCmd('EndProcess', payload);
    },

    async installPackage() {
        if (!this._selected) return;
        const pick = document.getElementById('fleet-pkg-pick');
        const packageId = pick && pick.value;
        if (!packageId) {
            LiveConsole.log('Select a package from the catalog first', 'WARN');
            return;
        }
        const label = pick.options[pick.selectedIndex] ? pick.options[pick.selectedIndex].text : packageId;
        if (!confirm(`Install "${label}" on the remote PC?`)) return;
        await this.queueCmd('InstallPackage', { PackageId: packageId });
    },

    async publishAgentPackage() {
        const res = await API.request('fleet/agent-package/publish', 'POST', {}, 30000);
        if (res.Success) {
            LiveConsole.log(`Published agent package ${res.Data && res.Data.Version ? res.Data.Version : ''}`, 'SUCCESS');
            await this.loadAgentPackage();
            this.renderTable();
            if (this._selected && this._drawerOpen) await this.loadDrawer(this._selected, true);
        } else {
            LiveConsole.log(res.Message || 'Publish failed', 'ERROR');
        }
    },

    async selfUpdateAgent(force) {
        if (!this._selected) return;
        const agent = this._agents.find((a) => a.Id === this._selected);
        const ver = agent ? agent.AgentVersion : '';
        if (!this.supportsSelfUpdate(ver)) {
            LiveConsole.log('This agent cannot self-update yet. Install LocalOpsAgent 2.2.0+ manually once.', 'WARN');
            return;
        }
        if (!this._agentPackage || !this._agentPackage.Version) {
            LiveConsole.log('No published agent package. Click Publish agent package under Enrollment first.', 'WARN');
            return;
        }
        const pkgVer = this._agentPackage.Version;
        const msg = force
            ? `Force-update agent to ${pkgVer}? The agent will download, verify SHA-256, replace its script, and restart.`
            : `Update agent from ${ver || '?'} to ${pkgVer}? The agent will download, verify SHA-256, replace its script, and restart.`;
        if (!confirm(msg)) return;
        await this.queueCmd('SelfUpdate', { Force: !!force });
    },

    async pingAgent() {
        if (!this._selected) return;
        LiveConsole.log('Probing console→agent latency…', 'INFO');
        const res = await API.request(`fleet/agents/${this._selected}/latency`, 'GET', null, 20000, { silent: true });
        if (res.Success && res.Data) {
            this._lastLatency = res.Data;
            if (res.Data.ProbeOk) {
                LiveConsole.log(`Latency avg ${res.Data.AvgMs} ms to ${res.Data.TargetHost}`, 'SUCCESS');
            } else {
                LiveConsole.log(res.Data.Error || res.Message || 'ICMP failed (endpoint OK)', 'WARN');
            }
            await this.loadDrawer(this._selected, true);
        } else {
            LiveConsole.log(res.Message || 'Latency probe failed', 'ERROR');
        }
    },

    async queueMessage() {
        if (!this._selected) return;
        const text = prompt('Message text for the user on the remote PC:');
        if (!text) return;
        await this.queueCmd('Message', { Text: text, Title: 'LocalOpsConsole' });
    },

    async revokeAgent() {
        if (!this._selected) return;
        if (!confirm('Remove this PC from Computers? It will be deleted from the fleet and can no longer authenticate.')) return;
        const res = await API.request(`fleet/agents/${this._selected}/revoke`, 'POST', {});
        if (res.Success) {
            LiveConsole.log('Agent removed', 'WARN');
            this.closeDrawer();
            await this.refresh();
        } else {
            LiveConsole.log(res.Message || 'Remove failed', 'ERROR');
        }
    },

    async rotateToken() {
        if (!confirm('Rotate enrollment token? Existing install scripts will need the new token.')) return;
        const res = await API.request('fleet/enroll-token/rotate', 'POST', {});
        if (res.Success) {
            LiveConsole.log('Enrollment token rotated', 'SUCCESS');
            await this.loadEnrollInfo();
        } else {
            LiveConsole.log(res.Message || 'Rotate failed', 'ERROR');
        }
    },

    copyToken() {
        const el = document.getElementById('fleet-token');
        if (el && el.value) {
            navigator.clipboard.writeText(el.value);
            LiveConsole.log('Token copied', 'INFO');
        }
    },

    copyInstall() {
        const el = document.getElementById('fleet-install-cmd');
        if (el && el.value) {
            navigator.clipboard.writeText(el.value);
            LiveConsole.log('Install command copied', 'INFO');
        }
    }
};

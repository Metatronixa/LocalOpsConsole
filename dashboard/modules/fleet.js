const FleetView = {
    _agents: [],
    _selected: null,
    _pollTimer: null,
    _lastLatency: null,

    async render(container) {
        this._selected = null;
        this._lastLatency = null;
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Computers</h2>
                        <p class="text-xs text-slate-400">Fleet agents — telemetry, remote actions, repairs. Tailscale: set fleetPublicUrl to http://&lt;tailscale-ip&gt;:8787.</p>
                    </div>
                    <button type="button" onclick="FleetView.refresh()" class="action-btn cyan">Refresh</button>
                </div>

                <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <h3 class="text-sm font-bold text-slate-100">Enrollment</h3>
                    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 text-xs">
                        <div>
                            <label class="text-slate-400">Enrollment token</label>
                            <div class="flex gap-2 mt-1">
                                <input id="fleet-token" readonly class="flex-1 px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 font-mono text-slate-200" />
                                <button type="button" class="action-btn emerald" onclick="FleetView.copyToken()">Copy</button>
                                <button type="button" class="action-btn amber" onclick="FleetView.rotateToken()">Rotate</button>
                            </div>
                        </div>
                        <div>
                            <label class="text-slate-400">Install one-liner (run as Admin on target PC)</label>
                            <textarea id="fleet-install-cmd" readonly rows="2" class="w-full mt-1 px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 font-mono text-[11px] text-slate-300"></textarea>
                            <button type="button" class="action-btn cyan mt-1 text-[11px]" onclick="FleetView.copyInstall()">Copy install command</button>
                        </div>
                    </div>
                    <p id="fleet-url-hint" class="text-[11px] text-slate-500"></p>
                    <p id="fleet-bind-warn" class="hidden text-[11px] text-rose-400 font-semibold"></p>
                </div>

                <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
                    <div class="xl:col-span-2 p-4 rounded-xl bg-slate-900/60 border border-slate-800">
                        <h3 class="text-sm font-bold text-slate-100 mb-3">Managed computers</h3>
                        <div class="overflow-x-auto">
                            <table class="w-full text-xs">
                                <thead>
                                    <tr class="text-slate-500 text-left border-b border-slate-800">
                                        <th class="py-2 pr-2">Name</th>
                                        <th class="py-2 pr-2">Online</th>
                                        <th class="py-2 pr-2">CPU</th>
                                        <th class="py-2 pr-2">RAM</th>
                                        <th class="py-2 pr-2">Disk free</th>
                                        <th class="py-2 pr-2">Net</th>
                                        <th class="py-2 pr-2">Last seen</th>
                                        <th class="py-2">Agent</th>
                                    </tr>
                                </thead>
                                <tbody id="fleet-agent-rows">
                                    <tr><td colspan="8" class="py-4 text-slate-500">Loading…</td></tr>
                                </tbody>
                            </table>
                        </div>
                    </div>

                    <div id="fleet-detail" class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                        <h3 class="text-sm font-bold text-slate-100">Detail</h3>
                        <p class="text-slate-500 text-xs">Select a computer to view telemetry and queue commands.</p>
                    </div>
                </div>
            </div>
        `;

        await this.loadEnrollInfo();
        await this.refresh();
        this.startPoll();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        this._pollTimer = setInterval(() => this.refresh(true), 15000);
    },

    stopPoll() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
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
        return `${Number(v).toFixed(2)} MB/s`;
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
        this.renderTable();
        if (this._selected) {
            await this.loadDetail(this._selected, true);
        }
    },

    renderTable() {
        const tbody = document.getElementById('fleet-agent-rows');
        if (!tbody) return;
        if (!this._agents.length) {
            tbody.innerHTML = '<tr><td colspan="8" class="py-4 text-slate-500">No enrolled agents yet.</td></tr>';
            return;
        }
        tbody.innerHTML = this._agents.map((a) => {
            const online = a.Online ? '<span class="badge badge-ok">online</span>' : '<span class="badge badge-muted">offline</span>';
            const net = a.InternetOk === true ? 'OK' : (a.InternetOk === false ? 'DOWN' : '—');
            const sel = this._selected === a.Id ? 'bg-slate-800/80' : '';
            return `<tr class="border-b border-slate-800/60 hover:bg-slate-800/40 cursor-pointer ${sel}" onclick="FleetView.select('${this.escape(a.Id)}')">
                <td class="py-2 pr-2 font-mono text-cyan-300">${this.escape(a.ComputerName || a.Id)}</td>
                <td class="py-2 pr-2">${online}</td>
                <td class="py-2 pr-2">${this.fmtPct(a.CpuPct)}</td>
                <td class="py-2 pr-2">${this.fmtPct(a.RamPct)}</td>
                <td class="py-2 pr-2">${this.fmtPct(a.DiskFreePct)}</td>
                <td class="py-2 pr-2">${net}</td>
                <td class="py-2 pr-2 text-slate-400">${this.escape(a.LastSeen || '—')}</td>
                <td class="py-2">${this.escape(a.AgentVersion || '—')}</td>
            </tr>`;
        }).join('');
    },

    async select(agentId) {
        this._selected = agentId;
        this._lastLatency = null;
        this.renderTable();
        await this.loadDetail(agentId);
    },

    async loadDetail(agentId, silent) {
        const box = document.getElementById('fleet-detail');
        if (!box) return;
        if (!silent) {
            box.innerHTML = '<h3 class="text-sm font-bold text-slate-100">Detail</h3><div class="text-slate-500 text-xs">Loading…</div>';
        }
        const res = await API.request(`fleet/agents/${agentId}`, 'GET', null, 15000, { silent: !!silent });
        if (!res.Success || !res.Data) {
            box.innerHTML = `<p class="text-rose-400 text-xs">${this.escape(res.Message || 'Failed')}</p>`;
            return;
        }
        const d = res.Data;
        const a = d.Agent || d.agent || {};
        const cmds = API.asArray(d.Commands || d.commands);
        const alerts = API.asArray(d.Alerts || d.alerts);
        const inv = a.Inventory;

        const procData = this.latestResultData(cmds, 'GetProcesses');
        const processes = procData ? API.asArray(procData) : [];
        const printerBundle = this.latestResultData(cmds, 'GetPrinters') || (inv && inv.Printers ? { Printers: inv.Printers } : null);
        const printers = printerBundle ? API.asArray(printerBundle.Printers || printerBundle) : [];
        const netSmoke = this.latestResultData(cmds, 'NetHealthSmoke');
        const lat = this._lastLatency;

        box.innerHTML = `
            <h3 class="text-sm font-bold text-slate-100">${this.escape(a.ComputerName || agentId)}</h3>
            <div class="flex flex-wrap gap-2 text-[11px]">
                <span class="badge ${a.Online ? 'badge-ok' : 'badge-muted'}">${a.Online ? 'online' : 'offline'}</span>
                <span class="badge badge-muted">${this.escape(a.IPv4 || 'no IP')}</span>
                <span class="badge badge-muted">${this.escape(a.UserName || '')}</span>
            </div>
            <div class="grid grid-cols-2 gap-2 text-xs font-mono">
                <div>CPU: ${this.fmtPct(a.CpuPct)}</div>
                <div>RAM: ${this.fmtPct(a.RamPct)}</div>
                <div>Disk free: ${this.fmtPct(a.DiskFreePct)}</div>
                <div>Disk R/W: ${this.fmtIo(a.DiskReadMBps)} / ${this.fmtIo(a.DiskWriteMBps)}</div>
                <div>Last: ${this.escape(a.LastSeen || '—')}</div>
                <div>Agent→net: ${a.InternetOk === true ? 'OK' : (a.InternetOk === false ? 'DOWN' : '—')}</div>
            </div>
            ${lat ? `<div class="text-[11px] text-cyan-300">Console→PC latency: ${lat.ProbeOk || lat.Success ? `avg ${lat.AvgMs} ms (min ${lat.MinMs}, max ${lat.MaxMs}) to ${this.escape(lat.TargetHost)}` : this.escape(lat.Error || 'failed')}</div>` : ''}
            ${netSmoke ? `<div class="text-[11px] text-emerald-300">Agent internet: ping ${netSmoke.PingOk ? netSmoke.InternetLatencyMs + ' ms' : 'fail'} · download smoke ${netSmoke.DownloadOk ? netSmoke.DownloadMbps + ' Mbps' : 'fail'}</div>` : ''}

            <div class="flex flex-wrap gap-2 pt-2 border-t border-slate-800">
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('FlushDns')">Flush DNS</button>
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('RestartSpooler')">Restart Spooler</button>
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('CollectInventory')">Collect Inventory</button>
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetProcesses')">Processes</button>
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('GetPrinters')">Printers</button>
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.pingAgent()">Ping PC</button>
                <button type="button" class="action-btn cyan text-[11px]" onclick="FleetView.queueCmd('NetHealthSmoke')">Net smoke</button>
                <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.queueMessage()">Message</button>
            </div>
            <div class="flex flex-wrap gap-2">
                <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.confirmQueue('SfcScannow', 'Run SFC /scannow on the remote PC? This can take a long time and will block other agent commands until finished.')">SFC scan</button>
                <button type="button" class="action-btn amber text-[11px]" onclick="FleetView.confirmQueue('ChkdskScan', 'Run read-only CHKDSK on C: (no /F)?')">CHKDSK scan</button>
                <button type="button" class="action-btn rose text-[11px]" onclick="FleetView.confirmQueue('ChkdskScheduleFix', 'Schedule CHKDSK /F on C: for next restart? This does NOT reboot the PC.')">CHKDSK schedule /F</button>
                <button type="button" class="action-btn rose text-[11px]" onclick="FleetView.revokeAgent()">Remove</button>
            </div>

            ${processes.length ? `
            <div class="text-xs">
                <p class="text-slate-300 font-semibold mb-1">Processes (top by memory)</p>
                <div class="max-h-36 overflow-auto border border-slate-800 rounded-lg">
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
                                    <td class="p-1"><button type="button" class="text-rose-400 hover:underline" onclick="FleetView.endProcess(${Number(id)})">End</button></td>
                                </tr>`;
                            }).join('')}
                        </tbody>
                    </table>
                </div>
            </div>` : ''}

            ${printers.length ? `
            <div class="text-xs">
                <p class="text-slate-300 font-semibold mb-1">Printers</p>
                <ul class="space-y-1 text-[10px] text-slate-400 font-mono max-h-28 overflow-auto">
                    ${printers.map((pr) => `<li>${this.escape(pr.Name || '')} · ${this.escape(pr.DriverName || '')} · ${this.escape(pr.PortName || '')} · ${this.escape(pr.PrinterStatus != null ? pr.PrinterStatus : '')}</li>`).join('')}
                </ul>
            </div>` : ''}

            ${alerts.length ? `<div class="text-xs"><p class="text-amber-400 font-semibold mb-1">Alerts</p><ul class="space-y-1 text-slate-400">${alerts.slice(0, 5).map((al) => `<li>${this.escape(al.Type)}: ${this.escape(al.Message)}</li>`).join('')}</ul></div>` : ''}
            ${inv ? `<div class="text-xs"><p class="text-emerald-400 font-semibold mb-1">Inventory</p><pre class="text-[10px] text-slate-400 max-h-24 overflow-auto">${this.escape(JSON.stringify(inv, null, 2))}</pre></div>` : ''}
            <div class="text-xs">
                <p class="text-slate-300 font-semibold mb-1">Command history</p>
                <div class="max-h-40 overflow-auto space-y-1 font-mono text-[10px] text-slate-400">
                    ${cmds.length ? cmds.map((c) => {
                        const extra = c.Result && c.Result.Message ? ' — ' + this.escape(c.Result.Message) : '';
                        const dur = c.Result && c.Result.DurationMs != null ? ` (${c.Result.DurationMs}ms)` : '';
                        return `<div>${this.escape(c.CreatedAt)} · ${this.escape(c.Type)} · ${this.escape(c.Status)}${dur}${extra}</div>`;
                    }).join('') : '<div class="text-slate-500">No commands yet.</div>'}
                </div>
            </div>
        `;
    },

    async queueCmd(type, payload) {
        if (!this._selected) return;
        const res = await API.request('fleet/commands', 'POST', { AgentId: this._selected, Type: type, Payload: payload || {} }, 20000);
        if (res.Success) {
            LiveConsole.log(`Queued ${type} for agent`, 'SUCCESS', res.Data);
            // Give agent a moment to pick up short commands, then refresh
            setTimeout(() => this.loadDetail(this._selected, true), 4000);
            await this.loadDetail(this._selected);
        } else {
            LiveConsole.log(res.Message || 'Queue failed', 'ERROR');
        }
    },

    async confirmQueue(type, promptText) {
        if (!this._selected) return;
        if (!confirm(promptText)) return;
        await this.queueCmd(type);
    },

    async endProcess(pid) {
        if (!this._selected) return;
        if (!confirm(`End process PID ${pid} on the remote PC?`)) return;
        await this.queueCmd('EndProcess', { ProcessId: pid });
    },

    async pingAgent() {
        if (!this._selected) return;
        LiveConsole.log('Probing console→agent latency…', 'INFO');
        const res = await API.request(`fleet/agents/${this._selected}/latency`, 'GET', null, 20000);
        if (res.Data) {
            this._lastLatency = res.Data;
            if (res.Success) {
                LiveConsole.log(`Latency avg ${res.Data.AvgMs} ms to ${res.Data.TargetHost}`, 'SUCCESS');
            } else {
                LiveConsole.log(res.Message || 'Latency probe failed', 'WARN');
            }
            await this.loadDetail(this._selected, true);
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
            this._selected = null;
            await this.refresh();
            const box = document.getElementById('fleet-detail');
            if (box) box.innerHTML = '<p class="text-slate-500 text-xs">PC removed from Computers.</p>';
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

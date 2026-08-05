const PrintersView = {
    _selected: null,
    _printers: [],
    _busy: false,

    async render(container) {
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';
        this._selected = null;
        this._printers = [];
        this._busy = false;

        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Printers & Spooler</h2>
                        <p class="text-xs text-slate-400">Queues, spooler health, TCP/IP network tests, and print events.
                            ${admin ? '' : '<span class="text-amber-400">Repair actions need elevation.</span>'}
                        </p>
                    </div>
                    <button onclick="PrintersView.refreshAll()" class="action-btn cyan">Refresh all</button>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <div class="lg:col-span-1 p-4 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
                        <h3 class="text-sm font-bold text-slate-100">Printers</h3>
                        <div id="printers-list" class="space-y-1 max-h-80 overflow-auto text-xs font-mono">
                            <div class="text-slate-500">Loading…</div>
                        </div>
                    </div>
                    <div class="lg:col-span-2 p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3" id="printer-detail-panel">
                        <h3 class="text-sm font-bold text-slate-100">Printer detail</h3>
                        <p class="text-xs text-slate-500">Select a printer from the list.</p>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <div class="flex items-center justify-between flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100">Print Spooler</h3>
                        <div class="flex flex-wrap gap-2">
                            <button onclick="PrintersView.restartSpooler()" class="action-btn amber" ${needsElev}>Restart spooler</button>
                            <button onclick="PrintersView.killSpooler()" class="action-btn rose" ${needsElev}>Kill spooler process</button>
                            <button onclick="PrintersView.setSpoolerAuto()" class="action-btn emerald" ${needsElev}>Set automatic</button>
                        </div>
                    </div>
                    <div id="spooler-panel" class="text-xs font-mono text-slate-400">Loading spooler…</div>
                    ${admin ? '' : '<p class="text-[11px] text-amber-400">Needs elevation — relaunch as Administrator for spooler repair.</p>'}
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                    <div class="flex items-center justify-between flex-wrap gap-2">
                        <h3 class="text-sm font-bold text-slate-100">Print queue</h3>
                        <button onclick="PrintersView.clearQueue()" class="action-btn rose" ${needsElev}>Clear all jobs</button>
                    </div>
                    <div class="overflow-x-auto">
                        <table class="w-full text-xs font-mono text-left">
                            <thead class="text-slate-500 border-b border-slate-800">
                                <tr>
                                    <th class="py-2 pr-2">Printer</th>
                                    <th class="py-2 pr-2">Job</th>
                                    <th class="py-2 pr-2">Document</th>
                                    <th class="py-2 pr-2">Owner</th>
                                    <th class="py-2 pr-2">Pages</th>
                                    <th class="py-2 pr-2">Age</th>
                                    <th class="py-2 pr-2">Status</th>
                                    <th class="py-2 text-right">Actions</th>
                                </tr>
                            </thead>
                            <tbody id="queue-tbody">
                                <tr><td colspan="8" class="text-slate-500 py-3">Loading jobs…</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">Network test (TCP/IP)</h3>
                            <button onclick="PrintersView.runNetworkTest()" class="action-btn cyan text-[11px]">Run test</button>
                        </div>
                        <p class="text-[11px] text-slate-500">Tests ping, DNS, ports 9100/515, HTTP/HTTPS for the selected TCP/IP printer.</p>
                        <div id="network-test-panel" class="text-xs font-mono text-slate-400">Select a TCP/IP printer to test.</div>
                    </div>
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
                        <div class="flex items-center justify-between">
                            <h3 class="text-sm font-bold text-slate-100">Print events</h3>
                            <button onclick="PrintersView.loadEvents()" class="action-btn cyan text-[11px]">Refresh</button>
                        </div>
                        <div id="events-panel" class="text-xs font-mono text-slate-400 max-h-64 overflow-auto">Loading…</div>
                    </div>
                </div>

                <div id="printers-result" class="result-panel text-slate-500">Action results appear here.</div>
            </div>
        `;

        await this.refreshAll();
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    },

    setBusy(msg) {
        const el = document.getElementById('printers-result');
        if (el) el.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${this.escape(msg)}</div>`;
    },

    showResult(message, data) {
        const el = document.getElementById('printers-result');
        if (!el) return;
        if (typeof ResultRenderer !== 'undefined') {
            ResultRenderer.mount(el, message, data);
        } else {
            el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
        }
    },

    adminAttr() {
        return window.__LOC_ADMIN ? '' : 'disabled title="Needs elevation"';
    },

    async refreshAll() {
        if (this._busy) return;
        this._busy = true;
        this.setBusy('Refreshing printers, spooler, queue, and events…');
        try {
            await Promise.all([
                this.loadPrinters(),
                this.loadSpooler(),
                this.loadQueue(),
                this.loadEvents()
            ]);
            this.showResult('Refreshed', null);
        } finally {
            this._busy = false;
        }
    },

    async loadPrinters() {
        const list = document.getElementById('printers-list');
        const res = await API.diagnostic('printers', 'GetPrinters', '', 15000);
        if (!res.Success) {
            if (list) list.innerHTML = `<div class="text-rose-300">${this.escape(res.Message || 'Failed')}</div>`;
            return;
        }
        const data = res.Data || {};
        this._printers = API.asArray(data.Printers || data);
        if (!list) return;
        if (!this._printers.length) {
            list.innerHTML = '<div class="text-slate-500">No printers found.</div>';
            return;
        }
        list.innerHTML = this._printers.map((p) => {
            const sel = this._selected === p.Name;
            const def = p.Default ? ' <span class="text-cyan-400">★</span>' : '';
            const jobs = p.JobCount > 0 ? ` <span class="text-amber-400">(${p.JobCount})</span>` : '';
            return `
                <button type="button"
                    class="w-full text-left px-2 py-1.5 rounded ${sel ? 'bg-cyan-500/20 border border-cyan-500/40' : 'hover:bg-slate-800/60 border border-transparent'}"
                    onclick="PrintersView.selectPrinter(${JSON.stringify(p.Name)})">
                    <span class="text-slate-200">${this.escape(p.Name)}</span>${def}${jobs}
                    <div class="text-[10px] text-slate-500 truncate">${this.escape(p.PortName || '')}${p.PortHost ? ' → ' + this.escape(p.PortHost) : ''}</div>
                </button>`;
        }).join('');

        if (this._selected && !this._printers.some((p) => p.Name === this._selected)) {
            this._selected = null;
        }
        if (this._selected) {
            await this.loadDetail(this._selected);
        }
    },

    async selectPrinter(name) {
        this._selected = name;
        await this.loadPrinters();
        await this.loadDetail(name);
        await this.loadQueue(name);
        this.renderNetworkPlaceholder();
    },

    async loadDetail(name) {
        const panel = document.getElementById('printer-detail-panel');
        if (!panel) return;
        panel.innerHTML = `<h3 class="text-sm font-bold text-slate-100">Printer detail</h3><div class="result-busy"><span class="spinner"></span> Loading ${this.escape(name)}…</div>`;

        const res = await API.diagnostic('printers', 'GetPrinterDetail', `PrinterName=${encodeURIComponent(name)}`, 15000);
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';

        if (!res.Success) {
            panel.innerHTML = `<h3 class="text-sm font-bold text-slate-100">Printer detail</h3><p class="text-rose-300 text-xs">${this.escape(res.Message)}</p>`;
            return;
        }
        const d = res.Data || {};
        const lastErr = d.LastError;
        const errBlock = lastErr
            ? `<div class="mt-2 p-2 rounded bg-rose-500/10 border border-rose-500/30 text-rose-300 text-[11px]">
                <strong>Last error</strong> (${this.escape(lastErr.TimeCreated)} #${lastErr.Id})<br/>${this.escape(lastErr.Message)}
               </div>`
            : '';

        panel.innerHTML = `
            <div class="flex items-start justify-between flex-wrap gap-2">
                <div>
                    <h3 class="text-sm font-bold text-slate-100">${this.escape(d.Name)}${d.Default ? ' <span class="text-cyan-400 text-xs">DEFAULT</span>' : ''}</h3>
                    <span class="badge ${/Normal|Idle/i.test(d.Status || '') ? 'badge-ok' : 'badge-muted'}">${this.escape(d.Status || '—')}</span>
                </div>
                <div class="flex flex-wrap gap-2">
                    <button onclick="PrintersView.testPage(${JSON.stringify(name)})" class="action-btn emerald text-[11px]" ${needsElev}>Test page</button>
                    <button onclick="PrintersView.clearQueue(${JSON.stringify(name)})" class="action-btn amber text-[11px]" ${needsElev}>Clear queue</button>
                    <button onclick="PrintersView.recreatePort(${JSON.stringify(name)})" class="action-btn cyan text-[11px]" ${needsElev}>Recreate TCP/IP port</button>
                    <button onclick="PrintersView.removeGhost(${JSON.stringify(name)})" class="action-btn rose text-[11px]" ${needsElev}>Remove ghost</button>
                </div>
            </div>
            <div class="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs font-mono text-slate-400 mt-3">
                <div><strong class="text-slate-300">Driver:</strong> ${this.escape(d.DriverName)}</div>
                <div><strong class="text-slate-300">Version:</strong> ${this.escape(d.DriverVersion || '—')}</div>
                <div><strong class="text-slate-300">Driver date:</strong> ${this.escape(d.DriverDate || '—')}</div>
                <div><strong class="text-slate-300">Port:</strong> ${this.escape(d.PortName)} (${this.escape(d.PortType || '')})</div>
                <div><strong class="text-slate-300">Host:</strong> ${this.escape(d.PortHost || '—')}</div>
                <div><strong class="text-slate-300">Jobs:</strong> ${d.JobCount != null ? d.JobCount : '—'}</div>
                <div><strong class="text-slate-300">Shared:</strong> ${d.Shared ? 'Yes' : 'No'}</div>
                <div><strong class="text-slate-300">Local:</strong> ${d.Local ? 'Yes' : 'No'}</div>
                <div><strong class="text-slate-300">Processor:</strong> ${this.escape(d.PrintProcessor || '—')}</div>
            </div>
            ${errBlock}
        `;
    },

    async loadSpooler() {
        const el = document.getElementById('spooler-panel');
        const res = await API.diagnostic('printers', 'GetSpooler', '', 12000);
        if (!el) return;
        if (!res.Success) {
            el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`;
            return;
        }
        const s = res.Data || {};
        const depOn = API.asArray(s.ServicesDependedOn).map((d) => `${d.Name} (${d.Status})`).join(', ') || '—';
        const depBy = API.asArray(s.DependentServices).map((d) => `${d.Name} (${d.Status})`).join(', ') || '—';
        const recovery = s.Recovery || {};
        const actions = API.asArray(recovery.Actions).map((a) => a.Action).filter(Boolean).join('; ') || '—';

        el.innerHTML = `
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
                <div><strong class="text-slate-300">Status:</strong> <span class="badge ${s.Status === 'Running' ? 'badge-ok' : 'badge-muted'}">${this.escape(s.Status)}</span></div>
                <div><strong class="text-slate-300">Start type:</strong> ${this.escape(s.StartType)}</div>
                <div><strong class="text-slate-300">Depends on:</strong> ${this.escape(depOn)}</div>
                <div><strong class="text-slate-300">Dependents:</strong> ${this.escape(depBy)}</div>
            </div>
            <div class="mt-2 text-[11px] text-slate-500">Recovery: ${this.escape(actions)}${recovery.ResetPeriod ? ' · reset ' + this.escape(recovery.ResetPeriod) : ''}</div>
        `;
    },

    async loadQueue(printerName) {
        const tbody = document.getElementById('queue-tbody');
        const q = printerName ? `PrinterName=${encodeURIComponent(printerName)}` : '';
        const res = await API.diagnostic('printers', 'GetQueueJobs', q, 15000);
        const admin = !!window.__LOC_ADMIN;
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';

        if (!tbody) return;
        if (!res.Success) {
            tbody.innerHTML = `<tr><td colspan="8" class="text-rose-300 py-2">${this.escape(res.Message)}</td></tr>`;
            return;
        }
        const rows = API.asArray(res.Data);
        if (!rows.length) {
            tbody.innerHTML = '<tr><td colspan="8" class="text-slate-500 py-3">No queued jobs.</td></tr>';
            return;
        }
        tbody.innerHTML = rows.map((j) => `
            <tr class="border-t border-slate-800/60 hover:bg-slate-800/30">
                <td class="py-1.5 pr-2 text-slate-300">${this.escape(j.PrinterName)}</td>
                <td class="py-1.5 pr-2">${j.JobId}</td>
                <td class="py-1.5 pr-2 text-slate-200">${this.escape(j.Document)}</td>
                <td class="py-1.5 pr-2">${this.escape(j.Owner || '—')}</td>
                <td class="py-1.5 pr-2">${j.Pages != null ? j.Pages : '—'}</td>
                <td class="py-1.5 pr-2">${this.escape(j.Age || '—')}</td>
                <td class="py-1.5 pr-2">${this.escape(j.Status)}</td>
                <td class="py-1.5 text-right space-x-1 whitespace-nowrap">
                    <button class="action-btn rose text-[10px] px-1 py-0.5" ${needsElev}
                        onclick="PrintersView.cancelJob(${JSON.stringify(j.PrinterName)}, ${j.JobId})">Cancel</button>
                    <button class="action-btn amber text-[10px] px-1 py-0.5" ${needsElev}
                        onclick="PrintersView.pauseJob(${JSON.stringify(j.PrinterName)}, ${j.JobId})">Pause</button>
                    <button class="action-btn emerald text-[10px] px-1 py-0.5" ${needsElev}
                        onclick="PrintersView.resumeJob(${JSON.stringify(j.PrinterName)}, ${j.JobId})">Resume</button>
                </td>
            </tr>
        `).join('');
    },

    renderNetworkPlaceholder() {
        const el = document.getElementById('network-test-panel');
        if (!el) return;
        const p = this._printers.find((x) => x.Name === this._selected);
        if (!p) {
            el.textContent = 'Select a TCP/IP printer to test.';
            return;
        }
        const isTcp = p.PortHost || (p.PortName && /^(IP_|TCP|\d)/i.test(p.PortName));
        el.innerHTML = isTcp
            ? `Ready to test <strong class="text-slate-300">${this.escape(p.Name)}</strong> → ${this.escape(p.PortHost || p.PortName)}`
            : `<span class="text-slate-500">${this.escape(p.Name)} is not a TCP/IP printer.</span>`;
    },

    async runNetworkTest() {
        if (!this._selected) {
            this.showResult('Select a printer first', null);
            return;
        }
        const el = document.getElementById('network-test-panel');
        if (el) el.innerHTML = '<div class="result-busy"><span class="spinner"></span> Running network probe (≤8s)…</div>';
        this.setBusy('Testing printer network…');

        const res = await API.diagnostic(
            'printers',
            'TestPrinterNetwork',
            `PrinterName=${encodeURIComponent(this._selected)}`,
            12000
        );

        if (!el) return;
        if (!res.Success) {
            el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`;
            this.showResult(res.Message, res.Data);
            return;
        }
        const d = res.Data || {};
        const ping = d.Ping || {};
        const fmtTcp = (t) => t && t.Open ? `open (${t.LatencyMs}ms)` : `closed${t && t.Error ? ': ' + t.Error : ''}`;
        const fmtHttp = (h) => h && h.Success ? `OK ${h.StatusCode || ''}` : 'fail';

        el.innerHTML = `
            <div class="space-y-1">
                <div><strong class="text-slate-300">Host:</strong> ${this.escape(d.Host)}</div>
                <div><strong class="text-slate-300">Ping:</strong> ${ping.Success ? `OK avg ${ping.AvgLatencyMs}ms, loss ${ping.PacketLossPct}%` : 'fail'}</div>
                <div><strong class="text-slate-300">DNS A:</strong> ${(d.Dns && d.Dns.A || []).join(', ') || '—'}</div>
                <div><strong class="text-slate-300">DNS AAAA:</strong> ${(d.Dns && d.Dns.AAAA || []).join(', ') || '—'}</div>
                <div><strong class="text-slate-300">TCP 9100:</strong> ${fmtTcp(d.Tcp9100)}</div>
                <div><strong class="text-slate-300">TCP 515:</strong> ${fmtTcp(d.Tcp515)}</div>
                <div><strong class="text-slate-300">HTTP:</strong> ${fmtHttp(d.Http)} · <strong class="text-slate-300">HTTPS:</strong> ${fmtHttp(d.Https)}</div>
                ${d.Ipv6 ? `<div><strong class="text-slate-300">IPv6 (${this.escape(d.Ipv6.Address)}):</strong> ${d.Ipv6.Success ? 'reachable' : 'unreachable'}</div>` : ''}
            </div>
        `;
        this.showResult(res.Message, d);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'WARN', d);
    },

    async loadEvents() {
        const el = document.getElementById('events-panel');
        if (el) el.innerHTML = '<div class="result-busy"><span class="spinner"></span> Loading events…</div>';
        const res = await API.diagnostic('printers', 'GetPrintEvents', 'MaxEvents=20', 15000);
        if (!el) return;
        if (!res.Success) {
            el.innerHTML = `<span class="text-rose-300">${this.escape(res.Message)}</span>`;
            return;
        }
        const rows = API.asArray(res.Data);
        if (!rows.length) {
            el.innerHTML = '<div class="text-slate-500">No recent print/spooler errors.</div>';
            return;
        }
        el.innerHTML = rows.map((e) => `
            <div class="mb-2 pb-2 border-b border-slate-800/60">
                <div class="text-slate-300">${this.escape(e.TimeCreated)} · ${this.escape(e.Level)} · #${e.Id}</div>
                <div class="text-[10px] text-slate-500">${this.escape(e.Provider)} / ${this.escape(e.LogName)}</div>
                <div class="text-slate-400 mt-0.5">${this.escape(e.Message)}</div>
            </div>
        `).join('');
    },

    requireAdmin() {
        if (!window.__LOC_ADMIN) {
            alert('Needs elevation');
            return false;
        }
        return true;
    },

    async restartSpooler() {
        if (!this.requireAdmin()) return;
        if (!confirm('Restart the Print Spooler service?')) return;
        this.setBusy('Restarting spooler…');
        const res = await API.action('printers', 'RestartSpooler', {});
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) {
            await this.loadSpooler();
            await this.loadPrinters();
        }
    },

    async killSpooler() {
        if (!this.requireAdmin()) return;
        if (!confirm('Force-kill spooler process and restart service?')) return;
        this.setBusy('Killing spooler process…');
        const res = await API.action('printers', 'KillSpoolerProcess', {});
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) await this.loadSpooler();
    },

    async setSpoolerAuto() {
        if (!this.requireAdmin()) return;
        this.setBusy('Setting spooler to Automatic…');
        const res = await API.action('printers', 'SetSpoolerAutomatic', {});
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) await this.loadSpooler();
    },

    async clearQueue(printerName) {
        if (!this.requireAdmin()) return;
        const name = printerName || '';
        const msg = name ? `Clear all jobs on "${name}"?` : 'Clear ALL print jobs on every printer?';
        if (!confirm(msg)) return;
        this.setBusy('Clearing queue…');
        const payload = name ? { PrinterName: name } : {};
        const res = await API.action('printers', 'ClearQueue', payload);
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) {
            await this.loadQueue(this._selected || '');
            await this.loadPrinters();
            if (this._selected) await this.loadDetail(this._selected);
        }
    },

    async testPage(name) {
        if (!this.requireAdmin()) return;
        if (!confirm(`Print test page on "${name}"?`)) return;
        this.setBusy('Sending test page…');
        const res = await API.action('printers', 'TestPage', { PrinterName: name });
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
    },

    async cancelJob(printerName, jobId) {
        if (!this.requireAdmin()) return;
        if (!confirm(`Cancel job ${jobId} on ${printerName}?`)) return;
        this.setBusy('Cancelling job…');
        const res = await API.action('printers', 'CancelJob', { PrinterName: printerName, JobId: jobId });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadQueue(this._selected || '');
    },

    async pauseJob(printerName, jobId) {
        if (!this.requireAdmin()) return;
        this.setBusy('Pausing job…');
        const res = await API.action('printers', 'PauseJob', { PrinterName: printerName, JobId: jobId });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadQueue(this._selected || '');
    },

    async resumeJob(printerName, jobId) {
        if (!this.requireAdmin()) return;
        this.setBusy('Resuming job…');
        const res = await API.action('printers', 'ResumeJob', { PrinterName: printerName, JobId: jobId });
        this.showResult(res.Message, res.Data);
        if (res.Success) await this.loadQueue(this._selected || '');
    },

    async recreatePort(name) {
        if (!this.requireAdmin()) return;
        if (!confirm(`Recreate TCP/IP port for "${name}"? This removes and re-adds the port.`)) return;
        this.setBusy('Recreating TCP/IP port…');
        const res = await API.action('printers', 'RecreateTcpIpPort', { PrinterName: name });
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) {
            await this.loadPrinters();
            await this.loadDetail(name);
        }
    },

    async removeGhost(name) {
        if (!this.requireAdmin()) return;
        if (!confirm(`Remove printer "${name}"? Use for stuck/ghost queue entries.`)) return;
        this.setBusy('Removing printer…');
        const res = await API.action('printers', 'RemoveGhostPrinter', { PrinterName: name });
        this.showResult(res.Message, res.Data);
        LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
        if (res.Success) {
            if (this._selected === name) this._selected = null;
            await this.loadPrinters();
            const panel = document.getElementById('printer-detail-panel');
            if (panel) {
                panel.innerHTML = '<h3 class="text-sm font-bold text-slate-100">Printer detail</h3><p class="text-xs text-slate-500">Select a printer from the list.</p>';
            }
        }
    }
};

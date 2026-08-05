const SystemView = {
    _pollId: null,
    _active: false,
    _openDisk: null,
    _hist: { cpu: [], mem: [], send: [], recv: [], diskRead: [], diskWrite: [] },

    async render(container) {
        this.stopPoll();
        this._active = true;
        this._hist = { cpu: [], mem: [], send: [], recv: [], diskRead: [], diskWrite: [] };
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">System &amp; Hardware Telemetry</h2>
                        <p class="text-xs text-slate-400">Live CPU, RAM, network, disk I/O graphs, and all fixed disks — polls every 2s while this page is open.</p>
                    </div>
                    <button type="button" onclick="SystemView.refresh(true)" class="action-btn cyan">Refresh Telemetry</button>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">PROCESSOR</span>
                            <i data-lucide="cpu" class="w-4 h-4 text-cyan-400"></i>
                        </div>
                        <div id="sys-cpu-usage" class="text-2xl font-bold font-mono text-slate-100">-- %</div>
                        <canvas id="sys-cpu-spark" class="w-full mt-2" style="height:44px"></canvas>
                        <div class="progress-track mt-2"><div id="sys-cpu-bar" class="progress-fill"></div></div>
                        <p id="sys-cpu-meta" class="text-[11px] text-slate-500 mt-2 truncate">Querying…</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">RAM USAGE</span>
                            <i data-lucide="database" class="w-4 h-4 text-emerald-400"></i>
                        </div>
                        <div id="sys-mem-usage" class="text-2xl font-bold font-mono text-slate-100">-- %</div>
                        <canvas id="sys-mem-spark" class="w-full mt-2" style="height:44px"></canvas>
                        <div class="progress-track mt-2"><div id="sys-mem-bar" class="progress-fill" style="background:var(--emerald)"></div></div>
                        <p id="sys-mem-meta" class="text-[11px] text-slate-500 mt-2">Querying…</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">NETWORK BANDWIDTH</span>
                            <i data-lucide="activity" class="w-4 h-4 text-sky-400"></i>
                        </div>
                        <div class="flex gap-4 text-sm font-mono mb-1">
                            <span class="text-cyan-300">↑ <span id="sys-net-up">0.00</span> Mb/s</span>
                            <span class="text-emerald-300">↓ <span id="sys-net-down">0.00</span> Mb/s</span>
                        </div>
                        <canvas id="sys-net-spark" class="w-full mt-1" style="height:48px"></canvas>
                        <p id="sys-net-ip" class="text-[11px] font-mono text-slate-300 mt-2 truncate">--</p>
                        <p id="sys-net-meta" class="text-[11px] text-slate-500 mt-1 truncate">Querying…</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">DISK I/O</span>
                            <i data-lucide="hard-drive" class="w-4 h-4 text-amber-400"></i>
                        </div>
                        <div class="flex gap-4 text-sm font-mono mb-1">
                            <span class="text-amber-300">R <span id="sys-dio-read">0.00</span> MB/s</span>
                            <span class="text-orange-300">W <span id="sys-dio-write">0.00</span> MB/s</span>
                        </div>
                        <canvas id="sys-dio-spark" class="w-full mt-1" style="height:48px"></canvas>
                        <p id="sys-dio-meta" class="text-[11px] text-slate-500 mt-2 font-mono">IOPS —</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">SYSTEM UPTIME</span>
                            <i data-lucide="clock" class="w-4 h-4 text-amber-400"></i>
                        </div>
                        <div id="sys-uptime" class="text-2xl font-bold font-mono text-slate-100">--</div>
                        <p id="sys-lastboot" class="text-[11px] text-slate-500 mt-2">Last boot: —</p>
                        <div id="sys-reboot-flag" class="mt-3 badge badge-muted">Checking…</div>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">GPU</span>
                            <i data-lucide="monitor" class="w-4 h-4 text-violet-300"></i>
                        </div>
                        <div id="sys-gpu-name" class="text-sm font-semibold text-slate-100 leading-snug">--</div>
                        <p id="sys-gpu-meta" class="text-[11px] text-slate-500 mt-2">Querying…</p>
                    </div>

                    <div id="sys-bat-card" class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md hidden">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">BATTERY</span>
                            <i data-lucide="battery" class="w-4 h-4 text-lime-400"></i>
                        </div>
                        <div id="sys-bat-pct" class="text-2xl font-bold font-mono text-slate-100">-- %</div>
                        <div class="progress-track mt-3"><div id="sys-bat-bar" class="progress-fill" style="background:#a3e635"></div></div>
                        <p id="sys-bat-meta" class="text-[11px] text-slate-500 mt-2">—</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-3">
                            <span class="text-xs font-mono text-slate-400">PROBLEM DEVICES</span>
                            <i data-lucide="alert-triangle" class="w-4 h-4 text-rose-400"></i>
                        </div>
                        <div id="sys-dev-count" class="text-2xl font-bold font-mono text-slate-100">--</div>
                        <p class="text-[11px] text-slate-500 mt-2">PnP devices not in OK state. Open Devices for details.</p>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                    <div class="section-title mb-3">Disks</div>
                    <p class="text-[11px] text-slate-500 mb-3">Fixed volumes — expand one at a time.</p>
                    <div id="sys-disks" class="space-y-2"></div>
                </div>

                <p id="sys-updated" class="text-[10px] font-mono text-slate-600">Updated: —</p>
            </div>
        `;
        lucide.createIcons();
        await this.refresh(true);
        this.startPoll();
    },

    startPoll() {
        this.stopPoll();
        // Soft poll only — force=1 every 2s was blocking the single-threaded API (~40s feel).
        this._pollId = setInterval(() => {
            if (!this._active || !document.getElementById('sys-cpu-usage')) {
                this.stopPoll();
                this._active = false;
                return;
            }
            this.refresh(false);
        }, 2000);
    },

    stopPoll() {
        if (this._pollId) {
            clearInterval(this._pollId);
            this._pollId = null;
        }
    },

    onTelemetry(data) {
        // Header refresh can also feed System when open (non-force path)
        if (!this._active || !document.getElementById('sys-cpu-usage')) {
            this._active = false;
            this.stopPoll();
            return;
        }
        this.applyTelemetry(data);
    },

    toggleDisk(letter) {
        this._openDisk = (this._openDisk === letter) ? null : letter;
        const wrap = document.getElementById('sys-disks');
        if (!wrap || !this._lastDisks) return;
        this.renderDisks(this._lastDisks);
    },

    renderDisks(disks) {
        const wrap = document.getElementById('sys-disks');
        if (!wrap) return;
        const list = API.asArray(disks);
        this._lastDisks = list;
        if (!list.length) {
            wrap.innerHTML = `<p class="text-xs text-slate-500">No fixed disks reported.</p>`;
            return;
        }
        if (!this._openDisk || !list.some((d) => d.Letter === this._openDisk)) {
            this._openDisk = list[0].Letter;
        }
        wrap.innerHTML = list.map((d) => {
            const open = d.Letter === this._openDisk;
            const letter = String(d.Letter || '').replace(/"/g, '');
            const label = `${d.Letter}${d.VolumeName ? ' · ' + d.VolumeName : ''}`;
            return `
                <div class="border border-slate-700/80 rounded-lg overflow-hidden">
                    <button type="button" class="w-full flex items-center justify-between px-3 py-2 text-left text-xs font-mono text-slate-200 hover:bg-slate-800/60"
                        onclick="SystemView.toggleDisk('${letter}')">
                        <span>${this.escape(label)} — ${d.UsedPct ?? '--'}% used</span>
                        <span class="text-slate-500">${open ? '▾' : '▸'}</span>
                    </button>
                    ${open ? `
                    <div class="px-3 pb-3 pt-1 bg-slate-950/40">
                        <div class="text-lg font-bold font-mono text-slate-100">${d.UsedPct ?? '--'} %</div>
                        <div class="progress-track mt-2"><div class="progress-fill" style="width:${d.UsedPct ?? 0}%;background:var(--amber,#f59e0b)"></div></div>
                        <p class="text-[11px] text-slate-500 mt-2">${d.FreeGB ?? '?'} GB free / ${d.SizeGB ?? '?'} GB</p>
                    </div>` : ''}
                </div>`;
        }).join('');
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    applyTelemetry(d) {
        if (!d) return;

        if (d.Cpu) {
            const el = document.getElementById('sys-cpu-usage');
            const bar = document.getElementById('sys-cpu-bar');
            const meta = document.getElementById('sys-cpu-meta');
            if (el) el.innerText = `${d.Cpu.UsagePct ?? '--'} %`;
            if (bar) bar.style.width = `${d.Cpu.UsagePct ?? 0}%`;
            if (meta) {
                const cores = d.Cpu.Cores != null ? `${d.Cpu.Cores}c` : '';
                const logical = d.Cpu.Logical != null ? `${d.Cpu.Logical}t` : '';
                meta.innerText = [d.Cpu.Name, [cores, logical].filter(Boolean).join(' / ')].filter(Boolean).join(' · ') || '—';
            }
            Sparkline.push(this._hist.cpu, d.Cpu.UsagePct);
            Sparkline.draw(document.getElementById('sys-cpu-spark'), [{ data: this._hist.cpu, color: '#22d3ee' }], { max: 100 });
        }

        if (d.Memory) {
            const el = document.getElementById('sys-mem-usage');
            const bar = document.getElementById('sys-mem-bar');
            const meta = document.getElementById('sys-mem-meta');
            if (el) el.innerText = `${d.Memory.UsedPct ?? '--'} %`;
            if (bar) bar.style.width = `${d.Memory.UsedPct ?? 0}%`;
            if (meta) {
                const used = d.Memory.UsedGB != null ? d.Memory.UsedGB : '?';
                const total = d.Memory.TotalGB != null ? d.Memory.TotalGB : '?';
                meta.innerText = `${used} GB used / ${total} GB total`;
            }
            Sparkline.push(this._hist.mem, d.Memory.UsedPct);
            Sparkline.draw(document.getElementById('sys-mem-spark'), [{ data: this._hist.mem, color: '#34d399' }], { max: 100 });
        }

        const disks = d.Disks && API.asArray(d.Disks).length ? API.asArray(d.Disks) : (d.Disk ? [d.Disk] : []);
        this.renderDisks(disks);

        if (d.Host) {
            const up = document.getElementById('sys-uptime');
            const boot = document.getElementById('sys-lastboot');
            const flag = document.getElementById('sys-reboot-flag');
            if (up) up.innerText = d.Host.UptimeFormatted || '--';
            if (boot) boot.innerText = d.Host.LastBoot ? `Last boot: ${d.Host.LastBoot}` : 'Last boot: —';
            if (flag) {
                if (d.Host.PendingReboot) {
                    flag.className = 'mt-3 badge badge-warn';
                    flag.innerText = 'REBOOT PENDING';
                } else {
                    flag.className = 'mt-3 badge badge-ok';
                    flag.innerText = 'SYSTEM HEALTHY';
                }
            }
            const hostEl = document.getElementById('host-name');
            if (hostEl && d.Host.ComputerName) hostEl.innerText = d.Host.ComputerName;
        }

        if (d.Network) {
            const upEl = document.getElementById('sys-net-up');
            const downEl = document.getElementById('sys-net-down');
            const ip = document.getElementById('sys-net-ip');
            const meta = document.getElementById('sys-net-meta');
            const send = Number(d.Network.SendMbps) || 0;
            const recv = Number(d.Network.RecvMbps) || 0;
            if (upEl) upEl.innerText = send.toFixed(2);
            if (downEl) downEl.innerText = recv.toFixed(2);
            Sparkline.push(this._hist.send, send);
            Sparkline.push(this._hist.recv, recv);
            Sparkline.draw(document.getElementById('sys-net-spark'), [
                { data: this._hist.send, color: '#22d3ee' },
                { data: this._hist.recv, color: '#34d399' }
            ], { floorMax: 1 });
            if (d.Network.Connected) {
                const parts = [];
                if (d.Network.IPv4) parts.push(d.Network.IPv4);
                if (d.Network.IPv6) parts.push(d.Network.IPv6);
                if (ip) {
                    ip.innerText = parts.length ? parts.join(' · ') : 'UP';
                    ip.title = d.Network.IPv6Full ? `IPv6 full: ${d.Network.IPv6Full}` : '';
                }
                let metaText = d.Network.Adapter || 'Connected';
                if (d.Vpn && d.Vpn.Connected) {
                    metaText += ` · VPN ${d.Vpn.Name || ''} (${d.Vpn.TunnelType || ''}) ${d.Vpn.ServerAddress || ''}`.trim();
                }
                if (meta) meta.innerText = metaText;
            } else {
                if (ip) { ip.innerText = 'DOWN'; ip.title = ''; }
                if (meta) meta.innerText = 'No enabled IP adapter';
            }
        }

        if (d.DiskIo) {
            const rEl = document.getElementById('sys-dio-read');
            const wEl = document.getElementById('sys-dio-write');
            const meta = document.getElementById('sys-dio-meta');
            const read = Number(d.DiskIo.ReadMBps) || 0;
            const write = Number(d.DiskIo.WriteMBps) || 0;
            if (rEl) rEl.innerText = read.toFixed(2);
            if (wEl) wEl.innerText = write.toFixed(2);
            Sparkline.push(this._hist.diskRead, read);
            Sparkline.push(this._hist.diskWrite, write);
            Sparkline.draw(document.getElementById('sys-dio-spark'), [
                { data: this._hist.diskRead, color: '#fbbf24' },
                { data: this._hist.diskWrite, color: '#fb923c' }
            ], { floorMax: 1 });
            if (meta) {
                const ri = d.DiskIo.ReadIops != null ? d.DiskIo.ReadIops : '--';
                const wi = d.DiskIo.WriteIops != null ? d.DiskIo.WriteIops : '--';
                meta.innerText = `IOPS R ${ri} · W ${wi} (physical _Total)`;
            }
        }

        if (d.Gpu) {
            const name = document.getElementById('sys-gpu-name');
            const meta = document.getElementById('sys-gpu-meta');
            if (name) name.innerText = d.Gpu.Name || '--';
            if (meta) {
                const parts = [];
                if (d.Gpu.DriverVersion) parts.push(`Driver ${d.Gpu.DriverVersion}`);
                if (d.Gpu.AdapterRAMGB != null) parts.push(`${d.Gpu.AdapterRAMGB} GB`);
                meta.innerText = parts.join(' · ') || '—';
            }
        }

        const batCard = document.getElementById('sys-bat-card');
        if (batCard) {
            if (d.Battery && d.Battery.ChargePct != null) {
                batCard.classList.remove('hidden');
                const pct = document.getElementById('sys-bat-pct');
                const bar = document.getElementById('sys-bat-bar');
                const meta = document.getElementById('sys-bat-meta');
                if (pct) pct.innerText = `${d.Battery.ChargePct} %`;
                if (bar) bar.style.width = `${d.Battery.ChargePct}%`;
                if (meta) meta.innerText = d.Battery.Name || `Status ${d.Battery.Status || '—'}`;
            } else {
                batCard.classList.add('hidden');
            }
        }

        const dev = document.getElementById('sys-dev-count');
        if (dev) {
            if (d.Devices && d.Devices.ProblemCount != null) {
                dev.innerText = String(d.Devices.ProblemCount);
                if (d.Devices.ProblemCount > 0) dev.classList.add('text-rose-400');
                else dev.classList.remove('text-rose-400');
            } else {
                dev.innerText = '--';
            }
        }

        const updated = document.getElementById('sys-updated');
        if (updated) updated.innerText = d.Updated ? `Updated: ${d.Updated}` : 'Updated: —';
    },

    async refresh(force) {
        const q = force ? 'telemetry?force=1' : 'telemetry';
        const res = await API.request(q, 'GET', null, 12000, { silent: true });
        if (res.Success && res.Data) {
            this.applyTelemetry(res.Data);
        } else if (force) {
            LiveConsole.log(res.Message || 'Telemetry failed', 'ERROR');
        }
    }
};

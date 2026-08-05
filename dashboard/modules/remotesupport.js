const RemoteSupportView = {
    _busy: false,

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Remote Support (RustDesk)</h2>
                        <p class="text-xs text-slate-400">Install, monitor, and control RustDesk on this PC.</p>
                    </div>
                    <button type="button" onclick="RemoteSupportView.refresh()" class="action-btn cyan">Refresh status</button>
                </div>

                <p class="text-[11px] text-slate-500 border border-slate-800 rounded-lg px-3 py-2 bg-slate-950/40">
                    Remote access passwords are never collected, returned, or displayed by LocalOpsConsole.
                </p>

                <div id="rs-admin-note" class="hidden text-[11px] text-amber-400"></div>

                <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-2">
                            <span class="text-xs font-mono text-slate-400">INSTALLED</span>
                            <i data-lucide="package" class="w-4 h-4 text-cyan-400"></i>
                        </div>
                        <div id="rs-installed" class="text-lg font-bold font-mono text-slate-100">—</div>
                        <p id="rs-version" class="text-[11px] text-slate-500 mt-2 font-mono">Version —</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-2">
                            <span class="text-xs font-mono text-slate-400">RUNNING</span>
                            <i data-lucide="activity" class="w-4 h-4 text-emerald-400"></i>
                        </div>
                        <div id="rs-running" class="text-lg font-bold font-mono text-slate-100">—</div>
                        <p id="rs-process-meta" class="text-[11px] text-slate-500 mt-2 font-mono">Process —</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                        <div class="flex items-center justify-between mb-2">
                            <span class="text-xs font-mono text-slate-400">SERVICE</span>
                            <i data-lucide="server" class="w-4 h-4 text-amber-400"></i>
                        </div>
                        <div id="rs-service" class="text-lg font-bold font-mono text-slate-100">—</div>
                        <p id="rs-service-meta" class="text-[11px] text-slate-500 mt-2 font-mono">—</p>
                    </div>

                    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md sm:col-span-2 xl:col-span-3">
                        <div class="flex items-center justify-between mb-2 flex-wrap gap-2">
                            <span class="text-xs font-mono text-slate-400">RUSTDESK ID</span>
                            <button type="button" id="rs-copy-btn" onclick="RemoteSupportView.copyId()" class="action-btn cyan text-[11px]" disabled>Copy ID</button>
                        </div>
                        <div id="rs-id" class="text-2xl font-bold font-mono text-slate-100 tracking-wide">—</div>
                        <p id="rs-path" class="text-[11px] text-slate-500 mt-2 font-mono truncate">Install path —</p>
                    </div>
                </div>

                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 backdrop-blur-md">
                    <div class="section-title">Actions</div>
                    <p id="rs-install-hint" class="text-[11px] text-slate-500 mb-3 hidden"></p>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" id="rs-btn-install" onclick="RemoteSupportView.install()" class="action-btn emerald">Install RustDesk</button>
                        <button type="button" id="rs-btn-start" onclick="RemoteSupportView.action('StartRustDesk')" class="action-btn emerald">Start</button>
                        <button type="button" id="rs-btn-stop" onclick="RemoteSupportView.action('StopRustDesk')" class="action-btn rose">Stop</button>
                        <button type="button" id="rs-btn-restart" onclick="RemoteSupportView.action('RestartRustDeskService')" class="action-btn amber">Restart service</button>
                        <button type="button" id="rs-btn-open" onclick="RemoteSupportView.action('OpenRustDesk')" class="action-btn cyan">Open RustDesk</button>
                    </div>
                </div>

                <div id="rs-result" class="result-panel text-slate-500 text-xs font-mono">Loading status…</div>
            </div>
        `;
        this._status = null;
        await this.refresh();
    },

    adminGate(needsAdmin) {
        if (!needsAdmin) return true;
        if (window.__LOC_ADMIN) return true;
        alert('Needs elevation — relaunch start.bat as Administrator.');
        return false;
    },

    setBusy(running) {
        this._busy = !!running;
        document.querySelectorAll('#rs-btn-install, #rs-btn-start, #rs-btn-stop, #rs-btn-restart, #rs-btn-open, #rs-copy-btn')
            .forEach((btn) => {
                if (!btn) return;
                if (running) {
                    btn.dataset.wasDisabled = btn.disabled ? '1' : '0';
                    btn.disabled = true;
                } else if (btn.dataset.wasDisabled === '0') {
                    btn.disabled = false;
                }
            });
        this.applyButtonState();
    },

    applyButtonState() {
        const admin = !!window.__LOC_ADMIN;
        const s = this._status || {};
        const needsElev = admin ? '' : 'disabled title="Needs elevation"';

        const installBtn = document.getElementById('rs-btn-install');
        const canInstall = admin && s.InstallerUrlConfigured && !s.Installed;
        if (installBtn) {
            installBtn.disabled = this._busy || !canInstall;
            installBtn.title = !admin ? 'Needs elevation' : (!s.InstallerUrlConfigured ? 'Set rustDeskInstallerUrl in settings.json' : (s.Installed ? 'Already installed' : ''));
        }

        ['rs-btn-start', 'rs-btn-stop', 'rs-btn-restart'].forEach((id) => {
            const btn = document.getElementById(id);
            if (btn && !admin) btn.setAttribute('disabled', 'disabled');
            else if (btn && admin && !this._busy) btn.removeAttribute('disabled');
        });

        const openBtn = document.getElementById('rs-btn-open');
        if (openBtn) openBtn.disabled = this._busy || !s.Installed;

        const copyBtn = document.getElementById('rs-copy-btn');
        if (copyBtn) copyBtn.disabled = this._busy || !s.Id;

        const adminNote = document.getElementById('rs-admin-note');
        if (adminNote) {
            if (!admin) {
                adminNote.textContent = 'Needs elevation — relaunch start.bat as Administrator for install and service controls.';
                adminNote.classList.remove('hidden');
            } else {
                adminNote.classList.add('hidden');
            }
        }

        const hint = document.getElementById('rs-install-hint');
        if (hint) {
            if (!s.InstallerUrlConfigured) {
                hint.textContent = 'Install is disabled until rustDeskInstallerUrl is set in settings.json.';
                hint.classList.remove('hidden');
            } else if (s.Installed) {
                hint.textContent = 'RustDesk is already installed on this machine.';
                hint.classList.remove('hidden');
            } else {
                hint.classList.add('hidden');
            }
        }

        void needsElev;
    },

    paintStatus(s) {
        this._status = s || {};
        const installedEl = document.getElementById('rs-installed');
        const versionEl = document.getElementById('rs-version');
        const runningEl = document.getElementById('rs-running');
        const processEl = document.getElementById('rs-process-meta');
        const serviceEl = document.getElementById('rs-service');
        const serviceMeta = document.getElementById('rs-service-meta');
        const idEl = document.getElementById('rs-id');
        const pathEl = document.getElementById('rs-path');
        const resultEl = document.getElementById('rs-result');

        if (installedEl) {
            installedEl.innerHTML = s.Installed
                ? '<span class="badge badge-ok">Yes</span>'
                : '<span class="badge badge-muted">No</span>';
        }
        if (versionEl) versionEl.textContent = s.Version ? `Version ${s.Version}` : 'Version not detected';
        if (runningEl) {
            runningEl.innerHTML = s.ProcessRunning
                ? '<span class="badge badge-ok">Running</span>'
                : '<span class="badge badge-muted">Stopped</span>';
        }
        if (processEl) processEl.textContent = s.ProcessRunning ? 'rustdesk.exe is active' : 'No rustdesk process';

        if (serviceEl) {
            if (!s.ServiceFound) {
                serviceEl.innerHTML = '<span class="badge badge-muted">Not found</span>';
            } else {
                const ok = s.ServiceStatus === 'Running';
                serviceEl.innerHTML = `<span class="badge ${ok ? 'badge-ok' : 'badge-muted'}">${s.ServiceStatus || '—'}</span>`;
            }
        }
        if (serviceMeta) {
            serviceMeta.textContent = s.ServiceFound
                ? `${s.ServiceName || 'RustDesk'} · ${s.ServiceStartType || '—'}`
                : 'No Windows service matching RustDesk';
        }

        if (idEl) idEl.textContent = s.Id || '—';
        if (pathEl) pathEl.textContent = s.InstallPath ? `Install path: ${s.InstallPath}` : 'Install path —';

        if (resultEl && s.Note) resultEl.textContent = s.Note;
        this.applyButtonState();
    },

    async refresh() {
        const resultEl = document.getElementById('rs-result');
        if (resultEl) resultEl.textContent = 'Loading status…';
        const res = await API.diagnostic('remotesupport', 'GetRustDeskStatus', '', 20000);
        if (!res.Success) {
            if (resultEl) resultEl.textContent = res.Message || 'Failed to load status';
            LiveConsole.log(res.Message || 'GetRustDeskStatus failed', 'ERROR');
            return;
        }
        this.paintStatus(res.Data || {});
        LiveConsole.log(res.Message, 'SUCCESS');
        if (typeof lucide !== 'undefined') lucide.createIcons();
    },

    async copyId() {
        if (this._busy) return;
        this.setBusy(true);
        try {
            const res = await API.action('remotesupport', 'CopyRustDeskId', {}, 15000);
            const id = res.Data && res.Data.Id;
            if (!res.Success || !id) {
                LiveConsole.log(res.Message || 'No ID available', 'ERROR');
                alert(res.Message || 'Could not read RustDesk ID');
                return;
            }
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(String(id));
            } else {
                const ta = document.createElement('textarea');
                ta.value = String(id);
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
            }
            LiveConsole.log(`Copied RustDesk ID ${id}`, 'SUCCESS');
            const resultEl = document.getElementById('rs-result');
            if (resultEl) resultEl.textContent = `ID copied to clipboard: ${id}`;
        } finally {
            this.setBusy(false);
        }
    },

    async install() {
        if (this._busy) return;
        if (!this.adminGate(true)) return;
        if (!this._status || !this._status.InstallerUrlConfigured) {
            alert('Set rustDeskInstallerUrl in settings.json before installing.');
            return;
        }
        if (!confirm('Download and silently install RustDesk using settings from settings.json?')) return;

        this.setBusy(true);
        const resultEl = document.getElementById('rs-result');
        if (resultEl) resultEl.textContent = 'Downloading and installing RustDesk… this may take a minute.';
        LiveConsole.log('InstallRustDesk started', 'INFO');
        try {
            const res = await API.action('remotesupport', 'InstallRustDesk', {}, 300000);
            if (res.Success) {
                LiveConsole.log(res.Message, 'SUCCESS');
                if (res.Data) this.paintStatus(res.Data);
                else await this.refresh();
            } else {
                LiveConsole.log(res.Message, 'ERROR');
                if (resultEl) resultEl.textContent = res.Message || 'Install failed';
            }
        } finally {
            this.setBusy(false);
        }
    },

    async action(name) {
        if (this._busy) return;
        const adminActions = ['StartRustDesk', 'StopRustDesk', 'RestartRustDeskService'];
        if (adminActions.some((a) => a.toLowerCase() === name.toLowerCase()) && !this.adminGate(true)) return;

        this.setBusy(true);
        const resultEl = document.getElementById('rs-result');
        if (resultEl) resultEl.textContent = `Running ${name}…`;
        LiveConsole.log(`RemoteSupport / ${name}`, 'INFO');
        try {
            const timeout = /^InstallRustDesk$/i.test(name) ? 300000 : 60000;
            const res = await API.action('remotesupport', name, {}, timeout);
            if (resultEl) resultEl.textContent = res.Message || (res.Success ? 'Done' : 'Failed');
            LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
            if (res.Data && (res.Data.Installed !== undefined || res.Data.ProcessRunning !== undefined)) {
                this.paintStatus(res.Data);
            } else if (/^(Start|Stop|Restart)/i.test(name)) {
                await this.refresh();
            }
        } finally {
            this.setBusy(false);
        }
    }
};

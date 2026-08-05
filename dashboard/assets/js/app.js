document.addEventListener('DOMContentLoaded', async () => {
    lucide.createIcons();

    const PROFILES = [
        { id: 'helpdesk', label: 'Helpdesk' },
        { id: 'desktop_support', label: 'Desktop Support' },
        { id: 'systems_administrator', label: 'Systems Administrator' },
        { id: 'network_administrator', label: 'Network Administrator' },
        { id: 'developer', label: 'Developer' },
        { id: 'power_user', label: 'Power User' },
    ];

    function getActiveProfile() {
        const v = localStorage.getItem('loc_profile');
        if (v && PROFILES.some((p) => p.id === v)) return v;
        return 'power_user';
    }

    function setActiveProfile(id) {
        localStorage.setItem('loc_profile', id);
    }

    function labelForProfile(id) {
        return (PROFILES.find((p) => p.id === id) || PROFILES[PROFILES.length - 1]).label;
    }

    function ensureProfileUi() {
        const adminBadge = document.getElementById('admin-badge');
        const headerRight = adminBadge ? adminBadge.parentElement : null;
        if (!headerRight) return;

        // Dropdown
        let sel = document.getElementById('profile-select');
        if (!sel) {
            sel = document.createElement('select');
            sel.id = 'profile-select';
            sel.className = 'px-2 py-1 rounded-lg bg-slate-900/60 border border-slate-800 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50';
            sel.onchange = () => {
                setActiveProfile(sel.value);
                // Trigger a full refresh because sidebar + initial view both depend on the filtered module list.
                refreshSidebarWithActiveProfile();
            };

            const wrap = document.createElement('div');
            wrap.className = 'flex items-center gap-2';
            wrap.appendChild(sel);
            headerRight.appendChild(wrap);
        }

        // Badge
        let badge = document.getElementById('profile-badge');
        if (!badge) {
            badge = document.createElement('span');
            badge.id = 'profile-badge';
            badge.className = 'badge badge-muted';
            badge.innerText = 'PROFILE: —';
            headerRight.appendChild(badge);
        }

        // Populate dropdown (once)
        if (sel.options.length === 0) {
            PROFILES.forEach((p) => {
                const opt = document.createElement('option');
                opt.value = p.id;
                opt.text = p.label;
                sel.appendChild(opt);
            });
        }

        const active = getActiveProfile();
        sel.value = active;
        badge.innerText = `PROFILE: ${labelForProfile(active)}`;
    }

    let allModules = [];
    async function refreshSidebarWithActiveProfile() {
        const active = getActiveProfile();
        const filtered = (allModules || []).filter((m) => {
            if (m.hidden) return false;
            if (!m.profiles || !Array.isArray(m.profiles) || m.profiles.length === 0) return true;
            return m.profiles.includes(active);
        });
        renderSidebar(filtered);
        if (filtered.length > 0) {
            await Router.loadModuleView(filtered[0].id);
        } else {
            const viewport = document.getElementById('page-content');
            viewport.innerHTML = `<div class="p-6 text-slate-400">No modules available for this profile.</div>`;
        }
    }

    const health = await API.request('health');
    if (health.Success) {
        document.getElementById('app-version').innerText = `v${health.Data.Version}`;
        document.getElementById('host-name').innerText = (health.Data.Windows || 'LOCAL').split('(')[0].trim() || 'LOCAL';
        window.__LOC_ADMIN = !!health.Data.Admin;
        const badge = document.getElementById('admin-badge');
        if (window.__LOC_ADMIN) {
            badge.className = 'badge badge-ok';
            badge.innerText = 'ELEVATED';
        } else {
            badge.className = 'badge badge-warn';
            badge.innerText = 'STANDARD USER';
        }
        document.getElementById('engine-status').innerText = health.Data.Status || 'ONLINE';
    }

    const response = await API.request('modules');
    if (response.Success) {
        const mods = Array.isArray(response.Data) ? response.Data : [];
        Router.setModules(mods);
        allModules = mods;
        ensureProfileUi();
        await refreshSidebarWithActiveProfile();
    }

    // Telemetry strip refresh
    refreshTelemetry();
    setInterval(refreshTelemetry, 10000);

    checkForUpdates();
});

async function checkForUpdates() {
    const res = await API.request('updates/check');
    if (!res.Success || !res.Data || !res.Data.UpdateAvailable) return;
    const banner = document.getElementById('update-banner');
    const text = document.getElementById('update-banner-text');
    if (!banner || !text) return;
    text.textContent = `Update available: v${res.Data.LatestVersion} (you have v${res.Data.CurrentVersion}). ${res.Data.Notes || ''}`.trim();
    banner.classList.remove('hidden');
    LiveConsole.log(`Update available: ${res.Data.LatestVersion}`, 'WARN', res.Data);
    window.__LOC_UPDATE = res.Data;
}

function dismissUpdateBanner() {
    const banner = document.getElementById('update-banner');
    if (banner) banner.classList.add('hidden');
}

async function applyUpdate() {
    if (!confirm('Download and apply the update? The server should be restarted afterward.')) return;
    LiveConsole.log('Applying update...', 'INFO');
    const res = await API.request('updates/apply', 'POST', { Force: false });
    if (res.Success) {
        LiveConsole.log(res.Message, 'SUCCESS', res.Data);
        dismissUpdateBanner();
        alert(res.Message + '\n\nStop and re-run start.ps1 to load the new build.');
    } else {
        LiveConsole.log(res.Message || 'Update failed', 'ERROR', res.Data);
        alert(res.Message || 'Update failed');
    }
}

async function shutdownConsole() {
    if (!confirm('Shut down LocalOpsConsole? The server and launcher window will close.')) return;
    const btn = document.getElementById('btn-shutdown');
    const engineEl = document.getElementById('engine-status');
    if (btn) btn.disabled = true;
    if (engineEl) engineEl.innerText = 'SHUTTING DOWN…';
    LiveConsole.log('Shutting down server…', 'WARN');
    try {
        await API.request('shutdown', 'POST', {}, 5000);
    } catch (e) { /* expected once listener stops */ }
    if (engineEl) {
        engineEl.innerText = 'OFFLINE';
        engineEl.classList.add('text-rose-400');
    }
    LiveConsole.log('Server stopped. You can close this tab.', 'INFO');
}

function renderSidebar(modules) {
    const nav = document.getElementById('sidebar-nav');
    nav.innerHTML = '';

    // Domain mapping (frontend-first; long-term can be moved into module.json metadata).
    function domainForModule(mod) {
        const id = (mod && mod.id ? String(mod.id).toLowerCase() : '');
        if (['system', 'services', 'tools', 'updates', 'startup', 'power', 'users', 'audio', 'configuration'].includes(id)) return 'System';
        if (['graphics', 'devices'].includes(id)) return 'Hardware';
        if (['storage', 'printers', 'syncme'].includes(id)) return 'Storage';
        if (['network', 'vpn', 'internetslow'].includes(id)) return 'Networking';
        if (['remote', 'remotesupport', 'fleet'].includes(id)) return 'Enterprise';
        if (['security', 'eventlog'].includes(id)) return 'Security';
        return 'Developer';
    }

    const domainOrder = ['System', 'Networking', 'Storage', 'Enterprise', 'Security', 'Hardware', 'Developer'];
    const grouped = {};
    (modules || []).forEach((mod) => {
        const d = domainForModule(mod);
        if (!grouped[d]) grouped[d] = [];
        grouped[d].push(mod);
    });

    domainOrder.forEach((domain) => {
        const items = grouped[domain];
        if (!items || !items.length) return;

        const section = document.createElement('div');
        section.className = 'mb-4';

        // Header should NOT be a button, otherwise Router active highlighting would interfere.
        const header = document.createElement('div');
        header.className = 'px-3 py-2 text-[11px] font-semibold text-slate-500 uppercase tracking-wider cursor-pointer select-none flex items-center justify-between';
        header.innerText = `${domain}`;

        const badge = document.createElement('span');
        badge.className = 'badge badge-muted';
        badge.innerText = items.length;
        header.appendChild(badge);

        const body = document.createElement('div');
        body.className = 'space-y-1';
        body.style.display = '';

        // Default expanded. Toggled via header click (accordion behavior).
        header.onclick = () => {
            const currentlyHidden = body.style.display === 'none';
            body.style.display = currentlyHidden ? '' : 'none';
        };

        items.forEach((mod) => {
            const item = document.createElement('button');
            item.dataset.module = mod.id;
            item.className = 'w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-xs font-semibold text-slate-400 hover:text-slate-100 hover:bg-slate-800/60 transition text-left';
            item.onclick = () => Router.loadModuleView(mod.id);
            item.innerHTML = `
                <i data-lucide="${mod.icon || 'box'}" class="w-4 h-4 text-slate-400"></i>
                <span>${mod.name}</span>
            `;
            body.appendChild(item);
        });

        section.appendChild(header);
        section.appendChild(body);
        nav.appendChild(section);
    });

    lucide.createIcons();
}

let telemetryFailCount = 0;

function setTelemetryWarn(el, pct) {
    if (!el) return;
    const n = Number(pct);
    if (!isNaN(n) && n >= 90) {
        el.classList.add('text-rose-400');
        el.classList.remove('text-cyan-400', 'text-emerald-400', 'text-amber-400');
    } else {
        el.classList.remove('text-rose-400');
    }
}

function shortGpuName(name) {
    if (!name) return '--';
    const s = String(name).replace(/\s+/g, ' ').trim();
    if (s.length <= 18) return s;
    return s.slice(0, 16) + '…';
}

async function refreshTelemetry() {
    const res = await API.request('telemetry', 'GET', null, 8000, { silent: true });
    const cpuEl = document.getElementById('telemetry-cpu');
    const memEl = document.getElementById('telemetry-mem');
    const diskEl = document.getElementById('telemetry-disk');
    const netEl = document.getElementById('telemetry-net');
    const gpuEl = document.getElementById('telemetry-gpu');
    const batEl = document.getElementById('telemetry-bat');
    const batWrap = document.getElementById('telemetry-bat-wrap');
    const engineEl = document.getElementById('engine-status');
    const hostEl = document.getElementById('host-name');

    if (!res.Success || !res.Data) {
        telemetryFailCount += 1;
        if (cpuEl) cpuEl.innerText = '--%';
        if (memEl) memEl.innerText = '--%';
        if (diskEl) diskEl.innerText = '--%';
        if (netEl) netEl.innerText = '--';
        if (gpuEl) gpuEl.innerText = '--';
        if (engineEl && telemetryFailCount >= 2) {
            engineEl.innerText = 'OFFLINE';
            engineEl.classList.add('text-rose-400');
        }
        return;
    }

    telemetryFailCount = 0;
    if (engineEl) {
        engineEl.innerText = 'ONLINE';
        engineEl.classList.remove('text-rose-400');
    }

    const d = res.Data;
    if (cpuEl && d.Cpu) {
        cpuEl.innerText = `${d.Cpu.UsagePct ?? '--'}%`;
        setTelemetryWarn(cpuEl, d.Cpu.UsagePct);
    }
    if (memEl && d.Memory) {
        memEl.innerText = `${d.Memory.UsedPct ?? '--'}%`;
        setTelemetryWarn(memEl, d.Memory.UsedPct);
    }
    if (diskEl) {
        if (d.Disk) {
            diskEl.innerText = `${d.Disk.UsedPct ?? '--'}%`;
            setTelemetryWarn(diskEl, d.Disk.UsedPct);
            diskEl.title = d.Disk.FreeGB != null ? `${d.Disk.FreeGB} GB free on ${d.Disk.Letter}` : '';
        } else {
            diskEl.innerText = '--%';
        }
    }
    if (netEl) {
        if (d.Network && d.Network.Connected) {
            const up = Number(d.Network.SendMbps);
            const down = Number(d.Network.RecvMbps);
            const rates = (!isNaN(up) || !isNaN(down))
                ? ` ↑${(up || 0).toFixed(1)} ↓${(down || 0).toFixed(1)}`
                : '';
            const v4 = d.Network.IPv4 || '';
            const v6s = d.Network.IPv6 || '';
            let label = v4 || v6s || 'UP';
            if (v4 && v6s) label = `${v4} · ${v6s}`;
            netEl.innerText = `${label}${rates}`;
            const tipParts = [];
            if (d.Network.Adapter) tipParts.push(d.Network.Adapter);
            if (d.Network.IPv6Full) tipParts.push(`IPv6 full: ${d.Network.IPv6Full}`);
            netEl.title = tipParts.join(' | ');
            netEl.classList.remove('text-rose-400');
        } else if (d.Network && d.Network.Connected === false) {
            netEl.innerText = 'DOWN';
            netEl.classList.add('text-rose-400');
        } else {
            netEl.innerText = '--';
        }
    }
    const vpnWrap = document.getElementById('telemetry-vpn-wrap');
    const vpnEl = document.getElementById('telemetry-vpn');
    if (vpnWrap && vpnEl) {
        if (d.Vpn && d.Vpn.Connected) {
            vpnWrap.classList.remove('hidden');
            const name = String(d.Vpn.Name || 'VPN');
            vpnEl.innerText = name.length > 14 ? name.slice(0, 12) + '…' : name;
            vpnEl.title = [d.Vpn.Name, d.Vpn.TunnelType, d.Vpn.ServerAddress].filter(Boolean).join(' · ');
        } else {
            vpnWrap.classList.add('hidden');
        }
    }
    if (gpuEl) {
        gpuEl.innerText = d.Gpu ? shortGpuName(d.Gpu.Name) : '--';
        gpuEl.title = d.Gpu ? `${d.Gpu.Name}${d.Gpu.DriverVersion ? ' · ' + d.Gpu.DriverVersion : ''}` : '';
    }
    if (batWrap && batEl) {
        if (d.Battery && d.Battery.ChargePct != null) {
            batWrap.classList.remove('hidden');
            batEl.innerText = `${d.Battery.ChargePct}%`;
            setTelemetryWarn(batEl, 100 - Number(d.Battery.ChargePct) >= 90 ? 95 : d.Battery.ChargePct < 15 ? 95 : 0);
            if (d.Battery.ChargePct < 15) batEl.classList.add('text-rose-400');
        } else {
            batWrap.classList.add('hidden');
        }
    }
    if (hostEl && d.Host && d.Host.ComputerName) {
        hostEl.innerText = d.Host.ComputerName;
    }

    if (typeof SystemView !== 'undefined' && SystemView.onTelemetry) {
        SystemView.onTelemetry(d);
    }
}

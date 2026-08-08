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
            const profiles = API.asArray(m.profiles);
            if (!profiles.length) return true;
            return profiles.includes(active);
        });
        renderSidebar(filtered);
        const prefer = filtered.find((m) => String(m.id).toLowerCase() === 'overview')
            || filtered[0];
        if (prefer) {
            await Router.loadModuleView(prefer.id);
        } else {
            const viewport = document.getElementById('page-content');
            viewport.innerHTML = `<div class="p-6 text-slate-400">No modules available for this profile.</div>`;
        }
    }

    const health = await API.request('health');
    if (typeof LocSplash !== 'undefined') LocSplash.markReady(!!health.Success);
    if (health.Success) {
        API.setOffline(false);
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
    } else {
        API.setOffline(true);
        const engineEl = document.getElementById('engine-status');
        if (engineEl) {
            engineEl.innerText = 'OFFLINE';
            engineEl.classList.add('text-rose-400');
        }
    }

    const response = await API.request('modules');
    if (response.Success) {
        const mods = API.asArray(response.Data).map((m) => ({
            ...m,
            profiles: API.asArray(m.profiles),
            depends: API.asArray(m.depends),
            diagnostics: API.asArray(m.diagnostics),
            actions: API.asArray(m.actions),
            requiresAdmin: API.asArray(m.requiresAdmin),
            capabilities: API.asArray(m.capabilities)
        }));
        Router.setModules(mods);
        allModules = mods;
        ensureProfileUi();
        await refreshSidebarWithActiveProfile();
    }

    // Telemetry strip refresh
    refreshTelemetry();
    setInterval(refreshTelemetry, 10000);

    checkForUpdates();
    ensureAlertsBell();
    refreshAlertsBellCount();
    setInterval(refreshAlertsBellCount, 15000);
});

let __locAlertUnreadPrev = null;
let __locAlertToastTimer = null;

function isLocFleetAlert(a) {
    if (!a) return false;
    const cat = String(a.Category || a.category || '').toLowerCase();
    const src = String(a.Source || a.source || '').toLowerCase();
    const title = String(a.Title || a.title || '');
    return cat === 'fleet' || src === 'fleet' || /^fleet[\s:]/i.test(title);
}

function locFleetPcFromAlert(a) {
    if (!a) return '';
    if (a.ComputerName || a.computerName) return String(a.ComputerName || a.computerName);
    const title = String(a.Title || a.title || '');
    const m = title.match(/^Fleet\s+[^:]+:\s*(.+)$/i);
    return m ? m[1].trim() : '';
}

function locFleetSevClass(sev) {
    const s = String(sev || '').toLowerCase();
    if (s === 'critical') return 'sev-critical';
    if (s === 'warning') return 'sev-warning';
    return 'sev-info';
}

function ensureAlertsBell() {
    if (document.getElementById('btn-alerts')) return;
    const adminBadge = document.getElementById('admin-badge');
    const headerRight = adminBadge ? adminBadge.parentElement : null;
    if (!headerRight) return;

    const wrap = document.createElement('div');
    wrap.className = 'relative';
    wrap.id = 'alerts-bell-wrap';
    wrap.innerHTML = `
        <button type="button" id="btn-alerts" class="action-btn slate text-[11px] px-2 py-1 flex items-center gap-1.5" title="Notifications">
            <i data-lucide="bell" class="w-3.5 h-3.5"></i>
            <span>Alerts</span>
        </button>
        <span id="alerts-bell-badge" class="hidden absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-500 text-white text-[10px] font-bold flex items-center justify-center">0</span>
        <div id="alerts-bell-drop" class="hidden absolute right-0 top-9 w-80 max-h-96 overflow-y-auto rounded-xl border border-slate-700 bg-slate-900 shadow-xl z-50 p-2 space-y-1"></div>
    `;
    headerRight.insertBefore(wrap, adminBadge);
    document.getElementById('btn-alerts').onclick = (e) => {
        e.stopPropagation();
        const drop = document.getElementById('alerts-bell-drop');
        if (!drop) return;
        const open = !drop.classList.contains('hidden');
        if (open) {
            drop.classList.add('hidden');
        } else {
            drop.classList.remove('hidden');
            refreshAlertsBellDropdown();
        }
    };
    document.addEventListener('click', () => {
        const drop = document.getElementById('alerts-bell-drop');
        if (drop) drop.classList.add('hidden');
    });
    if (typeof lucide !== 'undefined' && lucide.createIcons) lucide.createIcons();
}

async function refreshAlertsBellDropdown() {
    const drop = document.getElementById('alerts-bell-drop');
    if (!drop) return;
    const res = await API.request('alerts?unread=1', 'GET', null, 8000, { silent: true });
    const items = (res.Success && res.Data) ? API.asArray(res.Data.Items || res.Data).slice(0, 8) : [];
    const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    if (!items.length) {
        drop.innerHTML = `<p class="text-xs text-slate-500 p-2">No unread alerts</p>
            <button type="button" class="action-btn cyan w-full text-[11px]" onclick="Router.loadModuleView('alerts')">Open Notification Center</button>`;
        return;
    }
    drop.innerHTML = items.map((a) => {
        const color = String(a.Severity).toLowerCase() === 'critical' ? 'text-rose-400' :
            String(a.Severity).toLowerCase() === 'warning' ? 'text-amber-400' : 'text-sky-400';
        const fleet = isLocFleetAlert(a);
        const pc = locFleetPcFromAlert(a);
        const fleetBits = fleet
            ? `<span class="alert-chip-fleet">Fleet</span>${pc ? ` <span class="alert-chip-fleet alert-chip-fleet-pc">${esc(pc)}</span>` : ''}`
            : '';
        return `<button type="button" class="w-full text-left p-2 rounded-lg hover:bg-slate-800/80 ${fleet ? 'alert-bell-fleet' : ''}" onclick="Router.loadModuleView('alerts')">
            <div class="flex items-center gap-1.5 flex-wrap mb-0.5">${fleetBits}</div>
            <div class="text-xs font-semibold ${color}">${esc(a.Severity)} · ${esc(a.Title)}</div>
            <div class="text-[11px] text-slate-500 truncate">${esc(a.Message || '')}</div>
        </button>`;
    }).join('') + `<button type="button" class="action-btn cyan w-full text-[11px] mt-1" onclick="Router.loadModuleView('alerts')">Open Notification Center</button>`;
}

function refreshAlertsBell(count, latestTitle) {
    const badge = document.getElementById('alerts-bell-badge');
    const btn = document.getElementById('btn-alerts');
    if (!badge) return;
    const n = Number(count) || 0;
    if (n > 0) {
        badge.textContent = n > 99 ? '99+' : String(n);
        badge.classList.remove('hidden');
        badge.classList.add('has-unread');
        if (btn) btn.classList.add('has-unread');
    } else {
        badge.classList.add('hidden');
        badge.classList.remove('has-unread');
        if (btn) btn.classList.remove('has-unread');
    }

    if (__locAlertUnreadPrev != null && n > __locAlertUnreadPrev) {
        const delta = n - __locAlertUnreadPrev;
        const fleetish = !!(latestTitle && /^Fleet[\s:]/i.test(latestTitle));
        const label = latestTitle
            ? (fleetish ? `Fleet · ${latestTitle}` : `New alert: ${latestTitle}`)
            : (delta === 1 ? 'New alert in inbox' : `${delta} new alerts in inbox`);
        showAlertToast(label, fleetish);
    }
    __locAlertUnreadPrev = n;
}

function showAlertToast(message, isFleet) {
    const banner = document.getElementById('alert-toast');
    const text = document.getElementById('alert-toast-text');
    if (!banner || !text) return;
    text.textContent = message || 'New alert';
    banner.classList.toggle('is-fleet', !!isFleet);
    banner.classList.remove('hidden');
    if (__locAlertToastTimer) clearTimeout(__locAlertToastTimer);
    __locAlertToastTimer = setTimeout(() => dismissAlertToast(), 12000);
}

function dismissAlertToast() {
    const banner = document.getElementById('alert-toast');
    if (banner) {
        banner.classList.add('hidden');
        banner.classList.remove('is-fleet');
    }
    if (__locAlertToastTimer) {
        clearTimeout(__locAlertToastTimer);
        __locAlertToastTimer = null;
    }
}

function openAlertToastTarget() {
    dismissAlertToast();
    if (typeof Router !== 'undefined' && Router.loadModuleView) Router.loadModuleView('alerts');
}

async function refreshAlertsBellCount() {
    const res = await API.request('alerts', 'GET', null, 8000, { silent: true });
    if (!res.Success) return;
    let unread = 0;
    let latestTitle = '';
    if (res.Data && (res.Data.Unread != null || res.Data.unread != null)) {
        unread = res.Data.Unread != null ? res.Data.Unread : res.Data.unread;
        const items = API.asArray(res.Data.Items || res.Data.items);
        const firstUnread = items.find((a) => !(a.Acknowledged || a.acknowledged));
        if (firstUnread) latestTitle = firstUnread.Title || firstUnread.title || '';
    } else {
        const alerts = API.asArray(res.Data);
        const unacked = alerts.filter((a) => !(a.Acknowledged || a.acknowledged));
        unread = unacked.length;
        if (unacked[0]) latestTitle = unacked[0].Title || unacked[0].title || '';
    }
    refreshAlertsBell(unread, latestTitle);
}

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
    if (!confirm('Shut down LocalOpsConsole? The server will stop. Use start.bat (or Restart) to bring it back.')) return;
    const btn = document.getElementById('btn-shutdown');
    const btnR = document.getElementById('btn-restart');
    const engineEl = document.getElementById('engine-status');
    if (btn) btn.disabled = true;
    if (btnR) btnR.disabled = true;
    if (engineEl) {
        engineEl.innerText = 'SHUTTING DOWN…';
        engineEl.classList.add('text-rose-400');
    }
    LiveConsole.log('Shutting down server…', 'WARN');
    API.setOffline(true);
    await API.request('shutdown', 'POST', {}, 5000, { silent: true, expectDisconnect: true });
    if (engineEl) engineEl.innerText = 'OFFLINE';
    LiveConsole.log('Server stopped. You can close this tab.', 'INFO');
}

async function restartConsole() {
    if (!confirm('Restart LocalOpsConsole? The UI will reconnect when the server is back.')) return;
    const btn = document.getElementById('btn-shutdown');
    const btnR = document.getElementById('btn-restart');
    const engineEl = document.getElementById('engine-status');
    if (btn) btn.disabled = true;
    if (btnR) btnR.disabled = true;
    if (engineEl) {
        engineEl.innerText = 'RESTARTING…';
        engineEl.classList.remove('text-rose-400');
    }
    LiveConsole.log('Restarting server…', 'WARN');
    API.setOffline(true);

    const res = await API.request('restart', 'POST', {}, 12000, { silent: true, expectDisconnect: true });
    // Listener often drops mid-response after schedule — treat network errors as scheduled OK
    const scheduleOk = !!(res && (res.Success || res.NetworkError || API.isNetworkFailure(res.Message)));
    if (!scheduleOk) {
        API.setOffline(false);
        LiveConsole.log(res.Message || 'Restart request failed', 'ERROR');
        if (engineEl) {
            engineEl.innerText = 'ONLINE';
            engineEl.classList.remove('text-rose-400');
        }
        if (btn) btn.disabled = false;
        if (btnR) btnR.disabled = false;
        return;
    }

    LiveConsole.log('Waiting for server to come back…', 'INFO');
    const started = Date.now();
    const maxMs = 120000;
    while (Date.now() - started < maxMs) {
        await new Promise(r => setTimeout(r, 1500));
        if (engineEl) engineEl.innerText = 'RECONNECTING…';
        const h = await API.request('health', 'GET', null, 5000, { silent: true, expectDisconnect: true });
        if (h && h.Success) {
            API.setOffline(false);
            LiveConsole.log('Server is back — reloading…', 'SUCCESS');
            location.reload();
            return;
        }
    }

    if (engineEl) {
        engineEl.innerText = 'OFFLINE';
        engineEl.classList.add('text-rose-400');
    }
    LiveConsole.log('Server did not return. Run start.bat as Administrator to bring it back.', 'ERROR');
    if (btn) btn.disabled = false;
    if (btnR) btnR.disabled = false;
}

function renderSidebar(modules) {
    const nav = document.getElementById('sidebar-nav');
    nav.innerHTML = '';

    // Platform navigation sections (enterprise ops layout).
    function sectionForModule(mod) {
        const id = (mod && mod.id ? String(mod.id).toLowerCase() : '');
        if (id === 'overview') return 'Overview';
        if (['incidents'].includes(id)) return 'Incidents';
        if (['healthcenter'].includes(id)) return 'Health';
        if (['securitycenter', 'security', 'securitybaseline', 'eventlog', 'threatoperations'].includes(id)) return 'Security';
        if (['alerts', 'timeline'].includes(id)) return 'Monitoring';
        if (['automation'].includes(id)) return 'Automation';
        if (['settings', 'locsettings'].includes(id)) return 'Settings';
        if (['reports'].includes(id)) return 'Reports';
        if (['system'].includes(id)) return 'Performance';
        if (['devices', 'users', 'graphics', 'storage', 'startup', 'power'].includes(id)) return 'Inventory';
        if (['services', 'tools', 'updates', 'configuration', 'audio', 'printers', 'syncme',
            'network', 'vpn', 'internetslow', 'remote', 'remotesupport', 'fleet', 'networkmap',
            'activedirectory', 'dns', 'dhcp', 'grouppolicy', 'hyperv', 'certificates', 'serveroperations'].includes(id)) {
            return 'Operations';
        }
        return 'Operations';
    }

    const sectionOrder = [
        'Overview', 'Operations', 'Security', 'Health', 'Performance',
        'Inventory', 'Incidents', 'Monitoring', 'Automation', 'Reports', 'Settings'
    ];
    const grouped = {};
    (modules || []).forEach((mod) => {
        const d = sectionForModule(mod);
        if (!grouped[d]) grouped[d] = [];
        grouped[d].push(mod);
    });

    sectionOrder.forEach((domain) => {
        const items = grouped[domain];
        if (!items || !items.length) return;

        const section = document.createElement('div');
        section.className = 'mb-3';

        const header = document.createElement('div');
        header.className = 'nav-section-header px-3 py-1.5 text-[10px] font-semibold text-slate-500 uppercase tracking-wider cursor-pointer select-none flex items-center justify-between';
        header.innerText = domain;

        const badge = document.createElement('span');
        badge.className = 'badge badge-muted';
        badge.innerText = items.length;
        header.appendChild(badge);

        const body = document.createElement('div');
        body.className = 'space-y-0.5';
        // All section menus start collapsed; user expands via header click.
        body.style.display = 'none';
        body.dataset.navSection = domain;

        header.onclick = () => {
            const currentlyHidden = body.style.display === 'none';
            body.style.display = currentlyHidden ? '' : 'none';
        };

        items.forEach((mod) => {
            const item = document.createElement('button');
            item.dataset.module = mod.id;
            item.className = 'w-full flex items-center gap-3 px-3 py-2 rounded-lg text-xs font-semibold text-slate-400 hover:text-slate-100 hover:bg-slate-800/60 transition text-left';
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
            API.setOffline(true);
        }
        return;
    }

    telemetryFailCount = 0;
    API.setOffline(false);
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

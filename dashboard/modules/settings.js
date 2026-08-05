const SettingsView = {
    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Settings</h2>
                        <p class="text-xs text-slate-400">Notification channels, severity filters, quiet hours, and maintenance mode.</p>
                    </div>
                    <div class="flex gap-2">
                        <button type="button" class="action-btn slate" onclick="SettingsView.refresh()">Reload</button>
                        <button type="button" class="action-btn cyan" onclick="SettingsView.save()">Save</button>
                    </div>
                </div>
                <div id="settings-meta" class="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs"></div>
                <div class="glass-panel p-4 space-y-4">
                    <h3 class="text-sm font-bold text-slate-100">Notifications</h3>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
                        <label class="block">
                            <span class="text-slate-500">Minimum severity</span>
                            <select id="set-notify-level" class="mt-1 w-full px-2 py-1.5 rounded-lg bg-slate-900 border border-slate-800 text-slate-200">
                                <option>Info</option><option>Warning</option><option>Critical</option>
                            </select>
                        </label>
                        <label class="block">
                            <span class="text-slate-500">Categories (comma or *)</span>
                            <input id="set-notify-cats" type="text" class="mt-1 w-full px-2 py-1.5 rounded-lg bg-slate-900 border border-slate-800 text-slate-200 font-mono" />
                        </label>
                    </div>
                    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs" id="set-channels"></div>
                </div>
                <div class="glass-panel p-4 space-y-3">
                    <h3 class="text-sm font-bold text-slate-100">Quiet hours</h3>
                    <label class="flex items-center gap-2 text-xs text-slate-300">
                        <input type="checkbox" id="set-qh-enabled" /> Enabled
                    </label>
                    <div class="flex gap-3 text-xs flex-wrap">
                        <label>Start <input id="set-qh-start" type="time" class="ml-1 px-2 py-1 rounded bg-slate-900 border border-slate-800" /></label>
                        <label>End <input id="set-qh-end" type="time" class="ml-1 px-2 py-1 rounded bg-slate-900 border border-slate-800" /></label>
                    </div>
                </div>
                <div class="glass-panel p-4 space-y-3">
                    <h3 class="text-sm font-bold text-slate-100">Maintenance mode</h3>
                    <label class="flex items-center gap-2 text-xs text-slate-300">
                        <input type="checkbox" id="set-maint-enabled" /> Suppress notifications during maintenance
                    </label>
                    <p class="text-[11px] text-slate-500">Duplicate suppression and escalation are handled by NotificationManager using these prefs.</p>
                </div>
                <div id="settings-status" class="text-xs text-slate-500"></div>
            </div>`;
        await this.refresh();
    },

    channelKeys: ['desktop', 'dashboard', 'email', 'teams', 'slack', 'discord', 'webhook', 'syslog'],

    async refresh() {
        const res = await API.request('settings', 'GET', null, 10000, { silent: false });
        const meta = document.getElementById('settings-meta');
        if (!res.Success || !res.Data) {
            if (meta) meta.innerHTML = `<p class="text-rose-400 col-span-full">${res.Message || 'Failed'}</p>`;
            return;
        }
        const d = res.Data;
        const ei = d.eventIntel || {};
        if (meta) {
            meta.innerHTML = [
                ['Bind', `${d.bindHost}:${d.port}`],
                ['Integrity', d.integrityMode || 'warn'],
                ['Event Intel', d.eventIntelEnabled ? 'On' : 'Off'],
                ['Fleet', d.fleetEnabled ? 'On' : 'Off']
            ].map(([l, v]) => `
                <div class="glass-panel p-3">
                    <div class="text-[11px] text-slate-500 uppercase">${l}</div>
                    <div class="text-slate-200 font-mono mt-1">${v}</div>
                </div>`).join('');
        }
        const level = document.getElementById('set-notify-level');
        if (level) level.value = ei.notifyLevel || 'Warning';
        const cats = document.getElementById('set-notify-cats');
        if (cats) cats.value = Array.isArray(ei.notifyCategories) ? ei.notifyCategories.join(', ') : '*';
        const chWrap = document.getElementById('set-channels');
        const channels = ei.channels || {};
        if (chWrap) {
            chWrap.innerHTML = this.channelKeys.map((k) => `
                <label class="flex items-center gap-2 p-2 rounded-lg bg-slate-950/50 border border-slate-800">
                    <input type="checkbox" data-channel="${k}" ${channels[k] ? 'checked' : ''} />
                    <span class="capitalize text-slate-300">${k}</span>
                </label>`).join('');
        }
        const qh = ei.quietHours || {};
        const qhEn = document.getElementById('set-qh-enabled');
        if (qhEn) qhEn.checked = !!qh.enabled;
        const qhS = document.getElementById('set-qh-start');
        const qhE = document.getElementById('set-qh-end');
        if (qhS) qhS.value = qh.start || '22:00';
        if (qhE) qhE.value = qh.end || '07:00';
        const maint = ei.maintenanceWindow || {};
        const mEn = document.getElementById('set-maint-enabled');
        if (mEn) mEn.checked = !!maint.enabled;
    },

    collect() {
        const channels = {};
        document.querySelectorAll('#set-channels [data-channel]').forEach((el) => {
            channels[el.dataset.channel] = !!el.checked;
        });
        const catsRaw = (document.getElementById('set-notify-cats') || {}).value || '*';
        const cats = catsRaw.split(',').map((s) => s.trim()).filter(Boolean);
        return {
            notifyLevel: (document.getElementById('set-notify-level') || {}).value || 'Warning',
            notifyCategories: cats.length ? cats : ['*'],
            channels,
            quietHours: {
                enabled: !!(document.getElementById('set-qh-enabled') || {}).checked,
                start: (document.getElementById('set-qh-start') || {}).value || '22:00',
                end: (document.getElementById('set-qh-end') || {}).value || '07:00'
            },
            maintenanceWindow: {
                enabled: !!(document.getElementById('set-maint-enabled') || {}).checked,
                start: null,
                end: null
            }
        };
    },

    async save() {
        const status = document.getElementById('settings-status');
        if (status) status.textContent = 'Saving…';
        const prefs = this.collect();
        const res = await API.request('settings', 'POST', { eventIntel: prefs }, 10000);
        if (status) {
            status.textContent = res.Success ? 'Saved. Notification prefs applied.' : (res.Message || 'Save failed');
            status.className = `text-xs ${res.Success ? 'text-emerald-400' : 'text-rose-400'}`;
        }
        if (res.Success) LiveConsole.log('Settings saved', 'SUCCESS');
        else LiveConsole.log(res.Message || 'Settings save failed', 'ERROR');
    }
};

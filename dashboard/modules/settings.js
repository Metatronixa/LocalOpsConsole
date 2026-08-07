const SettingsView = {
    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Settings</h2>
                        <p class="text-xs text-slate-400">Notification channels, delivery config, severity filters, quiet hours, and maintenance mode.</p>
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
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs" id="set-channels"></div>
                </div>
                <div class="glass-panel p-4 space-y-4">
                    <div class="flex items-start justify-between flex-wrap gap-2">
                        <div>
                            <h3 class="text-sm font-bold text-slate-100">Channel configuration</h3>
                            <p class="text-[11px] text-slate-500 mt-1">Enable a channel above, fill its settings here, then Save. Use Test to verify delivery.</p>
                        </div>
                    </div>
                    <div id="set-channel-config" class="space-y-4"></div>
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

    channelLabels: {
        desktop: 'Windows desktop toast',
        dashboard: 'Dashboard inbox (Notification Centre + Alerts bell)',
        email: 'Email',
        teams: 'Microsoft Teams',
        slack: 'Slack',
        discord: 'Discord',
        webhook: 'Generic webhook',
        syslog: 'Syslog'
    },

    fieldClass: 'mt-1 w-full px-2 py-1.5 rounded-lg bg-slate-900 border border-slate-800 text-slate-200 font-mono text-xs',

    cfgVal(cc, channel, key, fallback) {
        const block = (cc && cc[channel]) || {};
        const v = block[key];
        return v == null ? (fallback || '') : String(v);
    },

    renderChannelConfig(cc) {
        const wrap = document.getElementById('set-channel-config');
        if (!wrap) return;
        const fc = this.fieldClass;
        const emailPassHint = (cc && cc.email && cc.email.passwordSet)
            ? 'Password saved — leave blank to keep'
            : 'Optional SMTP password';

        wrap.innerHTML = `
            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-3">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Discord</h4>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('discord')">Test</button>
                </div>
                <label class="block text-xs">
                    <span class="text-slate-500">Webhook URL</span>
                    <input id="cfg-discord-webhookUrl" type="url" autocomplete="off" class="${fc}"
                           placeholder="https://discord.com/api/webhooks/..." value="${this.escapeAttr(this.cfgVal(cc, 'discord', 'webhookUrl'))}" />
                </label>
            </div>

            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-3">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Email (SMTP)</h4>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('email')">Test</button>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs">
                    <label class="block">
                        <span class="text-slate-500">SMTP server</span>
                        <input id="cfg-email-smtpServer" type="text" autocomplete="off" class="${fc}"
                               placeholder="smtp.example.com" value="${this.escapeAttr(this.cfgVal(cc, 'email', 'smtpServer'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">Port</span>
                        <input id="cfg-email-port" type="number" class="${fc}"
                               placeholder="587" value="${this.escapeAttr(this.cfgVal(cc, 'email', 'port', '587'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">From</span>
                        <input id="cfg-email-from" type="email" autocomplete="off" class="${fc}"
                               placeholder="loc@example.com" value="${this.escapeAttr(this.cfgVal(cc, 'email', 'from'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">To</span>
                        <input id="cfg-email-to" type="email" autocomplete="off" class="${fc}"
                               placeholder="you@example.com" value="${this.escapeAttr(this.cfgVal(cc, 'email', 'to'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">Username</span>
                        <input id="cfg-email-username" type="text" autocomplete="off" class="${fc}"
                               value="${this.escapeAttr(this.cfgVal(cc, 'email', 'username'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">${emailPassHint}</span>
                        <input id="cfg-email-password" type="password" autocomplete="new-password" class="${fc}"
                               placeholder="${(cc && cc.email && cc.email.passwordSet) ? '********' : ''}" value="" />
                    </label>
                </div>
            </div>

            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-3">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Microsoft Teams</h4>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('teams')">Test</button>
                </div>
                <label class="block text-xs">
                    <span class="text-slate-500">Incoming webhook URL</span>
                    <input id="cfg-teams-webhookUrl" type="url" autocomplete="off" class="${fc}"
                           placeholder="https://outlook.office.com/webhook/..." value="${this.escapeAttr(this.cfgVal(cc, 'teams', 'webhookUrl'))}" />
                </label>
            </div>

            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-3">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Slack</h4>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('slack')">Test</button>
                </div>
                <label class="block text-xs">
                    <span class="text-slate-500">Incoming webhook URL</span>
                    <input id="cfg-slack-webhookUrl" type="url" autocomplete="off" class="${fc}"
                           placeholder="https://hooks.slack.com/services/..." value="${this.escapeAttr(this.cfgVal(cc, 'slack', 'webhookUrl'))}" />
                </label>
            </div>

            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-3">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Generic webhook</h4>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('webhook')">Test</button>
                </div>
                <label class="block text-xs">
                    <span class="text-slate-500">POST URL</span>
                    <input id="cfg-webhook-url" type="url" autocomplete="off" class="${fc}"
                           placeholder="https://your.endpoint/hooks/loc" value="${this.escapeAttr(this.cfgVal(cc, 'webhook', 'url'))}" />
                </label>
            </div>

            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-3">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Syslog</h4>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('syslog')">Test</button>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-3 text-xs">
                    <label class="block md:col-span-1">
                        <span class="text-slate-500">Host</span>
                        <input id="cfg-syslog-host" type="text" autocomplete="off" class="${fc}"
                               placeholder="syslog.local" value="${this.escapeAttr(this.cfgVal(cc, 'syslog', 'host'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">Port</span>
                        <input id="cfg-syslog-port" type="number" class="${fc}"
                               placeholder="514" value="${this.escapeAttr(this.cfgVal(cc, 'syslog', 'port', '514'))}" />
                    </label>
                    <label class="block">
                        <span class="text-slate-500">Protocol</span>
                        <select id="cfg-syslog-protocol" class="${fc}">
                            <option value="UDP">UDP</option>
                            <option value="TCP">TCP</option>
                        </select>
                    </label>
                </div>
            </div>

            <div class="rounded-xl border border-slate-800 bg-slate-950/40 p-3 space-y-2">
                <div class="flex items-center justify-between gap-2 flex-wrap">
                    <h4 class="text-xs font-semibold text-slate-200">Local channels</h4>
                </div>
                <div class="flex flex-wrap gap-2">
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('desktop')">Test desktop toast</button>
                    <button type="button" class="action-btn slate text-[11px]" onclick="SettingsView.testChannel('dashboard')">Test dashboard inbox</button>
                </div>
            </div>
        `;

        const proto = document.getElementById('cfg-syslog-protocol');
        if (proto) {
            const cur = (this.cfgVal(cc, 'syslog', 'protocol', 'UDP') || 'UDP').toUpperCase();
            proto.value = cur === 'TCP' ? 'TCP' : 'UDP';
        }
    },

    escapeAttr(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    },

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
            chWrap.innerHTML = this.channelKeys.map((k) => {
                const label = this.channelLabels[k] || k;
                const on = channels[k] != null ? !!channels[k] : (k === 'dashboard' || k === 'desktop');
                return `
                <label class="flex items-start gap-2 p-2 rounded-lg bg-slate-950/50 border border-slate-800">
                    <input type="checkbox" class="mt-0.5 shrink-0" data-channel="${k}" ${on ? 'checked' : ''} />
                    <span class="text-slate-300 leading-snug">${label}</span>
                </label>`;
            }).join('');
        }
        this.renderChannelConfig(ei.channelConfig || {});
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

    val(id) {
        const el = document.getElementById(id);
        return el ? String(el.value || '').trim() : '';
    },

    collect() {
        const channels = {};
        document.querySelectorAll('#set-channels [data-channel]').forEach((el) => {
            channels[el.dataset.channel] = !!el.checked;
        });
        const catsRaw = (document.getElementById('set-notify-cats') || {}).value || '*';
        const cats = catsRaw.split(',').map((s) => s.trim()).filter(Boolean);
        const emailPort = parseInt(this.val('cfg-email-port'), 10);
        const syslogPort = parseInt(this.val('cfg-syslog-port'), 10);
        return {
            notifyLevel: (document.getElementById('set-notify-level') || {}).value || 'Warning',
            notifyCategories: cats.length ? cats : ['*'],
            channels,
            channelConfig: {
                discord: { webhookUrl: this.val('cfg-discord-webhookUrl') },
                email: {
                    smtpServer: this.val('cfg-email-smtpServer'),
                    port: isNaN(emailPort) ? 587 : emailPort,
                    from: this.val('cfg-email-from'),
                    to: this.val('cfg-email-to'),
                    username: this.val('cfg-email-username'),
                    password: this.val('cfg-email-password')
                },
                teams: { webhookUrl: this.val('cfg-teams-webhookUrl') },
                slack: { webhookUrl: this.val('cfg-slack-webhookUrl') },
                webhook: { url: this.val('cfg-webhook-url') },
                syslog: {
                    host: this.val('cfg-syslog-host'),
                    port: isNaN(syslogPort) ? 514 : syslogPort,
                    protocol: this.val('cfg-syslog-protocol') || 'UDP'
                }
            },
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
        if (res.Success) {
            LiveConsole.log('Settings saved', 'SUCCESS');
            await this.refresh();
        } else {
            LiveConsole.log(res.Message || 'Settings save failed', 'ERROR');
        }
    },

    async testChannel(channel) {
        const status = document.getElementById('settings-status');
        if (status) {
            status.textContent = `Saving then testing ${channel}…`;
            status.className = 'text-xs text-slate-400';
        }
        // Persist form first so Test uses the values just entered
        const prefs = this.collect();
        const saveRes = await API.request('settings', 'POST', { eventIntel: prefs }, 10000);
        if (!saveRes.Success) {
            if (status) {
                status.textContent = saveRes.Message || 'Save failed — fix config before testing';
                status.className = 'text-xs text-rose-400';
            }
            return;
        }
        const res = await API.request('settings/test-channel', 'POST', { channel }, 20000);
        if (status) {
            status.textContent = res.Success
                ? `Test ${channel}: ${res.Message || 'ok'}`
                : `Test ${channel} failed: ${res.Message || 'error'}`;
            status.className = `text-xs ${res.Success ? 'text-emerald-400' : 'text-rose-400'}`;
        }
        if (res.Success) LiveConsole.log(`Test ${channel}: ${res.Message}`, 'SUCCESS');
        else LiveConsole.log(`Test ${channel}: ${res.Message}`, 'ERROR');
        if (channel === 'dashboard' && typeof refreshAlertsBellCount === 'function') {
            refreshAlertsBellCount();
        }
    }
};

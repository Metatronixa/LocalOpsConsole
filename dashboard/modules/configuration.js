const ConfigurationView = {
    _busy: false,
    _catalog: null,

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div>
                    <h2 class="text-lg font-bold text-slate-100">Configuration</h2>
                    <p class="text-xs text-slate-400">Documented Windows settings — see current, recommended, and defaults before you change anything.</p>
                </div>
                <div id="config-status" class="result-busy"><span class="spinner"></span> Loading catalog…</div>
                <div id="config-body"></div>
            </div>
        `;
        await this.refresh();
    },

    async refresh() {
        const status = document.getElementById('config-status');
        const body = document.getElementById('config-body');
        if (status) status.innerHTML = `<div class="result-busy"><span class="spinner"></span> Loading catalog…</div>`;
        const res = await API.diagnostic('configuration', 'GetCatalog', '', 30000);
        if (!res.Success) {
            if (status) status.innerHTML = `<div class="text-rose-400 text-sm">${this.escape(res.Message || 'Failed to load catalog')}</div>`;
            if (body) body.innerHTML = '';
            LiveConsole.log(res.Message || 'GetCatalog failed', 'ERROR', res.Data);
            return;
        }
        this._catalog = res.Data;
        if (status) status.innerHTML = `<div class="text-xs text-slate-500 font-mono">${this.escape(res.Message)}</div>`;
        this.renderCategories(body);
        LiveConsole.log(res.Message, 'SUCCESS');
    },

    renderCategories(body) {
        if (!body) return;
        const cats = API.asArray(this._catalog && this._catalog.Categories);
        if (!cats.length) {
            body.innerHTML = `<p class="text-slate-500 text-sm">No categories.</p>`;
            return;
        }

        body.innerHTML = cats.map((cat) => {
            const enabled = cat.Enabled !== false;
            const settings = API.asArray(cat.Settings);
            if (!enabled) {
                return `
                    <div class="p-5 rounded-xl bg-slate-900/40 border border-slate-800 mb-4 opacity-70">
                        <div class="section-title">${this.escape(cat.Name)}</div>
                        <p class="text-xs text-slate-500">${this.escape(cat.Description || 'Coming soon')}</p>
                    </div>`;
            }
            const cards = settings.map((s) => this.cardHtml(s)).join('');
            return `
                <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 mb-4">
                    <div class="section-title">${this.escape(cat.Name)}</div>
                    <p class="text-xs text-slate-500 mb-3">${this.escape(cat.Description || '')}</p>
                    <div class="space-y-3">${cards || '<p class="text-xs text-slate-500">No settings in this category yet.</p>'}</div>
                </div>`;
        }).join('');
    },

    cardHtml(s) {
        const id = this.escape(s.Id);
        const req = [];
        if (s.RequiresExplorerRestart) req.push('Explorer restart');
        if (s.RequiresLogoff) req.push('Logoff');
        if (s.RequiresRestart) req.push('Restart');
        const reqText = req.length ? req.join(', ') : 'None';
        const riskClass = /high/i.test(s.Risk || '') ? 'text-rose-400' : (/medium/i.test(s.Risk || '') ? 'text-amber-400' : 'text-emerald-400');

        return `
            <div class="rounded-lg border border-slate-700/80 bg-slate-950/50 p-4" data-setting-id="${id}">
                <div class="flex items-start justify-between gap-3 mb-2">
                    <div>
                        <h3 class="text-sm font-semibold text-slate-100">${this.escape(s.Name)}</h3>
                        <p class="text-[11px] text-slate-500 mt-0.5">${this.escape(s.Description || '')}</p>
                    </div>
                    <span class="text-[10px] font-mono uppercase ${riskClass}">Risk: ${this.escape(s.Risk || 'Low')}</span>
                </div>
                <dl class="grid grid-cols-1 md:grid-cols-2 gap-x-4 gap-y-1 text-[11px] font-mono text-slate-400 mb-3">
                    <div><span class="text-slate-500">Current:</span> <span class="text-cyan-300">${this.escape(s.Current)}</span></div>
                    <div><span class="text-slate-500">Recommended:</span> <span class="text-emerald-300">${this.escape(s.Recommended)}</span></div>
                    <div><span class="text-slate-500">Microsoft default:</span> <span class="text-slate-300">${this.escape(s.MicrosoftDefault)}</span></div>
                    <div><span class="text-slate-500">Requires:</span> <span class="text-slate-300">${this.escape(reqText)}</span></div>
                    <div class="md:col-span-2"><span class="text-slate-500">Location:</span> <span class="text-slate-300">${this.escape(s.Path)}</span></div>
                    <div class="md:col-span-2"><span class="text-slate-500">Registry value:</span> <span class="text-slate-300">${this.escape(s.ValueName)} = ${this.escape(String(s.CurrentRaw == null ? '(not set)' : s.CurrentRaw))}</span></div>
                </dl>
                <div class="flex flex-wrap gap-2">
                    ${s.ReadOnly ? '<span class="text-[11px] text-slate-500 font-mono">Read-only</span>' : `
                    <button class="action-btn cyan" ${this._busy ? 'disabled' : ''} onclick="ConfigurationView.apply('${id}')">Apply recommended</button>
                    <button class="action-btn amber" ${this._busy ? 'disabled' : ''} onclick="ConfigurationView.restore('${id}')">Restore default</button>`}
                </div>
            </div>`;
    },

    setBusy(on, message) {
        this._busy = !!on;
        const status = document.getElementById('config-status');
        if (on && status && message) {
            status.innerHTML = `<div class="result-busy"><span class="spinner"></span> ${this.escape(message)}</div>`;
        }
        document.querySelectorAll('#config-body button').forEach((b) => { b.disabled = !!on; });
    },

    async apply(settingId) {
        if (this._busy) return;
        const setting = API.asArray(this._catalog && this._catalog.Settings).find((s) => s.Id === settingId);
        const name = setting ? setting.Name : settingId;
        const risk = setting ? setting.Risk : 'Unknown';
        const note = setting && setting.RequiresExplorerRestart ? ' File Explorer may need a restart.' : '';
        if (!confirm(`Apply recommended value for "${name}"?\nRisk: ${risk}.${note}`)) return;

        this.setBusy(true, `Applying ${name}…`);
        LiveConsole.log(`Configuration / ApplySetting ${settingId}`, 'INFO');
        try {
            const res = await API.action('configuration', 'ApplySetting', { SettingId: settingId }, 30000);
            LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
            if (res.Data && res.Data.Note) LiveConsole.log(res.Data.Note, 'WARN');
            await this.refresh();
        } finally {
            this.setBusy(false);
        }
    },

    async restore(settingId) {
        if (this._busy) return;
        const setting = API.asArray(this._catalog && this._catalog.Settings).find((s) => s.Id === settingId);
        const name = setting ? setting.Name : settingId;
        if (!confirm(`Restore Microsoft default for "${name}"?`)) return;

        this.setBusy(true, `Restoring ${name}…`);
        LiveConsole.log(`Configuration / RestoreDefault ${settingId}`, 'INFO');
        try {
            const res = await API.action('configuration', 'RestoreDefault', { SettingId: settingId }, 30000);
            LiveConsole.log(res.Message, res.Success ? 'SUCCESS' : 'ERROR', res.Data);
            if (res.Data && res.Data.Note) LiveConsole.log(res.Data.Note, 'WARN');
            await this.refresh();
        } finally {
            this.setBusy(false);
        }
    }
};

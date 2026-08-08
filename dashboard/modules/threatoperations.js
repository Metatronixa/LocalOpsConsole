/* dashboard/modules/threatoperations.js */
const ThreatOperationsView = {
    _pollTimer: null,
    _filters: { profile: '', severity: '', eventId: '', search: '' },
    _items: [],

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Threat Analysis</h2>
                        <p class="text-xs text-slate-400">Agent security telemetry, ScriptBlock inspection, and playbook hints.</p>
                    </div>
                    <div class="flex gap-2 flex-wrap">
                        <button type="button" class="action-btn slate text-[11px]" onclick="Router.loadModuleView('securitycenter')">Security Center</button>
                        <button type="button" class="action-btn cyan" onclick="ThreatOperationsView.refresh()">Refresh</button>
                    </div>
                </div>
                <div id="threat-metrics"></div>
                <div id="threat-filters"></div>
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <div id="threat-stream"></div>
                    <div id="threat-detail"></div>
                </div>
            </div>`;
        ThreatFilters.render(container.querySelector('#threat-filters'), this._filters, (f) => {
            this._filters = f;
            this.refresh(true);
        });
        ThreatDetail.render(container.querySelector('#threat-detail'), null);
        setTimeout(() => this.refresh(false), 0);
        this.startPoll();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        this._pollTimer = setInterval(() => this.refresh(true), 20000);
    },
    stopPoll() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    },

    async refresh(silent) {
        try {
            const metrics = await API.diagnostic('threatoperations', 'Get-ThreatSummaryMetrics', {});
            const mEl = document.getElementById('threat-metrics');
            if (mEl && metrics && metrics.Success) ThreatMetrics.render(mEl, metrics.Data);

            const q = { Max: 200 };
            if (this._filters.profile) q.environmentProfile = this._filters.profile;
            if (this._filters.severity) q.severity = this._filters.severity;
            if (this._filters.eventId) q.eventId = this._filters.eventId;
            if (this._filters.search) q.search = this._filters.search;
            const stream = await API.diagnostic('threatoperations', 'Get-ThreatEventStream', q);
            const sEl = document.getElementById('threat-stream');
            this._items = (stream && stream.Success && stream.Data && stream.Data.Items) ? stream.Data.Items : [];
            if (sEl) {
                ThreatStream.render(sEl, this._items, (id) => this.select(id));
            }
        } catch (err) {
            if (!silent) console.warn('ThreatOperations refresh', err);
        }
    },

    async select(id) {
        const dEl = document.getElementById('threat-detail');
        if (!dEl || !id) return;
        try {
            const res = await API.diagnostic('threatoperations', 'Get-ScriptBlockDetail', { Id: id });
            if (res && res.Success) ThreatDetail.render(dEl, res.Data);
            else ThreatDetail.render(dEl, { Label: 'Unavailable', Severity: 'INFO', KeywordHits: [], Playbooks: [] });
        } catch (err) {
            console.warn('Threat detail', err);
        }
    }
};

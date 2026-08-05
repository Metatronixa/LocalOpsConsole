const EventTimelineView = {
    _entries: [],
    _source: 'timeline',

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Event Timeline</h2>
                        <p class="text-xs text-slate-400">Unified stream of ingested events and incident timeline entries.</p>
                    </div>
                    <div class="flex flex-wrap gap-2">
                        <button type="button" onclick="EventTimelineView.setSource('timeline')" id="et-btn-timeline" class="action-btn cyan text-[11px]">Timeline</button>
                        <button type="button" onclick="EventTimelineView.setSource('events')" id="et-btn-events" class="action-btn slate text-[11px]">Raw events</button>
                        <button type="button" onclick="EventTimelineView.refresh()" class="action-btn cyan">Refresh</button>
                    </div>
                </div>

                <div id="et-status" class="text-[11px] text-slate-500 font-mono"></div>

                <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800">
                    <div id="et-list" class="space-y-2 max-h-[32rem] overflow-auto text-xs">
                        <div class="text-slate-500"><span class="spinner"></span> Loading…</div>
                    </div>
                </div>
            </div>
        `;

        await this.refresh();
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    severityBadge(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return '<span class="badge badge-err">Critical</span>';
        if (s === 'warning') return '<span class="badge badge-warn">Warning</span>';
        return `<span class="badge badge-muted">${this.escape(sev || 'Info')}</span>`;
    },

    typeIcon(type) {
        const t = String(type || '').toLowerCase();
        if (t === 'resolved') return 'text-emerald-400';
        if (t === 'detection') return 'text-rose-400';
        if (t === 'ack') return 'text-cyan-400';
        if (t === 'event') return 'text-amber-400';
        return 'text-slate-400';
    },

    setSource(src) {
        this._source = src;
        const tlBtn = document.getElementById('et-btn-timeline');
        const evBtn = document.getElementById('et-btn-events');
        if (tlBtn) tlBtn.className = `action-btn ${src === 'timeline' ? 'cyan' : 'slate'} text-[11px]`;
        if (evBtn) evBtn.className = `action-btn ${src === 'events' ? 'cyan' : 'slate'} text-[11px]`;
        this.refresh();
    },

    normalizeEntry(e) {
        return {
            timestamp: e.Timestamp || e.timestamp || e.At || e.at || '—',
            type: e.Type || e.type || 'event',
            title: e.Title || e.title || e.Message || e.message || '—',
            severity: e.Severity || e.severity || '',
            category: e.Category || e.category || '',
            source: e.Source || e.source || '',
            eventId: e.EventID || e.eventId || e.EventId || '',
            incidentId: e.IncidentId || e.incidentId || null,
            detail: e.Detail || e.detail || ''
        };
    },

    async refresh() {
        const listEl = document.getElementById('et-list');
        const statusEl = document.getElementById('et-status');
        if (listEl) listEl.innerHTML = '<div class="text-slate-500"><span class="spinner"></span> Loading…</div>';

        const endpoint = this._source === 'events' ? 'events' : 'timeline';
        const res = await API.request(endpoint);
        if (!res.Success) {
            if (listEl) listEl.innerHTML = `<div class="text-rose-300">${this.escape(res.Message)}</div>`;
            return;
        }

        this._entries = API.asArray(res.Data).map((e) => this.normalizeEntry(e));
        if (statusEl) statusEl.textContent = `${this._entries.length} entries from ${endpoint}`;

        if (!listEl) return;
        if (!this._entries.length) {
            listEl.innerHTML = '<div class="text-slate-500">No timeline entries in the selected window.</div>';
            return;
        }

        listEl.innerHTML = this._entries.map((e) => `
            <div class="pb-2 border-b border-slate-800/60 flex gap-3">
                <div class="shrink-0 w-36 text-[10px] text-slate-500 font-mono pt-0.5">${this.escape(e.timestamp)}</div>
                <div class="flex-1 min-w-0">
                    <div class="flex flex-wrap items-center gap-2 mb-0.5">
                        <span class="font-semibold ${this.typeIcon(e.type)}">${this.escape(e.type)}</span>
                        ${e.severity ? this.severityBadge(e.severity) : ''}
                        ${e.category ? `<span class="badge badge-muted">${this.escape(e.category)}</span>` : ''}
                        ${e.source ? `<span class="text-[10px] text-slate-500 font-mono">${this.escape(e.source)}${e.eventId ? ' #' + this.escape(e.eventId) : ''}</span>` : ''}
                    </div>
                    <div class="text-slate-200">${this.escape(e.title)}</div>
                    ${e.detail ? `<div class="text-slate-500 text-[11px] mt-0.5">${this.escape(e.detail)}</div>` : ''}
                    ${e.incidentId ? `<button type="button" class="action-btn cyan text-[10px] mt-1 px-1.5 py-0.5" onclick="Router.loadModuleView('incidents')">Incident</button>` : ''}
                </div>
            </div>
        `).join('');
    }
};

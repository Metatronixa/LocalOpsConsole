const AlertsView = {
    _pollTimer: null,

    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between flex-wrap gap-2">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Notification Center</h2>
                        <p class="text-xs text-slate-400">Live Event Intelligence inbox — acknowledge alerts to clear the badge.</p>
                    </div>
                    <button type="button" onclick="AlertsView.refresh()" class="action-btn cyan">Refresh</button>
                </div>
                <div id="alerts-inbox" class="space-y-2"></div>
            </div>
        `;
        await this.refresh();
        this.startPoll();
    },

    startPoll() {
        if (this._pollTimer) clearInterval(this._pollTimer);
        this._pollTimer = setInterval(() => this.refresh(true), 15000);
    },

    stopPoll() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    },

    sevClass(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return 'text-rose-400 border-rose-500/30 bg-rose-500/10';
        if (s === 'warning') return 'text-amber-400 border-amber-500/30 bg-amber-500/10';
        return 'text-sky-400 border-sky-500/30 bg-sky-500/10';
    },

    sevDot(sev) {
        const s = String(sev || '').toLowerCase();
        if (s === 'critical') return 'bg-rose-500';
        if (s === 'warning') return 'bg-amber-500';
        return 'bg-sky-500';
    },

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    relTime(ts) {
        try {
            const d = new Date(ts);
            const sec = Math.max(0, Math.floor((Date.now() - d.getTime()) / 1000));
            if (sec < 60) return sec + 's ago';
            if (sec < 3600) return Math.floor(sec / 60) + ' min ago';
            if (sec < 86400) return Math.floor(sec / 3600) + 'h ago';
            return d.toLocaleString();
        } catch { return ts || ''; }
    },

    async refresh(silent) {
        const res = await API.request('alerts', 'GET', null, 10000, { silent: !!silent });
        const box = document.getElementById('alerts-inbox');
        if (!box) return;
        if (!res.Success) {
            box.innerHTML = `<p class="text-slate-500 text-sm">${this.escape(res.Message || 'Failed to load')}</p>`;
            return;
        }
        const items = API.asArray(res.Data && res.Data.Items ? res.Data.Items : res.Data);
        if (!items.length) {
            box.innerHTML = `<p class="text-slate-500 text-sm">No alerts yet. The engine will populate this as events match rules.</p>`;
            return;
        }
        box.innerHTML = items.map((a) => {
            const ack = a.Acknowledged ? 'opacity-50' : '';
            const repeat = a.RepeatCount > 1 ? `<span class="text-[10px] text-slate-500">×${a.RepeatCount}</span>` : '';
            const fleet = typeof isLocFleetAlert === 'function' && isLocFleetAlert(a);
            const pc = typeof locFleetPcFromAlert === 'function' ? locFleetPcFromAlert(a) : '';
            const fleetClass = fleet
                ? `alert-card-fleet ${typeof locFleetSevClass === 'function' ? locFleetSevClass(a.Severity) : ''}`
                : this.sevClass(a.Severity);
            const chips = fleet
                ? `<span class="alert-chip-fleet">Fleet</span>${pc ? `<span class="alert-chip-fleet alert-chip-fleet-pc">${this.escape(pc)}</span>` : ''}`
                : '';
            return `
                <div class="p-3 rounded-xl border ${fleetClass} ${ack} flex items-start justify-between gap-3">
                    <div class="flex items-start gap-3 min-w-0">
                        <span class="mt-1.5 w-2.5 h-2.5 rounded-full shrink-0 ${this.sevDot(a.Severity)}"></span>
                        <div class="min-w-0">
                            ${chips ? `<div class="flex items-center gap-1.5 flex-wrap mb-1">${chips}</div>` : ''}
                            <div class="text-sm font-semibold text-slate-100 truncate">${this.escape(a.Title)}</div>
                            <div class="text-xs text-slate-400 mt-0.5">${this.escape(a.Message || '')}</div>
                            <div class="text-[11px] text-slate-500 mt-1 flex gap-2 flex-wrap">
                                <span>${this.escape(a.Severity)}</span>
                                <span>${this.escape(a.Category || '')}</span>
                                <span>${this.relTime(a.Timestamp)}</span>
                                ${repeat}
                            </div>
                        </div>
                    </div>
                    ${a.Acknowledged ? '<span class="text-[10px] text-slate-500 shrink-0">ACK</span>' :
                        `<button type="button" class="action-btn emerald text-[11px] shrink-0" onclick="AlertsView.ack('${this.escape(a.Id)}')">Ack</button>`}
                </div>`;
        }).join('');
        if (typeof refreshAlertsBellCount === 'function') refreshAlertsBellCount();
    },

    async ack(id) {
        await API.request(`alerts/${id}/ack`, 'POST', {});
        await this.refresh();
    }
};

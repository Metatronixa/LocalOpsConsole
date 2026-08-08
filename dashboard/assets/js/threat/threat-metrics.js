/* dashboard/assets/js/threat/threat-metrics.js */
window.ThreatMetrics = {
    render(el, data) {
        const d = data || {};
        el.innerHTML = `
            <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
                ${this.card('Critical', d.Critical, 'text-rose-400')}
                ${this.card('High', d.High, 'text-amber-400')}
                ${this.card('Medium / Low', d.MediumLow, 'text-sky-400')}
                ${this.card('Total (24h)', d.Total, 'text-cyan-400')}
            </div>`;
    },
    card(label, value, color) {
        const n = (value == null) ? '—' : String(value);
        return `<div class="glass-panel p-4 text-center">
            <div class="text-[11px] text-slate-500 uppercase tracking-wider">${ThreatUtils.escape(label)}</div>
            <div class="text-3xl font-bold ${color} mt-1">${ThreatUtils.escape(n)}</div>
        </div>`;
    }
};

/* dashboard/assets/js/threat/threat-stream.js */
window.ThreatStream = {
    render(el, items, onSelect) {
        const rows = Array.isArray(items) ? items : [];
        if (!rows.length) {
            el.innerHTML = `<div class="glass-panel p-6 text-sm text-slate-500">No threat events in buffer yet. Agents POST to /api/v1/fleet/threat-telemetry.</div>`;
            return;
        }
        const body = rows.map((r, idx) => {
            const sev = ThreatUtils.escape(r.Severity || r.severity || '');
            const host = ThreatUtils.escape(r.ComputerName || '');
            const profile = ThreatUtils.escape(r.EnvironmentProfile || '');
            const label = ThreatUtils.escape(r.Label || ('Event ' + (r.EventId || '')));
            const ts = ThreatUtils.escape(r.Timestamp || '');
            const id = ThreatUtils.escape(r.Id || '');
            return `<button type="button" data-idx="${idx}" data-id="${id}"
                class="w-full text-left px-3 py-2 border-b border-slate-800 hover:bg-slate-800/50 flex flex-wrap gap-2 items-center">
                <span class="badge ${ThreatUtils.sevClass(sev)} text-[10px]">${sev}</span>
                <span class="text-xs text-slate-200 font-medium">${label}</span>
                <span class="text-[11px] text-cyan-400/80">${host}</span>
                <span class="text-[10px] text-slate-500 px-1.5 py-0.5 rounded bg-slate-800">${profile}</span>
                <span class="text-[10px] text-slate-500 ml-auto font-mono">${ts}</span>
            </button>`;
        }).join('');
        el.innerHTML = `<div class="glass-panel overflow-hidden max-h-[28rem] overflow-y-auto">${body}</div>`;
        el.querySelectorAll('button[data-id]').forEach(btn => {
            btn.onclick = () => onSelect(btn.getAttribute('data-id'), rows[Number(btn.getAttribute('data-idx'))]);
        });
    }
};

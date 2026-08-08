/* dashboard/assets/js/threat/threat-detail.js */
window.ThreatDetail = {
    render(el, detail) {
        if (!detail) {
            el.innerHTML = `<div class="glass-panel p-4 text-xs text-slate-500">Select an event to inspect.</div>`;
            return;
        }
        const e = ThreatUtils.escape;
        const hits = Array.isArray(detail.KeywordHits) ? detail.KeywordHits : [];
        const plays = Array.isArray(detail.Playbooks) ? detail.Playbooks : [];
        const chips = hits.map(h => `<span class="text-[10px] px-2 py-0.5 rounded bg-rose-500/15 text-rose-300 border border-rose-500/30">${e(h)}</span>`).join(' ');
        const playBtns = plays.map(p =>
            `<button type="button" class="action-btn slate text-[11px]" title="${e(p.Severity || '')}">${e(p.Title || p.Id || 'Playbook')}</button>`
        ).join(' ') || '<span class="text-[11px] text-slate-500">No mapped playbooks</span>';

        el.innerHTML = `
            <div class="glass-panel p-4 space-y-3">
                <div class="flex flex-wrap gap-2 items-center">
                    <span class="badge ${ThreatUtils.sevClass(detail.Severity)} text-[10px]">${e(detail.Severity)}</span>
                    <span class="text-sm text-slate-100 font-semibold">${e(detail.Label)}</span>
                    <span class="text-[11px] text-slate-500 font-mono">ID ${e(detail.EventId)}</span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 text-[11px] text-slate-300">
                    <div><span class="text-slate-500">Host</span><div>${e(detail.ComputerName)}</div></div>
                    <div><span class="text-slate-500">Profile</span><div>${e(detail.EnvironmentProfile)}</div></div>
                    <div><span class="text-slate-500">User</span><div>${e(detail.UserIdentity)}</div></div>
                    <div><span class="text-slate-500">Process</span><div class="font-mono break-all">${e(detail.ProcessName)}</div></div>
                    <div><span class="text-slate-500">Service</span><div>${e(detail.ServiceName)}</div></div>
                    <div><span class="text-slate-500">When</span><div class="font-mono">${e(detail.Timestamp)}</div></div>
                </div>
                <div class="flex flex-wrap gap-1">${chips || '<span class="text-[11px] text-slate-500">No keyword hits</span>'}</div>
                <div>
                    <div class="text-[11px] text-slate-500 uppercase tracking-wider mb-2">Playbook hints</div>
                    <div class="flex flex-wrap gap-2">${playBtns}</div>
                </div>
                <div id="threat-script-viewer"></div>
            </div>`;
        const viewer = el.querySelector('#threat-script-viewer');
        if (window.ThreatScriptViewer) {
            ThreatScriptViewer.render(viewer, detail);
        }
    }
};

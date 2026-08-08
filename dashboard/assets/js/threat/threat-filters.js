/* dashboard/assets/js/threat/threat-filters.js */
window.ThreatFilters = {
    render(el, state, onChange) {
        const profiles = ThreatUtils.profiles.map(p =>
            `<option value="${ThreatUtils.escape(p)}" ${state.profile === p ? 'selected' : ''}>${ThreatUtils.escape(p)}</option>`
        ).join('');
        const sevs = ThreatUtils.severities.map(s =>
            `<option value="${ThreatUtils.escape(s)}" ${state.severity === s ? 'selected' : ''}>${ThreatUtils.escape(s)}</option>`
        ).join('');
        const ids = ThreatUtils.eventIds.map(id =>
            `<option value="${id}" ${String(state.eventId) === String(id) ? 'selected' : ''}>${id}</option>`
        ).join('');
        el.innerHTML = `
            <div class="glass-panel p-3 flex flex-wrap gap-2 items-end">
                <label class="text-[11px] text-slate-500">Profile
                    <select id="threat-f-profile" class="block mt-1 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-slate-200">
                        <option value="">All</option>${profiles}
                    </select>
                </label>
                <label class="text-[11px] text-slate-500">Severity
                    <select id="threat-f-sev" class="block mt-1 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-slate-200">
                        <option value="">All</option>${sevs}
                    </select>
                </label>
                <label class="text-[11px] text-slate-500">Event ID
                    <select id="threat-f-eid" class="block mt-1 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-slate-200">
                        <option value="">All</option>${ids}
                    </select>
                </label>
                <label class="text-[11px] text-slate-500 grow">Search
                    <input id="threat-f-search" type="text" value="${ThreatUtils.escape(state.search || '')}"
                        class="block mt-1 w-full min-w-[12rem] bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-slate-200" placeholder="user, host, script…" />
                </label>
                <button type="button" id="threat-f-apply" class="action-btn cyan text-[11px]">Apply</button>
            </div>`;
        el.querySelector('#threat-f-apply').onclick = () => {
            onChange({
                profile: el.querySelector('#threat-f-profile').value,
                severity: el.querySelector('#threat-f-sev').value,
                eventId: el.querySelector('#threat-f-eid').value,
                search: el.querySelector('#threat-f-search').value.trim()
            });
        };
    }
};

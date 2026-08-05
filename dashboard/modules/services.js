const ServicesView = {
    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Windows Services</h2>
                        <p class="text-xs text-slate-400">Query background service states and trigger controls.</p>
                    </div>
                    <input type="text" id="svc-search" oninput="ServicesView.search(this.value)" placeholder="Search services..."
                        class="px-3 py-1.5 rounded-lg bg-slate-900 border border-slate-800 text-xs font-mono text-slate-200 focus:outline-none focus:border-cyan-500/50 w-64">
                </div>
                <div class="rounded-xl bg-slate-900/60 border border-slate-800 overflow-hidden backdrop-blur-md">
                    <table class="w-full text-left text-xs font-mono">
                        <thead class="bg-slate-900/80 border-b border-slate-800 text-slate-400">
                            <tr>
                                <th class="p-3">DISPLAY NAME</th>
                                <th class="p-3">STATUS</th>
                                <th class="p-3">STARTUP</th>
                                <th class="p-3 text-right">ACTIONS</th>
                            </tr>
                        </thead>
                        <tbody id="svc-table-body" class="divide-y divide-slate-800/50">
                            <tr><td colspan="4" class="p-4 text-slate-500 text-center">Loading system services...</td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
        this.loadServices();
    },

    async loadServices(filter = '') {
        const q = filter ? `Search=${encodeURIComponent(filter)}` : '';
        const res = await API.diagnostic('services', 'GetServices', q, 20000);
        const tbody = document.getElementById('svc-table-body');
        if (!tbody) return;
        if (!res.Success) {
            tbody.innerHTML = `<tr><td colspan="4" class="p-4 text-rose-300 text-center">${res.Message || 'Failed'}</td></tr>`;
            return;
        }
        const rows = API.asArray(res.Data).slice(0, 50);
        const admin = window.__LOC_ADMIN;
        tbody.innerHTML = rows.map((s) => `
            <tr class="hover:bg-slate-800/40 transition">
                <td class="p-3 font-semibold text-slate-200">${s.DisplayName} <span class="text-slate-500 font-normal">(${s.Name})</span></td>
                <td class="p-3"><span class="badge ${s.Status === 'Running' ? 'badge-ok' : 'badge-muted'}">${s.Status}</span></td>
                <td class="p-3 text-slate-400">${s.StartType}</td>
                <td class="p-3 text-right space-x-2">
                    ${s.Status === 'Running'
                        ? `<button ${admin ? '' : 'disabled'} onclick="ServicesView.action('${s.Name}', 'RestartService')" class="action-btn amber">Restart</button>
                           <button ${admin ? '' : 'disabled'} onclick="ServicesView.action('${s.Name}', 'StopService')" class="action-btn rose">Stop</button>`
                        : `<button ${admin ? '' : 'disabled'} onclick="ServicesView.action('${s.Name}', 'StartService')" class="action-btn emerald">Start</button>`
                    }
                </td>
            </tr>
        `).join('');
    },

    search(term) { this.loadServices(term); },

    async action(serviceName, endpoint) {
        LiveConsole.log(`Service ${endpoint} → ${serviceName}`, 'INFO');
        const res = await API.action('services', endpoint, { ServiceName: serviceName });
        if (res.Success) {
            LiveConsole.log(res.Message, 'SUCCESS');
            this.loadServices(document.getElementById('svc-search')?.value || '');
        }
    }
};

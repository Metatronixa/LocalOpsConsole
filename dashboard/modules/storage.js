const StorageView = {
    async render(container) {
        container.innerHTML = `
            <div class="space-y-6 fade-in">
                <div class="flex items-center justify-between">
                    <div>
                        <h2 class="text-lg font-bold text-slate-100">Storage & Volumes</h2>
                        <p class="text-xs text-slate-400">Disk capacity, SMART health, and temp cleaner.</p>
                    </div>
                    <div class="flex gap-2">
                        <button onclick="StorageView.smart()" class="action-btn cyan">SMART Status</button>
                        <button onclick="StorageView.clearTemp()" class="action-btn rose" ${window.__LOC_ADMIN ? '' : 'disabled'}>Clear Temp Files</button>
                    </div>
                </div>
                <div id="disk-grid" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-slate-800 text-slate-500 text-xs font-mono">Querying volumes...</div>
                </div>
                <pre id="smart-out" class="tool-output hidden"></pre>
            </div>
        `;
        this.loadDisks();
    },

    async loadDisks() {
        LiveConsole.log('Scanning logical drive volumes...', 'INFO');
        const res = await API.diagnostic('storage', 'GetDisks', '', 15000);
        const grid = document.getElementById('disk-grid');
        if (!grid) return;
        if (!res.Success) {
            grid.innerHTML = `<div class="p-4 rounded-xl bg-slate-900/60 border border-rose-500/40 text-rose-300 text-xs">${res.Message || 'Failed'}</div>`;
            return;
        }
        const rows = API.asArray(res.Data);
        grid.innerHTML = rows.map((d) => `
            <div class="p-5 rounded-xl bg-slate-900/60 border ${d.LowSpace ? 'border-rose-500/50' : 'border-slate-800'} backdrop-blur-md">
                <div class="flex items-center justify-between mb-2">
                    <span class="font-bold text-slate-100">${d.DeviceID} (${d.VolumeName})</span>
                    <span class="text-xs font-mono ${d.LowSpace ? 'text-rose-400 font-bold' : 'text-slate-400'}">${d.FreePct}% Free</span>
                </div>
                <div class="progress-track my-3"><div class="progress-fill" style="width:${100 - d.FreePct}%"></div></div>
                <div class="text-xs font-mono text-slate-400 flex justify-between">
                    <span>${d.UsedSizeGB} GB Used</span>
                    <span>${d.FreeSpaceGB} GB Available</span>
                </div>
            </div>
        `).join('');
        LiveConsole.log(`Identified ${rows.length} storage volume(s).`, 'SUCCESS');
    },

    async smart() {
        const res = await API.diagnostic('storage', 'SmartStatus');
        const out = document.getElementById('smart-out');
        out.classList.remove('hidden');
        out.textContent = JSON.stringify(res.Data, null, 2);
        LiveConsole.log(res.Message || 'SMART', res.Success ? 'SUCCESS' : 'ERROR', res.Data);
    },

    async clearTemp() {
        if (!confirm('Clear user and Windows temp files?')) return;
        LiveConsole.log('Clearing temp directories...', 'INFO');
        const res = await API.action('storage', 'ClearTemp', { IncludeUserTemp: true, IncludeWindowsTemp: true });
        if (res.Success) {
            LiveConsole.log(res.Message, 'SUCCESS', res.Data);
            this.loadDisks();
        }
    }
};

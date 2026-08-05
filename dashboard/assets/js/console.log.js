const LiveConsole = {
    autoScroll: true,

    log(message, level = 'INFO', details = null) {
        const stream = document.getElementById('live-console-stream');
        if (!stream) return;

        const time = new Date().toLocaleTimeString('en-US', { hour12: false });
        const colors = {
            INFO: 'text-cyan-400',
            SUCCESS: 'text-emerald-400',
            WARN: 'text-amber-400',
            ERROR: 'text-rose-400'
        };

        const line = document.createElement('div');
        line.className = 'flex items-start gap-2 leading-relaxed';

        let detailsBlock = '';
        if (details != null) {
            const text = typeof details === 'string' ? details : JSON.stringify(details, null, 2);
            detailsBlock = `<pre class="mt-1 p-2 rounded bg-slate-900 text-slate-400 text-[11px] border border-slate-800 overflow-x-auto">${this.escape(text)}</pre>`;
        }

        line.innerHTML = `
            <span class="text-slate-600">[${time}]</span>
            <span class="font-bold ${colors[level] || 'text-slate-300'}">[${level}]</span>
            <div class="flex-1 text-slate-200">${this.escape(message)}${detailsBlock}</div>
        `;
        stream.appendChild(line);
        if (this.autoScroll) stream.scrollTop = stream.scrollHeight;
    },

    escape(s) {
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    },

    clear() {
        const stream = document.getElementById('live-console-stream');
        if (stream) stream.innerHTML = '';
    },

    toggleAutoScroll() {
        this.autoScroll = !this.autoScroll;
        const btn = document.getElementById('autoscroll-btn');
        if (btn) btn.innerText = `Auto-Scroll: ${this.autoScroll ? 'ON' : 'OFF'}`;
    },

    async syncFromServer() {
        const res = await API.request('logs/tail?lines=40');
        if (!res.Success || !Array.isArray(res.Data)) return;
        res.Data.forEach((e) => {
            this.log(`${e.Module} ${e.Action}: ${e.Message}`, e.Level || 'INFO');
        });
    }
};

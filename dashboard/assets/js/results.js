/** Human-readable result renderer (tables / cards / monospace output) */
const ResultRenderer = {
    escape(s) {
        return String(s ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    labelize(key) {
        return String(key)
            .replace(/([a-z])([A-Z])/g, '$1 $2')
            .replace(/_/g, ' ')
            .replace(/\b\w/g, (c) => c.toUpperCase());
    },

    isPlainObject(v) {
        return v !== null && typeof v === 'object' && !Array.isArray(v);
    },

    statusClass(val) {
        const s = String(val ?? '').toLowerCase();
        if (['running', 'ok', 'online', 'up', 'true', 'healthy', 'idle', 'normal'].some((x) => s.includes(x))) return 'badge-ok';
        if (['error', 'fail', 'down', 'offline', 'critical', 'false', 'stopped'].some((x) => s.includes(x))) return 'badge-err';
        if (['warn', 'pending', 'degraded', 'unknown'].some((x) => s.includes(x))) return 'badge-warn';
        return 'badge-muted';
    },

    renderValue(val) {
        if (val === null || val === undefined) return '<span class="text-slate-500">—</span>';
        if (typeof val === 'boolean') {
            return `<span class="badge ${val ? 'badge-ok' : 'badge-muted'}">${val ? 'Yes' : 'No'}</span>`;
        }
        const name = String(val);
        if (/^https?:\/\//i.test(name)) {
            return `<a class="text-cyan-400 hover:underline break-all" href="${this.escape(name)}" target="_blank" rel="noopener noreferrer">${this.escape(name)}</a>`;
        }
        if (['Running', 'Stopped', 'Online', 'Offline', 'OK', 'Error', 'Up', 'Down'].includes(name) || /status|state|health/i.test(name)) {
            return `<span class="badge ${this.statusClass(name)}">${this.escape(name)}</span>`;
        }
        if (typeof val === 'object') return `<code>${this.escape(JSON.stringify(val))}</code>`;
        return this.escape(name);
    },

    renderTable(rows) {
        if (!rows.length) return '<p class="text-slate-500 text-xs">No rows.</p>';
        const keys = [];
        rows.forEach((r) => {
            if (this.isPlainObject(r)) {
                Object.keys(r).forEach((k) => { if (!keys.includes(k)) keys.push(k); });
            }
        });
        if (!keys.length) {
            return `<pre class="tool-output">${this.escape(JSON.stringify(rows, null, 2))}</pre>`;
        }
        const head = keys.map((k) => `<th class="p-2 text-left">${this.escape(this.labelize(k))}</th>`).join('');
        const body = rows.map((r) => {
            if (!this.isPlainObject(r)) {
                return `<tr><td class="p-2" colspan="${keys.length}">${this.escape(r)}</td></tr>`;
            }
            const cells = keys.map((k) => `<td class="p-2">${this.renderValue(r[k])}</td>`).join('');
            return `<tr class="hover:bg-slate-800/40">${cells}</tr>`;
        }).join('');
        return `<div class="result-table-wrap"><table class="result-table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
    },

    renderObject(obj) {
        const entries = Object.keys(obj || {});
        if (!entries.length) return '<p class="text-slate-500 text-xs">Empty result.</p>';

        let html = '';
        const scalars = [];
        const nestedArrays = [];
        const nestedObjects = [];

        entries.forEach((k) => {
            const v = obj[k];
            if (Array.isArray(v) && v.length && this.isPlainObject(v[0])) nestedArrays.push([k, v]);
            else if (this.isPlainObject(v)) nestedObjects.push([k, v]);
            else if (Array.isArray(v)) scalars.push([k, v.join(', ')]);
            else scalars.push([k, v]);
        });

        if (scalars.length) {
            html += '<div class="result-card"><dl class="result-dl">';
            scalars.forEach(([k, v]) => {
                html += `<div class="result-dl-row"><dt>${this.escape(this.labelize(k))}</dt><dd>${this.renderValue(v)}</dd></div>`;
            });
            html += '</dl></div>';
        }

        nestedArrays.forEach(([k, arr]) => {
            html += `<h3 class="result-subhead">${this.escape(this.labelize(k))} <span class="badge badge-muted">${arr.length}</span></h3>`;
            html += this.renderTable(arr);
        });

        nestedObjects.forEach(([k, o]) => {
            html += `<h3 class="result-subhead">${this.escape(this.labelize(k))}</h3>`;
            html += this.renderObject(o);
        });

        return html;
    },

    render(message, data) {
        const title = message ? `<div class="result-title">${this.escape(message)}</div>` : '';
        if (data == null) return `${title}<p class="text-slate-500 text-xs">No data.</p>`;

        if (typeof data === 'string') {
            return `${title}<pre class="tool-output">${this.escape(data)}</pre>`;
        }

        if (this.isPlainObject(data) && typeof data.Output === 'string' && Object.keys(data).length <= 3) {
            return `${title}<pre class="tool-output">${this.escape(data.Output)}</pre>`;
        }

        if (Array.isArray(data)) {
            return `${title}${this.renderTable(data)}`;
        }

        if (this.isPlainObject(data)) {
            return `${title}${this.renderObject(data)}`;
        }

        return `${title}<pre class="tool-output">${this.escape(String(data))}</pre>`;
    },

    mount(el, message, data) {
        if (!el) return;
        el.classList.remove('text-slate-500', 'tool-output');
        el.classList.add('result-panel');
        el.innerHTML = this.render(message, data);
    }
};

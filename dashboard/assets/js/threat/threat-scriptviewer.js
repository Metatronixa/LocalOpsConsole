/* dashboard/assets/js/threat/threat-scriptviewer.js — XSS-safe ScriptBlock display */
window.ThreatScriptViewer = {
    render(el, detail) {
        if (!detail || (!detail.RawScriptBlockText && !detail.DecodedScriptBlockText)) {
            el.innerHTML = `<div class="text-[11px] text-slate-500">No ScriptBlock payload on this event.</div>`;
            return;
        }
        const e = ThreatUtils.escape;
        const hits = Array.isArray(detail.KeywordHits) ? detail.KeywordHits : [];
        el.innerHTML = `
            <div class="mt-2">
                <div class="flex flex-wrap gap-2 items-center mb-2">
                    <div class="text-[11px] text-slate-500 uppercase tracking-wider">ScriptBlock</div>
                    <button type="button" id="threat-sb-raw" class="action-btn slate text-[10px]">Raw</button>
                    <button type="button" id="threat-sb-dec" class="action-btn cyan text-[10px]">Decoded</button>
                    <button type="button" id="threat-sb-copy" class="action-btn slate text-[10px]">Copy</button>
                </div>
                <div class="flex flex-wrap gap-1 mb-2" id="threat-sb-chips"></div>
                <pre id="threat-sb-pre" class="text-[11px] font-mono bg-slate-950 border border-slate-800 rounded p-3 overflow-auto max-h-64 text-slate-300 whitespace-pre-wrap break-all"></pre>
            </div>`;
        const chips = el.querySelector('#threat-sb-chips');
        chips.innerHTML = hits.map(h =>
            `<span class="text-[10px] px-2 py-0.5 rounded bg-amber-500/15 text-amber-300">${e(h)}</span>`
        ).join('');
        const pre = el.querySelector('#threat-sb-pre');
        let mode = detail.WasDecoded ? 'decoded' : 'raw';
        const paint = () => {
            const text = mode === 'decoded'
                ? (detail.DecodedScriptBlockText || detail.RawScriptBlockText || '')
                : (detail.RawScriptBlockText || '');
            // textContent only — never innerHTML for script bodies
            pre.textContent = text;
        };
        paint();
        el.querySelector('#threat-sb-raw').onclick = () => { mode = 'raw'; paint(); };
        el.querySelector('#threat-sb-dec').onclick = () => { mode = 'decoded'; paint(); };
        el.querySelector('#threat-sb-copy').onclick = async () => {
            try {
                await navigator.clipboard.writeText(pre.textContent || '');
            } catch (_) { /* ignore */ }
        };
    }
};

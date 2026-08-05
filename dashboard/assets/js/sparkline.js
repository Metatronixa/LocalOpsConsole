const Sparkline = {
    push(arr, value, max = 60) {
        const n = Number(value);
        arr.push(isNaN(n) ? 0 : n);
        while (arr.length > max) arr.shift();
        return arr;
    },

    draw(canvas, seriesList, options) {
        if (!canvas || !canvas.getContext) return;
        const opts = options || {};
        const ctx = canvas.getContext('2d');
        const dpr = window.devicePixelRatio || 1;
        const cssW = canvas.clientWidth || 160;
        const cssH = canvas.clientHeight || 40;
        canvas.width = Math.floor(cssW * dpr);
        canvas.height = Math.floor(cssH * dpr);
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, cssW, cssH);

        const pad = 2;
        let max = opts.max;
        if (max == null || max <= 0) {
            max = 1;
            (seriesList || []).forEach((s) => {
                (s.data || []).forEach((v) => { if (v > max) max = v; });
            });
            if (opts.floorMax && max < opts.floorMax) max = opts.floorMax;
        }

        (seriesList || []).forEach((s) => {
            const data = s.data || [];
            if (data.length < 2) return;
            ctx.beginPath();
            ctx.strokeStyle = s.color || '#22d3ee';
            ctx.lineWidth = 1.5;
            data.forEach((v, i) => {
                const x = pad + (i / (data.length - 1)) * (cssW - pad * 2);
                const y = cssH - pad - (Math.max(0, v) / max) * (cssH - pad * 2);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            });
            ctx.stroke();
        });
    }
};

const API = {
    baseUrl: '/api/v1',
    defaultTimeoutMs: 25000,

    /** Normalize PowerShell JSON quirks: single-item arrays become objects */
    asArray(data) {
        if (data == null) return [];
        if (Array.isArray(data)) return data;
        if (data.Items && Array.isArray(data.Items)) return data.Items;
        if (data.__items && Array.isArray(data.__items)) return data.__items;
        return [data];
    },

    async request(endpoint, method = 'GET', payload = null, timeoutMs = this.defaultTimeoutMs, options = {}) {
        const silent = !!options.silent;
        const reqOptions = {
            method,
            headers: { 'Content-Type': 'application/json' }
        };
        if (payload && (method === 'POST' || method === 'PUT')) {
            reqOptions.body = JSON.stringify(payload);
        }

        const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
        if (controller) reqOptions.signal = controller.signal;
        const timer = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;

        try {
            const response = await fetch(`${this.baseUrl}/${endpoint}`, reqOptions);
            if (!response.ok && !silent) {
                LiveConsole.log(`[API] ${endpoint}: HTTP ${response.status}`, 'WARN');
            }
            const text = await response.text();
            let json;
            try {
                json = text ? JSON.parse(text) : { Success: false, Message: 'Empty response', Data: null };
            } catch {
                if (!silent) {
                    LiveConsole.log(`[API Error] ${endpoint}: invalid JSON (HTTP ${response.status})`, 'ERROR');
                }
                return { Success: false, Message: `Invalid JSON (HTTP ${response.status})`, Data: null };
            }
            if (!json.Success && !silent) {
                LiveConsole.log(`[API] ${json.Message || endpoint}`, 'WARN');
            }
            return json;
        } catch (err) {
            const aborted = err && (err.name === 'AbortError' || /aborted/i.test(err.message || ''));
            const msg = aborted ? `Timed out after ${Math.round(timeoutMs / 1000)}s` : (err.message || 'Failed to fetch');
            if (!silent) {
                LiveConsole.log(`[API Error] ${endpoint}: ${msg}`, 'ERROR');
            }
            return { Success: false, Message: msg, Data: null };
        } finally {
            if (timer) clearTimeout(timer);
        }
    },

    diagnostic(moduleId, name, query = '', timeoutMs) {
        const q = query ? `?${query}` : '';
        return this.request(`${moduleId}/diagnostics/${name}${q}`, 'GET', null, timeoutMs);
    },

    action(moduleId, name, payload = {}, timeoutMs) {
        return this.request(`${moduleId}/actions/${name}`, 'POST', payload, timeoutMs);
    }
};

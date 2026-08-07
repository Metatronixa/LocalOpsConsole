/** Shared fleet target strip + command poller for module pages (Startup first). */
const FleetTarget = {
    STORAGE_KEY: 'loc.fleetTarget.agentId',
    THIS_PC: '__this_pc__',

    _agents: [],
    _selectedId: null,
    _pollTimer: null,

    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    },

    getSelectedId() {
        return this._selectedId || this.THIS_PC;
    },

    isThisPc() {
        return this.getSelectedId() === this.THIS_PC;
    },

    getSelectedAgent() {
        const id = this.getSelectedId();
        if (id === this.THIS_PC) return null;
        return this._agents.find((a) => a.Id === id) || null;
    },

    getSelectedLabel() {
        if (this.isThisPc()) return 'This PC';
        const a = this.getSelectedAgent();
        if (a) return a.ComputerName || a.Hostname || a.Id;
        return this.getSelectedId();
    },

    loadPersisted() {
        try {
            const v = sessionStorage.getItem(this.STORAGE_KEY);
            if (v) this._selectedId = v;
        } catch (e) { /* ignore */ }
        if (!this._selectedId) this._selectedId = this.THIS_PC;
    },

    persist() {
        try {
            sessionStorage.setItem(this.STORAGE_KEY, this.getSelectedId());
        } catch (e) { /* ignore */ }
    },

    setSelected(id, opts) {
        const next = id || this.THIS_PC;
        this._selectedId = next;
        this.persist();
        this.syncSelectEl();
        if (opts && typeof opts.onChange === 'function') opts.onChange(next);
    },

    openForAgent(agentId) {
        if (!agentId) return;
        this._selectedId = String(agentId);
        this.persist();
    },

    async loadAgents() {
        const res = await API.request('fleet/agents', 'GET', null, 15000, { silent: true });
        if (!res.Success) {
            this._agents = [];
            return this._agents;
        }
        this._agents = API.asArray(res.Data).filter((a) => a && !a.Revoked);
        // Drop stale selection if agent gone
        if (!this.isThisPc() && !this._agents.some((a) => a.Id === this._selectedId)) {
            this._selectedId = this.THIS_PC;
            this.persist();
        }
        return this._agents;
    },

    /** Compact HTML strip: This PC | agent dropdown */
    renderStripHtml(selectId) {
        const sid = selectId || 'fleet-target-select';
        const online = this._agents.filter((a) => a.Online);
        const offline = this._agents.filter((a) => !a.Online);
        const opts = [
            `<option value="${this.THIS_PC}">This PC (console host)</option>`
        ];
        if (online.length) {
            opts.push('<optgroup label="Online fleet">');
            online.forEach((a) => {
                const label = this.escape(a.ComputerName || a.Hostname || a.Id);
                opts.push(`<option value="${this.escape(a.Id)}">${label}</option>`);
            });
            opts.push('</optgroup>');
        }
        if (offline.length) {
            opts.push('<optgroup label="Offline fleet">');
            offline.forEach((a) => {
                const label = this.escape(a.ComputerName || a.Hostname || a.Id);
                opts.push(`<option value="${this.escape(a.Id)}">${label} (offline)</option>`);
            });
            opts.push('</optgroup>');
        }
        const note = this._agents.length
            ? ''
            : '<p class="text-[11px] text-slate-500 mt-1 mb-0">No fleet agents enrolled — This PC still works. Enroll under Computers.</p>';
        return `
            <div class="fleet-target-strip glass-panel p-3 flex flex-wrap items-end gap-3">
                <div class="min-w-[220px] flex-1">
                    <label class="text-[11px] text-slate-400" for="${sid}">Target PC</label>
                    <select id="${sid}" class="mt-1 w-full px-2 py-1.5 rounded-lg bg-slate-950 border border-slate-700 text-xs font-mono text-slate-200"
                            onchange="FleetTarget._onSelectChange(this)">
                        ${opts.join('')}
                    </select>
                    ${note}
                </div>
                <div id="fleet-target-badge" class="badge badge-muted shrink-0">This PC</div>
            </div>
        `;
    },

    _onSelectChange(el) {
        if (!el) return;
        this.setSelected(el.value, { onChange: this._changeHandler });
        this.updateBadge();
    },

    _changeHandler: null,

    bind(selectId, onChange) {
        this._changeHandler = onChange || null;
        this.loadPersisted();
        this.syncSelectEl(selectId);
        this.updateBadge();
    },

    syncSelectEl(selectId) {
        const el = document.getElementById(selectId || 'fleet-target-select');
        if (!el) return;
        const want = this.getSelectedId();
        if ([].some.call(el.options, (o) => o.value === want)) {
            el.value = want;
        } else {
            el.value = this.THIS_PC;
            this._selectedId = this.THIS_PC;
        }
        this.updateBadge();
    },

    updateBadge() {
        const badge = document.getElementById('fleet-target-badge');
        if (!badge) return;
        if (this.isThisPc()) {
            badge.className = 'badge badge-muted shrink-0';
            badge.textContent = 'This PC';
            return;
        }
        const a = this.getSelectedAgent();
        const online = a && a.Online;
        badge.className = `badge ${online ? 'badge-ok' : 'badge-warn'} shrink-0`;
        badge.textContent = online ? 'Fleet online' : 'Fleet offline';
    },

    stopPoll() {
        if (this._pollTimer) {
            clearTimeout(this._pollTimer);
            this._pollTimer = null;
        }
    },

    /**
     * Queue a fleet command and poll until terminal status.
     * @returns {Promise<{Success:boolean, Message:string, Data:*, Status:string, CommandId:string}>}
     */
    async queueAndWait(agentId, type, payload, opts) {
        const options = opts || {};
        const onStatus = typeof options.onStatus === 'function' ? options.onStatus : null;
        const timeoutMs = options.timeoutMs || 180000;
        const intervalMs = options.intervalMs || 2000;
        const label = options.label || type;

        this.stopPoll();

        if (!agentId || agentId === this.THIS_PC) {
            return { Success: false, Message: 'Select a fleet PC first', Data: null, Status: 'Failed', CommandId: '' };
        }

        const agent = this._agents.find((a) => a.Id === agentId);
        const host = agent ? (agent.ComputerName || agent.Hostname || agentId) : agentId;
        if (agent && !agent.Online) {
            if (onStatus) onStatus({ Status: 'Pending', Host: host, Type: type, Detail: 'Agent offline — command will stay Pending until it connects' });
        }

        if (onStatus) onStatus({ Status: 'Queuing', Host: host, Type: type, Detail: `Queueing ${label}…` });

        const queued = await API.request('fleet/commands', 'POST', {
            AgentId: agentId,
            Type: type,
            Payload: payload || {}
        }, 20000);

        if (!queued.Success || !queued.Data) {
            const msg = queued.Message || 'Failed to queue command';
            if (onStatus) onStatus({ Status: 'Failed', Host: host, Type: type, Detail: msg });
            return { Success: false, Message: msg, Data: null, Status: 'Failed', CommandId: '' };
        }

        const cmdId = String(queued.Data.Id || queued.Data.id || '');
        if (!cmdId) {
            return { Success: false, Message: 'Queued but no command id', Data: null, Status: 'Failed', CommandId: '' };
        }

        if (onStatus) onStatus({ Status: 'Pending', Host: host, Type: type, CommandId: cmdId, Detail: `Pending on ${host} · ${type}` });

        const started = Date.now();
        return new Promise((resolve) => {
            const tick = async () => {
                if (Date.now() - started > timeoutMs) {
                    this._pollTimer = null;
                    const msg = `Timed out waiting for ${type} on ${host} (${Math.round(timeoutMs / 1000)}s)`;
                    if (onStatus) onStatus({ Status: 'Timeout', Host: host, Type: type, CommandId: cmdId, Detail: msg });
                    resolve({ Success: false, Message: msg, Data: null, Status: 'Timeout', CommandId: cmdId });
                    return;
                }

                try {
                    const detail = await API.request(`fleet/agents/${encodeURIComponent(agentId)}`, 'GET', null, 15000, { silent: true });
                    const cmds = detail.Success && detail.Data
                        ? API.asArray(detail.Data.Commands || detail.Data.commands)
                        : [];
                    const cmd = cmds.find((c) => String(c.Id) === cmdId);
                    if (!cmd) {
                        if (onStatus) onStatus({ Status: 'Pending', Host: host, Type: type, CommandId: cmdId, Detail: `Waiting for command on ${host}…` });
                    } else {
                        const st = String(cmd.Status || 'Pending');
                        if (onStatus) {
                            onStatus({
                                Status: st,
                                Host: host,
                                Type: type,
                                CommandId: cmdId,
                                Detail: st === 'Running'
                                    ? `Running on ${host} · ${type}`
                                    : (st === 'Pending' ? `Pending on ${host} · ${type}` : `${st} · ${type}`)
                            });
                        }
                        if (st === 'Completed' || st === 'Failed' || st === 'Cancelled') {
                            this._pollTimer = null;
                            const res = cmd.Result || {};
                            const ok = st === 'Completed' && (res.Success !== false);
                            resolve({
                                Success: ok,
                                Message: res.Message || (ok ? 'OK' : (st === 'Cancelled' ? 'Cancelled' : 'Failed')),
                                Data: res.Data != null ? res.Data : null,
                                Status: st,
                                CommandId: cmdId
                            });
                            return;
                        }
                    }
                } catch (e) {
                    if (onStatus) onStatus({ Status: 'Pending', Host: host, Type: type, CommandId: cmdId, Detail: 'Polling…' });
                }

                this._pollTimer = setTimeout(tick, intervalMs);
            };
            this._pollTimer = setTimeout(tick, 600);
        });
    }
};

const LocSplash = {
  minMs: 5000,
  startedAt: Date.now(),
  engineReady: false,
  engineOk: false,
  dismissed: false,
  _statusTimer: null,

  statuses: [
    'Starting engine…',
    'Loading modules…',
    'Connecting fleet…',
    'Calibrating telemetry…',
    'Ready'
  ],

  init() {
    const el = document.getElementById('loc-splash');
    if (!el) return;
    let i = 0;
    const status = document.getElementById('loc-splash-status');
    this._statusTimer = setInterval(() => {
      if (i < this.statuses.length - 1) i += 1;
      if (status) status.textContent = this.statuses[i];
      if (this.engineReady && i >= this.statuses.length - 2) {
        if (status) status.textContent = this.engineOk ? 'Ready' : 'Engine unavailable';
      }
    }, 900);
    this._tryDismiss();
    setTimeout(() => this._tryDismiss(), this.minMs + 50);
  },

  markReady(ok) {
    this.engineReady = true;
    this.engineOk = !!ok;
    const status = document.getElementById('loc-splash-status');
    const elapsed = Date.now() - this.startedAt;
    if (elapsed >= this.minMs) {
      if (status) status.textContent = ok ? 'Ready' : 'Engine unavailable';
      this._tryDismiss();
    }
  },

  _tryDismiss() {
    if (this.dismissed) return;
    const elapsed = Date.now() - this.startedAt;
    if (elapsed < this.minMs) return;
    if (!this.engineReady && elapsed < this.minMs + 8000) {
      // wait a bit more for health; hard fallback later
      setTimeout(() => {
        if (!this.engineReady) this.markReady(false);
        this._tryDismiss();
      }, 500);
      return;
    }
    this.dismiss();
  },

  dismiss() {
    if (this.dismissed) return;
    this.dismissed = true;
    if (this._statusTimer) clearInterval(this._statusTimer);
    const el = document.getElementById('loc-splash');
    if (!el) return;
    el.classList.add('is-done');
    setTimeout(() => {
      try { el.remove(); } catch { }
    }, 450);
  }
};

document.addEventListener('DOMContentLoaded', () => LocSplash.init());

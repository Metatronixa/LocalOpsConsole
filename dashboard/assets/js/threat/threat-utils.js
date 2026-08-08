/* dashboard/assets/js/threat/threat-utils.js */
window.ThreatUtils = {
    escape(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    },
    sevClass(sev) {
        const v = String(sev || '').toUpperCase();
        if (v === 'CRITICAL') return 'badge-rose';
        if (v === 'HIGH') return 'badge-amber';
        if (v === 'MEDIUM') return 'badge-sky';
        if (v === 'LOW') return 'badge-slate';
        return 'badge-slate';
    },
    profiles: ['DomainController', 'ActiveDirectoryMember', 'EntraCloudJoined', 'StandaloneWorkgroup'],
    severities: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO'],
    eventIds: [1102, 4104, 4624, 4625, 4688, 4697, 4769, 7045]
};

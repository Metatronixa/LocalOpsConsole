const Router = {
    modules: [],
    current: null,

    setModules(list) {
        this.modules = list || [];
    },

    async loadModuleView(moduleId) {
        const viewport = document.getElementById('page-content');
        const mod = this.modules.find((m) => m.id.toLowerCase() === String(moduleId).toLowerCase());
        LiveConsole.log(`Navigating to view: ${moduleId}`, 'INFO');
        this.current = moduleId;

        if (typeof SystemView !== 'undefined' && SystemView.stopPoll) {
            SystemView._active = false;
            SystemView.stopPoll();
        }
        if (typeof FleetView !== 'undefined' && FleetView.stopPoll) {
            FleetView.stopPoll();
        }
        if (typeof FleetTarget !== 'undefined' && FleetTarget.stopPoll) {
            FleetTarget.stopPoll();
        }
        if (typeof AlertsView !== 'undefined' && AlertsView.stopPoll) {
            AlertsView.stopPoll();
        }
        if (typeof IncidentsView !== 'undefined' && IncidentsView.stopPoll) {
            IncidentsView.stopPoll();
        }
        if (typeof OverviewView !== 'undefined' && OverviewView.stopPoll) {
            OverviewView.stopPoll();
        }
        if (typeof HealthCenterView !== 'undefined' && HealthCenterView.stopPoll) {
            HealthCenterView.stopPoll();
        }
        if (typeof SecurityCenterView !== 'undefined' && SecurityCenterView.stopPoll) {
            SecurityCenterView.stopPoll();
        }

        document.querySelectorAll('#sidebar-nav button').forEach((btn) => {
            btn.classList.toggle('active', btn.dataset.module === (mod ? mod.id : moduleId));
        });

        // Expand only the section that contains the active module; leave others collapsed.
        document.querySelectorAll('#sidebar-nav [data-nav-section]').forEach((body) => {
            const hasActive = !!body.querySelector('button.active');
            body.style.display = hasActive ? '' : 'none';
        });

        if (!mod) {
            viewport.innerHTML = `<div class="p-6 text-slate-400">Module not found.</div>`;
            return;
        }

        // Rich custom views when available
        const custom = {
            system: typeof SystemView !== 'undefined' ? SystemView : null,
            services: typeof ServicesView !== 'undefined' ? ServicesView : null,
            tools: typeof ToolsView !== 'undefined' ? ToolsView : null,
            network: typeof NetworkView !== 'undefined' ? NetworkView : null,
            storage: typeof StorageView !== 'undefined' ? StorageView : null,
            configuration: typeof ConfigurationView !== 'undefined' ? ConfigurationView : null,
            printers: typeof PrintersView !== 'undefined' ? PrintersView : null,
            startup: typeof StartupView !== 'undefined' ? StartupView : null,
            remotesupport: typeof RemoteSupportView !== 'undefined' ? RemoteSupportView : null,
            remote: typeof RemoteView !== 'undefined' ? RemoteView : null,
            internetslow: typeof InternetHealthView !== 'undefined' ? InternetHealthView : null,
            fleet: typeof FleetView !== 'undefined' ? FleetView : null,
            networkmap: typeof NetworkMapView !== 'undefined' ? NetworkMapView : null,
            security: typeof SecurityToolsView !== 'undefined' ? SecurityToolsView : null,
            eventlog: typeof EventLogView !== 'undefined' ? EventLogView : null,
            overview: typeof OverviewView !== 'undefined' ? OverviewView : null,
            alerts: typeof AlertsView !== 'undefined' ? AlertsView : null,
            securitycenter: typeof SecurityCenterView !== 'undefined' ? SecurityCenterView : null,
            threatoperations: typeof ThreatOperationsView !== 'undefined' ? ThreatOperationsView : null,
            healthcenter: typeof HealthCenterView !== 'undefined' ? HealthCenterView : null,
            incidents: typeof IncidentsView !== 'undefined' ? IncidentsView : null,
            timeline: typeof EventTimelineView !== 'undefined' ? EventTimelineView : null,
            automation: typeof AutomationView !== 'undefined' ? AutomationView : null,
            locsettings: typeof SettingsView !== 'undefined' ? SettingsView : null,
            securitybaseline: typeof SecurityBaselineView !== 'undefined' ? SecurityBaselineView : null
        };

        const key = mod.id.toLowerCase();
        if (custom[key]) {
            await custom[key].render(viewport, mod);
        } else {
            await ModuleView.render(viewport, mod);
        }
        lucide.createIcons();
    }
};

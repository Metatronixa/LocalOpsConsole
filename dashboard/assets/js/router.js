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

        document.querySelectorAll('#sidebar-nav button').forEach((btn) => {
            btn.classList.toggle('active', btn.dataset.module === (mod ? mod.id : moduleId));
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
            configuration: typeof ConfigurationView !== 'undefined' ? ConfigurationView : null
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

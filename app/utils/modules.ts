// Single source of truth for what a "module" is (one home-page tile), its
// underlying permission "resources" (the exact `module` strings stored in
// role_permissions), and each resource's available actions. Consumed by the
// home page icon grid, the admin role editor, the CRM sidebar nav, and
// route-guard middleware. Adding a future module is just appending an entry
// here — no schema or framework change needed.
//
// Labels are i18n keys (resolved with $t() at render time), not literal
// text, so this stays a single source of truth across locales too.

export interface ModuleActionDef {
  key: string;
  labelKey: string;
}

export interface ModuleResourceDef {
  key: string;
  labelKey: string;
  actions: ModuleActionDef[];
}

export interface ModuleDef {
  key: string;
  labelKey: string;
  icon: string;
  route: string;
  resources: ModuleResourceDef[];
}

function crud(resourceKey: string): ModuleActionDef[] {
  return [
    { key: "create", labelKey: `resources.${resourceKey}.actions.create` },
    { key: "edit", labelKey: `resources.${resourceKey}.actions.edit` },
    { key: "delete", labelKey: `resources.${resourceKey}.actions.delete` },
  ];
}

// The pages of Settings. Each one is its own permission (action) on the
// "settings" resource, so a role can be allowed to manage some of them without
// being an administrator. Order here is the order they show in the menu.
export interface SettingsItemDef {
  key: string;
  path: string;
  titleKey: string;
  icon: string;
}
export const SETTINGS_ITEMS: SettingsItemDef[] = [
  { key: "users", path: "/admin/users", titleKey: "admin.users.title", icon: "i-lucide-users" },
  { key: "roles", path: "/admin/roles", titleKey: "admin.roles.title", icon: "i-lucide-shield" },
  { key: "pipelines", path: "/admin/pipelines", titleKey: "admin.pipelines.title", icon: "i-lucide-git-branch" },
  { key: "activity_types", path: "/admin/activity-types", titleKey: "admin.activityTypes.title", icon: "i-lucide-list-checks" },
  { key: "product_categories", path: "/admin/product-categories", titleKey: "admin.productCategories.title", icon: "i-lucide-tags" },
  { key: "teams", path: "/admin/teams", titleKey: "admin.teams.title", icon: "i-lucide-users-round" },
  { key: "automation", path: "/admin/automation", titleKey: "admin.automation.title", icon: "i-lucide-zap" },
  { key: "service_areas", path: "/admin/service-areas", titleKey: "admin.serviceAreas.title", icon: "i-lucide-map" },
  { key: "cs_pipelines", path: "/admin/cs-pipelines", titleKey: "admin.csPipelines.title", icon: "i-lucide-workflow" },
  { key: "visit_types", path: "/admin/visit-types", titleKey: "admin.visitTypes.title", icon: "i-lucide-map-pinned" },
  { key: "integrations", path: "/admin/integrations", titleKey: "admin.integrations.title", icon: "i-lucide-plug" },
  { key: "work_pipelines", path: "/admin/work-pipelines", titleKey: "admin.workPipelines.title", icon: "i-lucide-kanban" },
  { key: "notification_emails", path: "/admin/notification-emails", titleKey: "admin.notificationEmails.title", icon: "i-lucide-mail" },
];

// Ready-made reports. Each one is its own permission (action) on the "reports"
// resource, so a role can be allowed to open some reports and not others.
export interface ReportDef {
  key: string;
  path: string;
  titleKey: string;
  descriptionKey: string;
  icon: string;
}
export const REPORTS: ReportDef[] = [
  { key: "maintenance_done", path: "/cs/reports/maintenance-done", titleKey: "reports.maintenanceDone.title", descriptionKey: "reports.maintenanceDone.description", icon: "i-lucide-wrench" },
  { key: "maintenance_rescheduled", path: "/cs/reports/maintenance-rescheduled", titleKey: "reports.maintenanceRescheduled.title", descriptionKey: "reports.maintenanceRescheduled.description", icon: "i-lucide-calendar-sync" },
  { key: "spare_parts_used", path: "/cs/reports/spare-parts-used", titleKey: "reports.sparePartsUsed.title", descriptionKey: "reports.sparePartsUsed.description", icon: "i-lucide-package" },
];

// Which Settings page a path belongs to (/admin/roles/123 -> "roles"), or null
// for the Settings hub itself.
export function settingsKeyForPath(path: string) {
  return SETTINGS_ITEMS.find((i) => path === i.path || path.startsWith(`${i.path}/`))?.key ?? null;
}

export const MODULES: ModuleDef[] = [
  {
    key: "crm",
    labelKey: "modules.crm.label",
    icon: "i-lucide-briefcase",
    route: "/crm",
    resources: [
      {
        key: "crm_leads",
        labelKey: "resources.crm_leads.label",
        actions: [
          // Shows the Leads tab and the leads list / profile pages.
          { key: "view", labelKey: "resources.crm_leads.actions.view" },
          ...crud("crm_leads"),
          { key: "assign", labelKey: "resources.crm_leads.actions.assign" },
          { key: "view_all", labelKey: "resources.crm_leads.actions.view_all" },
        ],
      },
      {
        key: "crm_deals",
        labelKey: "resources.crm_deals.label",
        actions: [
          ...crud("crm_deals"),
          { key: "assign", labelKey: "resources.crm_deals.actions.assign" },
          { key: "view_all", labelKey: "resources.crm_deals.actions.view_all" },
        ],
      },
      { key: "crm_quotes", labelKey: "resources.crm_quotes.label", actions: crud("crm_quotes") },
      {
        // Field trips (مأمورية) and inspections (معاينة): requested on a deal,
        // approved by the requester's team leader and then by anyone with
        // "approve" or "view all" here.
        key: "crm_visits",
        labelKey: "resources.crm_visits.label",
        actions: [
          { key: "create", labelKey: "resources.crm_visits.actions.create" },
          { key: "edit", labelKey: "resources.crm_visits.actions.edit" },
          { key: "approve", labelKey: "resources.crm_visits.actions.approve" },
          { key: "view_all", labelKey: "resources.crm_visits.actions.view_all" },
        ],
      },
      {
        // The boards of the sub-workflows (e.g. the technical office): see them, and
        // move / assign the items. Any action opens the boards.
        key: "crm_work",
        labelKey: "resources.crm_work.label",
        actions: [
          { key: "view", labelKey: "resources.crm_work.actions.view" },
          { key: "edit", labelKey: "resources.crm_work.actions.edit" },
        ],
      },
      {
        key: "crm_customers",
        labelKey: "resources.crm_customers.label",
        actions: [
          ...crud("crm_customers"),
          { key: "assign", labelKey: "resources.crm_customers.actions.assign" },
          { key: "view_all", labelKey: "resources.crm_customers.actions.view_all" },
        ],
      },
    ],
  },
  {
    // Customer service: customers (everyone the CRM won, plus ones added here)
    // with a richer profile and their products / installation progress.
    key: "customer_service",
    labelKey: "modules.customer_service.label",
    icon: "i-lucide-headset",
    route: "/cs",
    resources: [
      {
        key: "cs_customers",
        labelKey: "resources.cs_customers.label",
        actions: [
          ...crud("cs_customers"),
          // Give a customer to a Customer Service agent.
          { key: "assign", labelKey: "resources.cs_customers.actions.assign" },
          // Without it an agent sees only the customers assigned to them.
          { key: "view_all", labelKey: "resources.cs_customers.actions.view_all" },
        ],
      },
      {
        // Maintenance of operating products: appointments, visits done,
        // cancellations and notes. Any one of these opens the Maintenance pages.
        key: "cs_maintenance",
        labelKey: "resources.cs_maintenance.label",
        actions: [
          { key: "view", labelKey: "resources.cs_maintenance.actions.view" },
          { key: "schedule", labelKey: "resources.cs_maintenance.actions.schedule" },
          { key: "complete", labelKey: "resources.cs_maintenance.actions.complete" },
          { key: "cancel", labelKey: "resources.cs_maintenance.actions.cancel" },
          { key: "note", labelKey: "resources.cs_maintenance.actions.note" },
          // The Confirmed visits page: only the visits assigned to me, or every one.
          { key: "view_confirmed_own", labelKey: "resources.cs_maintenance.actions.view_confirmed_own" },
          { key: "view_confirmed_all", labelKey: "resources.cs_maintenance.actions.view_confirmed_all" },
        ],
      },
      {
        // The parts of each product category, with their price.
        key: "cs_spare_parts",
        labelKey: "resources.cs_spare_parts.label",
        actions: crud("cs_spare_parts"),
      },
      {
        // What a maintenance visit costs in each area.
        key: "cs_visit_costs",
        labelKey: "resources.cs_visit_costs.label",
        actions: [
          { key: "view", labelKey: "resources.cs_visit_costs.actions.view" },
          { key: "edit", labelKey: "resources.cs_visit_costs.actions.edit" },
        ],
      },
      {
        // Ready-made reports (one action per report), viewed on screen and exported to PDF.
        key: "reports",
        labelKey: "resources.reports.label",
        actions: REPORTS.map((r) => ({ key: r.key, labelKey: r.titleKey })),
      },
    ],
  },
  {
    // Settings is reached through its own entry on the home page and sidebar,
    // not as a module tile; it is listed here so roles can grant its pages.
    key: "settings",
    labelKey: "nav.settings",
    icon: "i-lucide-settings",
    route: "/admin",
    resources: [
      {
        key: "settings",
        labelKey: "nav.settings",
        actions: SETTINGS_ITEMS.map((i) => ({ key: i.key, labelKey: i.titleKey })),
      },
    ],
  },
];

export function findModule(moduleKey: string) {
  return MODULES.find((m) => m.key === moduleKey);
}

export function findResource(resourceKey: string) {
  for (const module of MODULES) {
    const resource = module.resources.find((r) => r.key === resourceKey);
    if (resource) return { module, resource };
  }
  return undefined;
}

// The Maintenance permissions that open the Maintenance pages. The two
// "confirmed visits" permissions open only the Confirmed visits page.
export const MAINTENANCE_FULL_ACTIONS = ["view", "schedule", "complete", "cancel", "note"];
export const CONFIRMED_VISIT_ACTIONS = ["view_confirmed_own", "view_confirmed_all"];

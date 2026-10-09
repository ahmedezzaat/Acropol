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
        actions: crud("cs_customers"),
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

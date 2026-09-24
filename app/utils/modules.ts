// Single source of truth for what a "module" is (one home-page tile), its
// underlying permission "resources" (the exact `module` strings stored in
// role_permissions), and each resource's available actions. Consumed by the
// home page icon grid, the admin role editor, the CRM sidebar nav, and
// route-guard middleware. Adding a future module is just appending an entry
// here — no schema or framework change needed.

export interface ModuleActionDef {
  key: string;
  label: string;
}

export interface ModuleResourceDef {
  key: string;
  label: string;
  actions: ModuleActionDef[];
}

export interface ModuleDef {
  key: string;
  label: string;
  icon: string;
  route: string;
  resources: ModuleResourceDef[];
}

const CRUD: ModuleActionDef[] = [
  { key: "create", label: "Create" },
  { key: "edit", label: "Edit" },
  { key: "delete", label: "Delete" },
];

export const MODULES: ModuleDef[] = [
  {
    key: "crm",
    label: "CRM",
    icon: "i-lucide-briefcase",
    route: "/crm",
    resources: [
      {
        key: "crm_leads",
        label: "Leads",
        actions: [
          ...CRUD,
          { key: "assign", label: "Assign leads" },
          { key: "view_all", label: "View all leads" },
        ],
      },
      { key: "crm_deals", label: "Deals", actions: CRUD },
      { key: "crm_quotes", label: "Quotes", actions: CRUD },
      { key: "crm_customers", label: "Customers", actions: CRUD },
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

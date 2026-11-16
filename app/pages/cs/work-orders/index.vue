<script setup lang="ts">
// The installation, operation and inspection work orders made from the confirmed visits page.
// (A maintenance work order is a done visit: it is in the maintenance reports and the customer's history.)
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_maintenance", anyAction: ["complete", "view_confirmed_all", "view_confirmed_own"] },
});

const supabase = useSupabaseClient();
const { t } = useI18n();
const { hasPermission } = usePermissions();

interface Row {
  id: string; number: string; kind: SimpleWorkOrderKind; customer_id: string | null; lead_id: string | null;
  subject_name: string; subject_phone: string | null; work_date: string; note: string | null; done_note: string | null; done_on: string | null; status: "pending" | "done"; signature_path: string | null;
  technician_id: string | null;
  technician: { full_name: string | null; email: string } | null;
}
const { data: rows, refresh, status } = await useAsyncData<Row[]>("cs-work-orders", async () => {
  const { data } = await supabase
    .from("cs_work_orders")
    .select("id, number, kind, customer_id, lead_id, subject_name, subject_phone, work_date, note, done_note, done_on, status, signature_path, technician_id, technician:profiles!technician_id(full_name, email)")
    .order("work_date", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(500);
  return (data ?? []) as unknown as Row[];
});

// giving a pending order to a technician (or changing the technician)
const toast = useToast();
const canAssign = computed(() => hasPermission("cs_maintenance", "schedule") || hasPermission("cs_maintenance", "complete"));
const { data: technicians } = await useAsyncData<{ id: string; full_name: string | null; email: string }[]>("cs-work-orders-technicians", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_technician", true).eq("is_active", true).order("full_name");
  return (data ?? []) as { id: string; full_name: string | null; email: string }[];
});
const assignMenu = (r: Row) => [
  (technicians.value ?? []).map((u) => ({
    label: u.full_name || u.email,
    icon: u.id === r.technician_id ? "i-lucide-check" : "i-lucide-hard-hat",
    onSelect: () => assign(r, u.id),
  })),
];
async function assign(r: Row, technicianId: string) {
  const { error } = await supabase.rpc("cs_assign_work_order", { p_id: r.id, p_technician: technicianId });
  if (error) return toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
  toast.add({ title: t("cs.workOrders.assigned"), color: "success" });
  await refresh();
}

const kind = ref<"all" | SimpleWorkOrderKind>("all");
const statusFilter = ref<"all" | "pending" | "done">("all");
const statusTabs = computed(() => (["all", "pending", "done"] as const).map((k) => ({
  value: k,
  label: `${k === "all" ? t("cs.confirmedVisits.all") : t(`cs.workOrders.${k}`)} · ${(rows.value ?? []).filter((r) => k === "all" || r.status === k).length}`,
})));
const canComplete = computed(() => hasPermission("cs_maintenance", "complete"));
const completeOpen = ref(false);
const completing = ref<Row | null>(null);
function openComplete(r: Row) {
  completing.value = r;
  completeOpen.value = true;
}
const search = ref("");
const kinds = ["installation", "operation", "inspection"] as const;
const tabs = computed(() => [
  { value: "all", label: `${t("cs.confirmedVisits.all")} · ${rows.value?.length ?? 0}` },
  ...kinds.map((k) => ({ value: k, label: `${t(`cs.workOrders.kind.${k}`)} · ${(rows.value ?? []).filter((r) => r.kind === k).length}` })),
]);
const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return (rows.value ?? []).filter((r) => (kind.value === "all" || r.kind === kind.value) && (statusFilter.value === "all" || r.status === statusFilter.value) && (!q || `${r.subject_name} ${r.subject_phone ?? ""} ${r.number} ${r.note ?? ""}`.toLowerCase().includes(q)));
});
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('cs.workOrders.title')" :count="shown.length">
        <template #right><WorkOrderCreate @saved="refresh()" /></template>
      </KPageHeader>
      <div class="kords-filterbar w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <UTabs v-model="kind" :items="tabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs" />
        <div class="flex gap-2">
          <button v-for="s in statusTabs" :key="s.value" type="button" class="kords-chip" :class="statusFilter === s.value && 'kords-chip-on'" @click="statusFilter = s.value">{{ s.label }}</button>
        </div>
        <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.workOrders.search')" class="w-full" />
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending'" class="flex justify-center py-16"><UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" /></div>
      <p v-else-if="!shown.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.workOrders.empty") }}</p>
      <ul v-else class="mx-auto w-full max-w-4xl space-y-2">
        <li v-for="r in shown" :key="r.id" class="kords-card flex flex-wrap items-center justify-between gap-3 p-4 text-sm">
          <div class="min-w-0 space-y-1">
            <div class="flex flex-wrap items-center gap-2">
              <KBadge :label="t(`cs.workOrders.kind.${r.kind}`)" :tone="WORK_ORDER_TONES[r.kind]" :icon="WORK_ORDER_ICONS[r.kind]" />
              <bdi dir="ltr" class="text-xs text-muted">{{ r.number }}</bdi>
              <KBadge :label="t(`cs.workOrders.${r.status}`)" :tone="r.status === 'done' ? 'success' : 'warning'" :icon="r.status === 'done' ? 'i-lucide-check' : 'i-lucide-clock'" />
              <KBadge v-if="r.status === 'pending' && !r.technician_id" :label="t('cs.workOrders.unassigned')" tone="error" outlined icon="i-lucide-user-x" />
              <KBadge v-if="r.lead_id" :label="t('cs.workOrders.forLead')" tone="warning" outlined />
              <KBadge v-if="r.status === 'done' && !r.signature_path" :label="t('cs.workOrders.unsigned')" tone="neutral" outlined />
            </div>
            <NuxtLink v-if="r.customer_id" :to="`/cs/customers/${r.customer_id}`" class="block font-semibold text-highlighted hover:text-primary">{{ r.subject_name }}</NuxtLink>
            <p v-else class="font-semibold text-highlighted">{{ r.subject_name }}</p>
            <p class="text-xs text-muted">
              {{ formatDMY(r.done_on ?? r.work_date) }}
              <template v-if="r.subject_phone"> · <bdi dir="ltr">{{ r.subject_phone }}</bdi></template>
              <template v-if="r.technician"> · {{ r.technician.full_name || r.technician.email }}</template>
            </p>
            <p v-if="r.note" class="whitespace-pre-line text-toned">{{ r.note }}</p>
            <p v-if="r.done_note" class="whitespace-pre-line rounded-[8px] bg-success/10 p-2 text-toned">{{ r.done_note }}</p>
          </div>
          <div class="flex items-center gap-2">
            <UDropdownMenu v-if="r.status === 'pending' && canAssign && technicians?.length" :items="assignMenu(r)">
              <UButton icon="i-lucide-hard-hat" size="sm" color="neutral" variant="outline" :label="r.technician_id ? t('cs.workOrders.changeTechnician') : t('cs.workOrders.assign')" />
            </UDropdownMenu>
            <UButton v-if="r.status === 'pending' && canComplete" icon="i-lucide-check" size="sm" color="success" variant="soft" :label="t('cs.workOrders.markDone')" @click="openComplete(r)" />
            <UButton :to="`/print/work-order/${r.id}`" target="_blank" icon="i-lucide-printer" size="sm" color="neutral" variant="outline" :label="t('cs.workOrders.print')" />
          </div>
        </li>
      </ul>
    </template>
  </UDashboardPanel>
  <WorkOrderCompleteModal v-model:open="completeOpen" :order="completing" @saved="refresh()" />
</template>

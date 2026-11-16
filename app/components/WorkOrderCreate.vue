<script setup lang="ts">
// "أمر شغل جديد": a work order made straight from the confirmed visits page.
//   maintenance                      : pick the customer and the products serviced, then the usual done-visit form
//   installation / operation / inspection: a customer (an inspection also a lead), the date, technician, notes and the
//                                      customer's signature. No next visit and no spare parts.
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const canCreate = computed(() => hasPermission("cs_maintenance", "complete"));

const open = ref(false);
const kind = ref<WorkOrderKind>("maintenance");
const subjectType = ref<"customer" | "lead">("customer");
const subjectId = ref<string | null>(null);
const search = ref("");
interface Option { label: string; value: string; name: string; phone: string | null; address: string | null }
const options = ref<Option[]>([]);

const today = () => new Date().toISOString().slice(0, 10);
const workDate = ref(today());
const technicianId = ref<string | null>(null);
const note = ref("");
// done already (recorded now, with the signature) or given to a technician to do (pending)
const mode = ref<"done" | "assign">("done");
const signed = ref(false);
const noSignature = ref(false);
const signaturePad = ref<{ toBlob: () => Promise<Blob | null>; clear: () => void } | null>(null);
const saving = ref(false);

// an inspection can be for a lead; everything else is for a customer
const canPickLead = computed(() => kind.value === "inspection");
watch(kind, () => {
  if (!canPickLead.value) subjectType.value = "customer";
  subjectId.value = null;
  products.value = [];
  picked.value = new Set();
  search.value = " ";
  search.value = "";
});
watch(subjectType, () => {
  subjectId.value = null;
  search.value = " ";
  search.value = "";
});

// ---- find the customer / lead by name or phone
const label = (a: { name: string; company?: string | null; phone: string | null }) => [a.company, a.name, a.phone].filter(Boolean).join(" · ");
let timer: ReturnType<typeof setTimeout> | undefined;
watch(search, (q) => {
  clearTimeout(timer);
  timer = setTimeout(async () => {
    const term = q.trim();
    let found: Option[] = [];
    if (subjectType.value === "lead") {
      const { data } = await supabase.rpc("cs_search_leads", { p_q: term });
      found = ((data ?? []) as { id: string; name: string; phone: string | null; company_name: string | null }[]).map((l) => ({
        label: label({ name: l.name, company: l.company_name, phone: l.phone }), value: l.id, name: l.company_name || l.name, phone: l.phone, address: null,
      }));
    } else {
      let query = supabase.from("customers").select("id, name, company, phone, address").eq("cs_pending", false).order("created_at", { ascending: false }).limit(20);
      if (term) query = query.or(`name.ilike.%${term}%,company.ilike.%${term}%,phone.ilike.%${term}%`);
      const { data } = await query;
      found = (data ?? []).map((c) => ({ label: label(c as never), value: c.id as string, name: (c.company as string | null) || (c.name as string), phone: c.phone as string | null, address: c.address as string | null }));
    }
    const chosen = options.value.find((o) => o.value === subjectId.value);
    options.value = chosen && !found.some((o) => o.value === chosen.value) ? [chosen, ...found] : found;
  }, 250);
});
const subject = computed(() => options.value.find((o) => o.value === subjectId.value) ?? null);

// ---- technicians
interface Technician { id: string; full_name: string | null; email: string }
const technicians = ref<Technician[]>([]);
const NO_TECH = "none";
const technicianItems = computed(() => [{ label: t("cs.workOrders.noTechnician"), value: NO_TECH }, ...technicians.value.map((u) => ({ label: u.full_name || u.email, value: u.id }))]);

// ---- maintenance: the products serviced
const products = ref<CsProduct[]>([]);
const picked = ref<Set<string>>(new Set());
const doneOpen = ref(false);
const doneProducts = ref<CsProduct[]>([]);
watch(subjectId, async (id) => {
  products.value = [];
  picked.value = new Set();
  if (kind.value !== "maintenance" || !id) return;
  const { data } = await supabase.from("customer_products").select("*").eq("customer_id", id).order("name");
  products.value = (data ?? []) as CsProduct[];
  picked.value = new Set(products.value.map((p) => p.id));
});
function togglePick(id: string) {
  const next = new Set(picked.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  picked.value = next;
}
function continueMaintenance() {
  doneProducts.value = products.value.filter((p) => picked.value.has(p.id));
  open.value = false;
  doneOpen.value = true;
}

// ---- open
async function openModal() {
  kind.value = "maintenance";
  subjectType.value = "customer";
  subjectId.value = null;
  workDate.value = today();
  mode.value = "done";
  note.value = "";
  signed.value = false;
  noSignature.value = false;
  signaturePad.value?.clear();
  options.value = [];
  open.value = true;
  search.value = " ";
  search.value = "";
  if (!technicians.value.length) {
    const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_technician", true).eq("is_active", true).order("full_name");
    technicians.value = (data ?? []) as Technician[];
  }
  technicianId.value = technicians.value.some((u) => u.id === me.value?.sub) ? (me.value?.sub as string) : null;
}

const valid = computed(
  () => !!subject.value && !!workDate.value && (mode.value === "assign" || signed.value || noSignature.value),
);

async function save() {
  const s = subject.value;
  if (!s || !valid.value || kind.value === "maintenance") return;
  saving.value = true;
  const fail = (title: string, description?: string) => {
    saving.value = false;
    toast.add({ title, description, color: "error" });
  };
  let signaturePath: string | null = null;
  if (mode.value === "done" && signed.value && !noSignature.value) {
    const blob = await signaturePad.value?.toBlob();
    if (blob) {
      const path = `work-orders/${s.value}/${Date.now()}.png`;
      const { error: uploadError } = await supabase.storage.from("visit-signatures").upload(path, blob, { contentType: "image/png" });
      if (uploadError) return fail(t("cs.maintenance.signatureFailed"), uploadError.message);
      signaturePath = path;
    }
  }
  const { error } = await supabase.from("cs_work_orders").insert({
    kind: kind.value,
    customer_id: subjectType.value === "customer" ? s.value : null,
    lead_id: subjectType.value === "lead" ? s.value : null,
    subject_name: s.name,
    subject_phone: s.phone,
    subject_address: s.address,
    work_date: workDate.value,
    technician_id: technicianId.value || null,
    status: mode.value === "assign" ? "pending" : "done",
    note: note.value.trim() || null,
    signature_path: signaturePath,
  });
  if (error) return fail(t("cs.maintenance.saveFailed"), error.message);
  saving.value = false;
  toast.add({ title: t(mode.value === "assign" ? (technicianId.value ? "cs.workOrders.assigned" : "cs.workOrders.createdPending") : "cs.workOrders.saved"), color: "success" });
  open.value = false;
  emit("saved");
}

const kindItems = computed(() => WORK_ORDER_KINDS.map((k) => ({ value: k, label: t(`cs.workOrders.kind.${k}`), icon: WORK_ORDER_ICONS[k] })));
</script>

<template>
  <div v-if="canCreate" class="flex items-center gap-2">
    <UButton icon="i-lucide-plus" size="sm" :label="t('cs.workOrders.new')" @click="openModal" />
    <UButton to="/cs/work-orders" icon="i-lucide-list" size="sm" color="neutral" variant="outline" :label="t('cs.workOrders.list')" class="hidden sm:inline-flex" />

    <UModal v-model:open="open" :title="t('cs.workOrders.new')">
      <template #body>
        <div class="space-y-4">
          <!-- the kind of work order -->
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="k in kindItems"
              :key="k.value"
              type="button"
              class="flex items-center justify-center gap-2 rounded-[12px] border px-3 py-2.5 text-sm font-medium transition-colors"
              :class="kind === k.value ? 'border-primary bg-primary text-inverted' : 'border-default bg-default text-highlighted hover:bg-elevated'"
              @click="kind = k.value"
            >
              <UIcon :name="k.icon" class="size-4" />{{ k.label }}
            </button>
          </div>

          <!-- an inspection can be for a customer or a lead -->
          <div v-if="canPickLead" class="flex gap-2">
            <button type="button" class="kords-chip" :class="subjectType === 'customer' && 'kords-chip-on'" @click="subjectType = 'customer'">{{ t("cs.workOrders.forCustomer") }}</button>
            <button type="button" class="kords-chip" :class="subjectType === 'lead' && 'kords-chip-on'" @click="subjectType = 'lead'">{{ t("cs.workOrders.forLead") }}</button>
          </div>

          <UFormField :label="subjectType === 'lead' ? t('cs.workOrders.lead') : t('cs.workOrders.customer')" required>
            <USelectMenu
              v-model="subjectId"
              v-model:search-term="search"
              :items="options"
              value-key="value"
              :ignore-filter="true"
              :icon="subjectType === 'lead' ? 'i-lucide-user-search' : 'i-lucide-user-round'"
              :placeholder="t(subjectType === 'lead' ? 'cs.workOrders.pickLead' : 'cs.workOrders.pickCustomer')"
              class="w-full"
            >
              <template #empty>{{ t("cs.workOrders.noResults") }}</template>
            </USelectMenu>
          </UFormField>

          <!-- maintenance: which products were serviced, then the done-visit form -->
          <template v-if="kind === 'maintenance'">
            <div v-if="subject" class="space-y-2">
              <p class="text-sm font-medium text-highlighted">{{ t("cs.workOrders.pickProducts") }}</p>
              <p v-if="!products.length" class="rounded-[10px] bg-muted p-3 text-sm text-muted">{{ t("cs.workOrders.noProducts") }}</p>
              <ul v-else class="divide-y divide-default overflow-hidden rounded-[10px] border border-default">
                <li v-for="p in products" :key="p.id" class="flex items-center gap-3 px-3 py-2 text-sm">
                  <UCheckbox :model-value="picked.has(p.id)" @update:model-value="togglePick(p.id)" />
                  <span class="min-w-0 flex-1 truncate">{{ p.name }}<bdi v-if="p.contract_code" dir="ltr" class="ms-1 text-xs text-muted">#{{ p.contract_code }}</bdi></span>
                </li>
              </ul>
            </div>
            <UButton :label="t('cs.workOrders.continue')" icon="i-lucide-arrow-left" trailing size="lg" block :disabled="!picked.size" @click="continueMaintenance" />
          </template>

          <!-- installation / operation / inspection: date, technician, notes and the customer's signature -->
          <template v-else>
            <div class="flex gap-2">
              <button type="button" class="kords-chip" :class="mode === 'done' && 'kords-chip-on'" @click="mode = 'done'">{{ t("cs.workOrders.modeDone") }}</button>
              <button type="button" class="kords-chip" :class="mode === 'assign' && 'kords-chip-on'" @click="mode = 'assign'">{{ t("cs.workOrders.modeAssign") }}</button>
            </div>
            <div class="grid gap-3 sm:grid-cols-2">
              <UFormField :label="mode === 'assign' ? t('cs.workOrders.plannedDate') : t('cs.workOrders.date')" required>
                <UInput v-model="workDate" type="date" class="w-full" />
              </UFormField>
              <UFormField :label="t('cs.workOrders.technician')">
                <USelect :model-value="technicianId ?? NO_TECH" :items="technicianItems" value-key="value" class="w-full" @update:model-value="(v: string) => (technicianId = v === NO_TECH ? null : v)" />
              </UFormField>
            </div>
            <UFormField :label="mode === 'assign' ? t('cs.workOrders.instructions') : t('cs.workOrders.notes')">
              <UTextarea v-model="note" :rows="3" class="w-full" />
            </UFormField>

            <p v-if="mode === 'assign'" class="flex items-start gap-2 rounded-[10px] bg-info/10 p-3 text-sm text-info">
              <UIcon name="i-lucide-bell-ring" class="mt-0.5 size-4 shrink-0" /><span>{{ technicianId ? t("cs.workOrders.assignHint") : t("cs.workOrders.assignLaterHint") }}</span>
            </p>
            <div v-else class="space-y-2 border-t border-default pt-4">
              <p class="text-sm font-medium text-highlighted">{{ t("cs.maintenance.customerSignature") }} <span class="text-error">*</span></p>
              <UCheckbox v-model="noSignature" :label="t('cs.maintenance.noOneToSign')" />
              <SignaturePad v-show="!noSignature" ref="signaturePad" v-model:signed="signed" />
            </div>

            <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
          </template>
        </div>
      </template>
    </UModal>

    <!-- the usual done-visit form for a maintenance work order -->
    <MaintenanceDoneModal v-model:open="doneOpen" :products="doneProducts" @saved="emit('saved')" />
  </div>
</template>

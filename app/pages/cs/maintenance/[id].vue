<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const route = useRoute();
const productId = route.params.id as string;

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const { stageById, dateIndex, formatDate, formatDateTime, maintenanceDue, loadAreas, loadPipelines, areaName } = useCs();

const canEdit = computed(() => hasPermission("cs_customers", "edit"));

interface LogRow {
  id: string;
  product_id: string;
  kind: "scheduled" | "rescheduled" | "done" | "cancelled" | "note" | "declined" | "resumed";
  happened_at: string;
  scheduled_for: string | null;
  done_on: string | null;
  note: string | null;
  cost: number | null;
  created_by: string | null;
}
interface Person {
  id: string;
  full_name: string | null;
  email: string;
}

await useAsyncData("cs-mrec-meta", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

const { data: product, refresh: refreshProduct, status } = await useAsyncData<CsProduct | null>(`cs-mrec-${productId}`, async () => {
  const { data, error } = await supabase.from("customer_products").select("*").eq("id", productId).maybeSingle();
  if (error) throw error;
  return (data ?? null) as CsProduct | null;
});
const { data: customer } = await useAsyncData<CsCustomer | null>(`cs-mrec-${productId}-customer`, async () => {
  if (!product.value) return null;
  const { data } = await supabase
    .from("customers")
    .select("id, name, company, phone, email, address, area_id, customer_type")
    .eq("id", product.value.customer_id)
    .maybeSingle();
  return (data ?? null) as CsCustomer | null;
});
const { data: cardData } = await useAsyncData<{ dates: CsStageDate[]; items: CsProductItem[] }>(`cs-mrec-${productId}-card`, async () => {
  const [{ data: dates }, { data: items }] = await Promise.all([
    supabase.from("customer_product_stage_dates").select("product_id, stage_id, reached_on").eq("product_id", productId),
    supabase.from("customer_product_items").select("*").eq("product_id", productId).order("sort_order"),
  ]);
  return { dates: (dates ?? []) as CsStageDate[], items: (items ?? []) as CsProductItem[] };
});
const stageDates = computed(() => dateIndex(cardData.value?.dates ?? []));

const { data: category } = await useAsyncData<{ name: string; maintenance_interval_months: number | null } | null>(
  `cs-mrec-${productId}-category`,
  async () => {
    if (!product.value?.category_id) return null;
    const { data } = await supabase
      .from("product_categories")
      .select("name, maintenance_interval_months")
      .eq("id", product.value.category_id)
      .maybeSingle();
    return data ?? null;
  },
);
const { data: people } = await useAsyncData<Person[]>(`cs-mrec-${productId}-people`, async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return data ?? [];
});
const { data: log, refresh: refreshLog } = await useAsyncData<LogRow[]>(`cs-mrec-${productId}-log`, async () => {
  const { data, error } = await supabase
    .from("product_maintenance_log")
    .select("*")
    .eq("product_id", productId)
    .order("happened_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as LogRow[];
});

function personName(id: string | null) {
  const u = id ? people.value?.find((x) => x.id === id) : null;
  return u ? u.full_name || u.email : null;
}

// ---- Where maintenance stands
const operating = computed(() => !!product.value && !!stageById(product.value.stage_id)?.is_final);
const months = computed(() => category.value?.maintenance_interval_months ?? null);
const declined = computed(() => !!product.value?.maintenance_declined_at);
const periodicDue = computed(() => (product.value && !declined.value ? maintenanceDue(product.value, months.value) : null));
const appointmentAt = computed(() => (product.value?.next_maintenance_at ? new Date(product.value.next_maintenance_at).getTime() : null));
const dueMs = computed(() => appointmentAt.value ?? (periodicDue.value ? new Date(`${periodicDue.value}T09:00:00`).getTime() : null));

const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};
const state = computed<"overdue" | "today" | "week" | "later" | "unscheduled" | "declined">(() => {
  if (declined.value) return "declined";
  if (dueMs.value === null) return "unscheduled";
  const today = startOfToday();
  if (dueMs.value < today) return "overdue";
  if (dueMs.value < today + 86_400_000) return "today";
  if (dueMs.value < today + 7 * 86_400_000) return "week";
  return "later";
});
const daysLate = computed(() => (dueMs.value === null ? 0 : Math.max(1, Math.floor((startOfToday() - dueMs.value) / 86_400_000) + 1)));
const stateColor = { overdue: "error", today: "warning", week: "info", later: "neutral", unscheduled: "neutral", declined: "error" } as const;
const stateIcon = {
  overdue: "i-lucide-triangle-alert",
  today: "i-lucide-bell-ring",
  week: "i-lucide-calendar-clock",
  later: "i-lucide-calendar-check",
  unscheduled: "i-lucide-calendar-x",
  declined: "i-lucide-ban",
} as const;

// ---- Numbers
const doneVisits = computed(() => (log.value ?? []).filter((l) => l.kind === "done"));
const totalCost = computed(() => doneVisits.value.reduce((sum, l) => sum + (l.cost ?? 0), 0));
const lastVisit = computed(() => product.value?.last_maintenance_on ?? doneVisits.value[0]?.done_on ?? null);
function money(v: number) {
  return `${v.toLocaleString("en-US")} ${t("common.currency")}`;
}

// ---- Timeline
const events = computed(() => log.value ?? []);
const eventMeta = {
  scheduled: { icon: "i-lucide-calendar-plus", color: "text-info", label: "cs.maintenance.evScheduled" },
  done: { icon: "i-lucide-circle-check", color: "text-success", label: "cs.maintenance.evDone" },
  rescheduled: { icon: "i-lucide-calendar-sync", color: "text-info", label: "cs.maintenance.evRescheduled" },
  cancelled: { icon: "i-lucide-calendar-x", color: "text-error", label: "cs.maintenance.evCancelled" },
  declined: { icon: "i-lucide-ban", color: "text-error", label: "cs.maintenance.evDeclined" },
  resumed: { icon: "i-lucide-rotate-ccw", color: "text-success", label: "cs.maintenance.evResumed" },
  note: { icon: "i-lucide-sticky-note", color: "text-muted", label: "cs.maintenance.evNote" },
} as const;

// ---- Add a note
const noteText = ref("");
const savingNote = ref(false);
async function addNote() {
  const text = noteText.value.trim();
  if (!text || !product.value) return;
  savingNote.value = true;
  const { error } = await supabase.from("product_maintenance_log").insert({ product_id: product.value.id, kind: "note", note: text });
  savingNote.value = false;
  if (error) {
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }
  noteText.value = "";
  toast.add({ title: t("cs.maintenance.noteAdded"), color: "success", duration: 1500 });
  await refreshLog();
}

// ---- Dialogs
const cancelOpen = ref(false);
const resuming = ref(false);
function openCancel() {
  cancelOpen.value = true;
}
async function resume() {
  if (!product.value) return;
  resuming.value = true;
  const { error } = await supabase.from("customer_products").update({ maintenance_declined_at: null }).eq("id", product.value.id);
  if (!error) await supabase.from("product_maintenance_log").insert({ product_id: product.value.id, kind: "resumed" });
  resuming.value = false;
  if (error) {
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.maintenance.resumed"), color: "success" });
  await onSaved();
}

const scheduleOpen = ref(false);
const doneOpen = ref(false);
function openDone() {
  doneOpen.value = true;
}
function openSchedule() {
  scheduleOpen.value = true;
}
async function onSaved() {
  await Promise.all([refreshProduct(), refreshLog()]);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('cs.maintenance.record')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            icon="i-lucide-arrow-right"
            color="neutral"
            variant="ghost"
            to="/cs/maintenance"
            :label="t('cs.maintenance.backToList')"
            class="rtl:flex-row-reverse"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <p v-else-if="!product" class="py-16 text-center text-sm text-muted">{{ t("cs.profile.notFound") }}</p>

      <div v-else class="mx-auto w-full max-w-6xl space-y-5">
        <!-- ===== Who / what ===== -->
        <div class="border border-default bg-default p-4 sm:p-5">
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div class="min-w-0 flex-1 basis-64">
              <NuxtLink v-if="customer" :to="`/cs/customers/${customer.id}`" class="text-sm text-primary hover:underline">
                {{ customerTitle(customer) }}
              </NuxtLink>
              <h2 class="mt-0.5 text-xl font-semibold text-highlighted sm:text-2xl">
                {{ product.name }}
                <bdi v-if="product.contract_code" dir="ltr" class="ms-1 text-sm font-normal text-muted">#{{ product.contract_code }}</bdi>
              </h2>
            </div>
            <div v-if="customer" class="flex flex-wrap items-center gap-2">
              <UButton v-if="customer.phone" :to="`tel:${customer.phone}`" icon="i-lucide-phone" color="neutral" variant="outline" :label="t('crm.deals.callContact')" />
              <UButton
                v-if="toWhatsAppLink(customer.phone)"
                :to="toWhatsAppLink(customer.phone)!"
                target="_blank"
                rel="noopener noreferrer"
                icon="i-simple-icons-whatsapp"
                color="neutral"
                variant="outline"
                :label="t('cs.profile.whatsapp')"
              />
              <UButton :to="`/cs/customers/${customer.id}`" icon="i-lucide-user-round" color="neutral" variant="ghost" :label="t('cs.maintenance.customerProfile')" />
            </div>
          </div>
          <dl v-if="customer" class="mt-4 grid gap-x-6 gap-y-3 border-t border-default pt-4 text-sm sm:grid-cols-3">
            <div>
              <dt class="text-xs text-muted">{{ t("common.phone") }}</dt>
              <dd class="font-medium text-highlighted"><bdi dir="ltr">{{ customer.phone || "—" }}</bdi></dd>
            </div>
            <div>
              <dt class="text-xs text-muted">{{ t("cs.customers.area") }}</dt>
              <dd class="font-medium text-highlighted">{{ areaName(customer.area_id) || "—" }}</dd>
            </div>
            <div class="sm:col-span-3">
              <dt class="text-xs text-muted">{{ t("cs.customers.address") }}</dt>
              <dd class="font-medium text-highlighted">{{ customer.address || "—" }}</dd>
            </div>
          </dl>
        </div>

        <div class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <!-- ===== Status + activity ===== -->
          <div class="min-w-0 space-y-5">
            <!-- Where maintenance stands, with the actions -->
            <section
              class="border p-4 sm:p-5"
              :class="state === 'overdue' || state === 'declined' ? 'border-error/40 bg-error/5' : state === 'today' ? 'border-warning/40 bg-warning/5' : 'border-default bg-default'"
            >
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="flex min-w-0 items-start gap-3">
                  <UIcon
                    :name="stateIcon[state]"
                    class="mt-0.5 size-6 shrink-0"
                    :class="state === 'overdue' || state === 'declined' ? 'text-error' : state === 'today' ? 'text-warning' : 'text-muted'"
                  />
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="text-xs text-muted">{{ t("cs.maintenance.next") }}</span>
                      <UBadge
                        :label="state === 'overdue' ? t('cs.maintenance.late', { days: daysLate }) : t(`cs.maintenance.${state}`)"
                        :color="stateColor[state]"
                        :variant="state === 'unscheduled' || state === 'later' ? 'outline' : 'subtle'"
                        size="sm"
                        class="cds-tag"
                      />
                    </div>
                    <div v-if="declined" class="mt-0.5">
                      <div class="text-lg font-semibold text-error">{{ t("cs.maintenance.declinedNote") }}</div>
                      <div class="text-xs text-muted">{{ t("cs.maintenance.declinedOn", { date: formatDateTime(product.maintenance_declined_at) }) }}</div>
                    </div>
                    <template v-else>
                    <div v-if="product.next_maintenance_at" class="mt-0.5 text-lg font-semibold text-highlighted">
                      {{ formatDateTime(product.next_maintenance_at) }}
                    </div>
                    <div v-else-if="periodicDue" class="mt-0.5 text-lg font-semibold text-highlighted">
                      {{ formatDate(periodicDue) }}
                      <span class="text-sm font-normal text-muted">· {{ t("cs.maintenance.periodicShort") }}</span>
                    </div>
                    <div v-else class="mt-0.5 text-sm text-muted">{{ t("cs.maintenance.notScheduled") }}</div>
                    <p v-if="product.next_maintenance_note" class="mt-1 whitespace-pre-line text-sm text-toned">{{ product.next_maintenance_note }}</p>
                    </template>
                  </div>
                </div>

                <div v-if="canEdit && operating" class="flex flex-wrap items-center gap-2">
                  <UButton v-if="declined" icon="i-lucide-rotate-ccw" :label="t('cs.maintenance.resume')" :loading="resuming" @click="resume" />
                  <template v-else>
                    <UButton v-if="product.next_maintenance_at" icon="i-lucide-check" color="success" :label="t('cs.maintenance.markDone')" @click="openDone" />
                    <UButton
                      :icon="product.next_maintenance_at ? 'i-lucide-calendar-sync' : 'i-lucide-calendar-plus'"
                      :color="product.next_maintenance_at ? 'neutral' : 'primary'"
                      :variant="product.next_maintenance_at ? 'outline' : 'solid'"
                      :label="t(product.next_maintenance_at ? 'cs.maintenance.reschedule' : 'cs.maintenance.schedule')"
                      @click="openSchedule"
                    />
                    <UButton icon="i-lucide-ban" color="error" variant="outline" :label="t('cs.maintenance.cancelAction')" @click="openCancel" />
                  </template>
                </div>
              </div>
              <p v-if="!operating" class="mt-3 text-xs text-muted">{{ t("cs.maintenance.hint") }}</p>
            </section>

            <!-- The product itself -->
            <ProductCard
              :product="product"
              :dates="stageDates"
              :items="cardData?.items ?? []"
              :category-name="category?.name ?? null"
              :sales-person-name="personName(product.sales_person_id)"
            />

            <!-- Add a note -->
            <section v-if="canEdit" class="space-y-2 border border-default bg-default p-4">
              <UTextarea v-model="noteText" :rows="2" :placeholder="t('cs.maintenance.notePlaceholder')" class="w-full" />
              <div class="flex justify-end">
                <UButton
                  icon="i-lucide-send"
                  size="sm"
                  :label="t('cs.maintenance.addNote')"
                  :loading="savingNote"
                  :disabled="!noteText.trim()"
                  @click="addNote"
                />
              </div>
            </section>

            <!-- Activity -->
            <section class="space-y-3">
              <h3 class="flex items-center gap-2 text-lg font-semibold text-highlighted">
                {{ t("cs.maintenance.activity") }}
                <UBadge :label="String(events.length)" color="neutral" variant="subtle" class="cds-tag" />
              </h3>
              <p v-if="!events.length" class="border border-dashed border-default p-8 text-center text-sm text-muted">
                {{ t("cs.maintenance.noEvents") }}
              </p>
              <ol v-else class="relative space-y-4 border-s border-default ps-6">
                <li v-for="e in events" :key="e.id" class="relative">
                  <span
                    class="absolute -start-[2.15rem] top-0.5 flex size-6 items-center justify-center rounded-full border border-default bg-default"
                    :class="eventMeta[e.kind].color"
                  >
                    <UIcon :name="eventMeta[e.kind].icon" class="size-3.5" />
                  </span>
                  <div class="border border-default bg-default p-3 text-sm">
                    <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
                      <span class="font-medium text-highlighted">{{ t(eventMeta[e.kind].label) }}</span>
                      <span class="text-xs text-muted">
                        {{ formatDateTime(e.happened_at) }}<template v-if="personName(e.created_by)"> · {{ personName(e.created_by) }}</template>
                      </span>
                    </div>
                    <p v-if="e.kind === 'done' && e.done_on" class="mt-1 text-toned">
                      {{ t("cs.maintenance.doneOn") }}: <span class="font-medium text-highlighted">{{ formatDate(e.done_on) }}</span>
                      <template v-if="e.cost"> · {{ t("cs.maintenance.cost") }}: <span class="font-medium text-highlighted">{{ money(e.cost) }}</span></template>
                    </p>
                    <p v-else-if="(e.kind === 'scheduled' || e.kind === 'cancelled') && e.scheduled_for" class="mt-1 text-toned">
                      {{ t("cs.maintenance.forTime", { when: formatDateTime(e.scheduled_for) }) }}
                    </p>
                    <p v-if="e.note" class="mt-1 whitespace-pre-line text-toned">{{ e.note }}</p>
                  </div>
                </li>
              </ol>
            </section>
          </div>

          <!-- ===== Summary ===== -->
          <aside class="space-y-5 lg:sticky lg:top-0">
            <div class="grid grid-cols-2 gap-3">
              <div class="border border-default bg-default p-3">
                <div class="text-xs text-muted">{{ t("cs.maintenance.visitsDone") }}</div>
                <div class="mt-1 text-2xl font-bold" :class="doneVisits.length ? 'text-success' : 'text-highlighted'">{{ doneVisits.length }}</div>
              </div>
              <div class="border border-default bg-default p-3">
                <div class="text-xs text-muted">{{ t("cs.maintenance.totalCost") }}</div>
                <div class="mt-1 text-lg font-bold text-highlighted">{{ totalCost ? money(totalCost) : "—" }}</div>
              </div>
            </div>

            <section class="border border-default bg-default">
              <h3 class="border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">{{ t("cs.maintenance.schedule2") }}</h3>
              <dl class="divide-y divide-default text-sm">
                <div class="flex justify-between gap-3 px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.maintenance.operationDate") }}</dt>
                  <dd class="font-medium text-highlighted">{{ formatDate(product.operation_date) }}</dd>
                </div>
                <div class="flex justify-between gap-3 px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.maintenance.interval") }}</dt>
                  <dd class="font-medium text-highlighted">{{ months ? t("cs.maintenance.everyMonths", { months }) : "—" }}</dd>
                </div>
                <div class="flex justify-between gap-3 px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.maintenance.lastDone") }}</dt>
                  <dd class="font-medium text-highlighted">{{ lastVisit ? formatDate(lastVisit) : "—" }}</dd>
                </div>
                <div class="flex justify-between gap-3 px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.maintenance.periodicShort") }}</dt>
                  <dd class="font-medium text-highlighted">{{ periodicDue ? formatDate(periodicDue) : "—" }}</dd>
                </div>
              </dl>
            </section>

            <section class="border border-default bg-default">
              <h3 class="border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">{{ t("cs.maintenance.contract") }}</h3>
              <dl class="divide-y divide-default text-sm">
                <div class="flex justify-between gap-3 px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.profile.contractDate") }}</dt>
                  <dd class="font-medium text-highlighted">{{ formatDate(product.contract_date) }}</dd>
                </div>
                <div class="flex justify-between gap-3 px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.profile.salesPerson") }}</dt>
                  <dd class="font-medium text-highlighted">{{ personName(product.sales_person_id) || "—" }}</dd>
                </div>
                <div v-if="product.warranty_details" class="px-4 py-2.5">
                  <dt class="text-muted">{{ t("cs.profile.warrantyDetails") }}</dt>
                  <dd class="mt-0.5 whitespace-pre-line text-toned">{{ product.warranty_details }}</dd>
                </div>
              </dl>
            </section>
          </aside>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <MaintenanceModal v-model:open="scheduleOpen" :product="product ?? null" @saved="onSaved" />
  <MaintenanceDoneModal v-model:open="doneOpen" :product="product ?? null" @saved="onSaved" />
  <MaintenanceCancelModal v-model:open="cancelOpen" :product="product ?? null" @saved="onSaved" />
</template>

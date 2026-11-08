<script setup lang="ts">
// Settings -> Leave: everything about leave that can change — the delay permission rule, the weekend
// and when the credit year starts, the default hours, the vacation types with their yearly credit,
// and each person's own attendance / exit times and credits.
import type { LeavePolicy, LeaveType } from "~/composables/useLeave";

definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { loadTypes, loadPolicy } = useLeave();

const policy = reactive<LeavePolicy>({ delay_max_hours: 2, delay_per_month: 3, weekend_days: [5, 6], year_start_month: 1, default_start: "09:00", default_end: "17:00" });
const { data: loaded } = await useAsyncData("admin-leave-policy", async () => ({ policy: await loadPolicy() }));
Object.assign(policy, loaded.value?.policy);
const savingPolicy = ref(false);

const DAYS = [0, 1, 2, 3, 4, 5, 6];
function toggleDay(d: number, on: boolean) {
  policy.weekend_days = on ? [...new Set([...policy.weekend_days, d])].sort() : policy.weekend_days.filter((x) => x !== d);
}
const monthItems = computed(() => Array.from({ length: 12 }, (_, i) => ({ label: t(`leave.months.${i + 1}`), value: i + 1 })));
async function savePolicy() {
  savingPolicy.value = true;
  const { error } = await supabase.from("leave_policy").update({ ...policy }).eq("id", 1);
  savingPolicy.value = false;
  if (error) toast.add({ title: t("leave.settings.saveFailed"), description: error.message, color: "error" });
  else toast.add({ title: t("leave.settings.saved"), color: "success" });
}

// ---- Types
const { data: typesData, refresh: refreshTypes } = await useAsyncData<LeaveType[]>("admin-leave-types", () => loadTypes(false));
const types = ref<LeaveType[]>([]);
watch(typesData, (v) => (types.value = (v ?? []).map((x) => ({ ...x }))), { immediate: true });
const newType = reactive({ name: "", credit: 0, file: false });
async function saveType(ty: LeaveType) {
  const { error } = await supabase.from("leave_types").update({
    name: ty.name.trim(), yearly_credit: ty.yearly_credit, requires_attachment: ty.requires_attachment, is_active: ty.is_active,
  }).eq("id", ty.id);
  if (error) toast.add({ title: t("leave.settings.saveFailed"), description: error.message, color: "error" });
  else toast.add({ title: t("leave.settings.saved"), color: "success" });
}
async function addType() {
  const name = newType.name.trim();
  if (!name) return;
  const { error } = await supabase.from("leave_types").insert({ name, yearly_credit: newType.credit, requires_attachment: newType.file, sort_order: types.value.length });
  if (error) {
    toast.add({ title: t("leave.settings.saveFailed"), description: error.message, color: "error" });
    return;
  }
  Object.assign(newType, { name: "", credit: 0, file: false });
  await refreshTypes();
}

// ---- People: their own hours and credits (blank: the defaults)
interface Person { id: string; full_name: string | null; email: string; start: string; end: string; credits: Record<string, number | null>; approver: string | null }
const { data: peopleData, refresh: refreshPeople } = await useAsyncData<Person[]>("admin-leave-people", async () => {
  const [profiles, schedules, credits, routes] = await Promise.all([
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true).eq("can_login", true).order("full_name"),
    supabase.from("user_work_schedules").select("profile_id, start_time, end_time"),
    supabase.from("leave_user_credits").select("profile_id, leave_type_id, credit"),
    supabase.from("leave_approval_routes").select("profile_id, approver_id"),
  ]);
  return (profiles.data ?? []).map((p) => {
    const sc = schedules.data?.find((s) => s.profile_id === p.id);
    const cr: Record<string, number | null> = {};
    for (const c of credits.data ?? []) if (c.profile_id === p.id) cr[c.leave_type_id] = Number(c.credit);
    return { ...p, start: sc?.start_time?.slice(0, 5) ?? "", end: sc?.end_time?.slice(0, 5) ?? "", credits: cr, approver: routes.data?.find((r) => r.profile_id === p.id)?.approver_id ?? null };
  });
});
const people = ref<Person[]>([]);
watch(peopleData, (v) => (people.value = (v ?? []).map((p) => ({ ...p, credits: { ...p.credits } }))), { immediate: true });
const search = ref("");
const shownPeople = computed(() => {
  const q = search.value.trim().toLowerCase();
  return q ? people.value.filter((p) => `${p.full_name ?? ""} ${p.email}`.toLowerCase().includes(q)) : people.value;
});
// who can be set as an approver: any active person
const approverItems = computed(() => [
  { label: t("leave.settings.noApprover"), value: null as string | null },
  ...people.value.map((x) => ({ label: x.full_name || x.email, value: x.id as string | null })),
]);
const savingPerson = ref<string | null>(null);
async function savePerson(p: Person) {
  savingPerson.value = p.id;
  let failure: string | null = null;
  // hours: both set, or neither (the defaults)
  if (p.start && p.end) {
    const { error } = await supabase.from("user_work_schedules").upsert({ profile_id: p.id, start_time: p.start, end_time: p.end }, { onConflict: "profile_id" });
    failure = error?.message ?? null;
  } else {
    const { error } = await supabase.from("user_work_schedules").delete().eq("profile_id", p.id);
    failure = error?.message ?? null;
  }
  // who approves this person's requests (none: they pick one themselves)
  {
    const { error } = p.approver
      ? await supabase.from("leave_approval_routes").upsert({ profile_id: p.id, approver_id: p.approver }, { onConflict: "profile_id" })
      : await supabase.from("leave_approval_routes").delete().eq("profile_id", p.id);
    failure = failure ?? error?.message ?? null;
  }
  for (const ty of types.value) {
    const v = p.credits[ty.id];
    const { error } = v === null || v === undefined
      ? await supabase.from("leave_user_credits").delete().eq("profile_id", p.id).eq("leave_type_id", ty.id)
      : await supabase.from("leave_user_credits").upsert({ profile_id: p.id, leave_type_id: ty.id, credit: v }, { onConflict: "profile_id,leave_type_id" });
    failure = failure ?? error?.message ?? null;
  }
  savingPerson.value = null;
  if (failure) toast.add({ title: t("leave.settings.saveFailed"), description: failure, color: "error" });
  else toast.add({ title: t("leave.settings.saved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="t('admin.leave.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="mx-auto max-w-5xl space-y-6">
        <!-- Rules -->
        <section class="kords-card space-y-4 p-4">
          <h3 class="text-base font-semibold text-highlighted">{{ t("leave.settings.rules") }}</h3>
          <div class="grid gap-4 sm:grid-cols-3">
            <UFormField :label="t('leave.settings.delayHours')" :help="t('leave.settings.delayHoursHint')">
              <UInputNumber v-model="policy.delay_max_hours" :min="0.5" :step="0.5" class="w-full" />
            </UFormField>
            <UFormField :label="t('leave.settings.delayPerMonth')" :help="t('leave.settings.delayPerMonthHint')">
              <UInputNumber v-model="policy.delay_per_month" :min="0" class="w-full" />
            </UFormField>
            <UFormField :label="t('leave.settings.yearStart')" :help="t('leave.settings.yearStartHint')">
              <USelect v-model="policy.year_start_month" :items="monthItems" value-key="value" class="w-full" />
            </UFormField>
            <UFormField :label="t('leave.settings.defaultStart')">
              <UInput v-model="policy.default_start" type="time" class="w-full" />
            </UFormField>
            <UFormField :label="t('leave.settings.defaultEnd')">
              <UInput v-model="policy.default_end" type="time" class="w-full" />
            </UFormField>
          </div>
          <UFormField :label="t('leave.settings.weekend')" :help="t('leave.settings.weekendHint')">
            <div class="flex flex-wrap gap-x-4 gap-y-2">
              <UCheckbox v-for="d in DAYS" :key="d" :model-value="policy.weekend_days.includes(d)" :label="t(`leave.days.${d}`)" @update:model-value="(v: boolean | 'indeterminate') => toggleDay(d, v === true)" />
            </div>
          </UFormField>
          <UButton :label="t('common.save')" :loading="savingPolicy" @click="savePolicy" />
        </section>

        <!-- Vacation types -->
        <section class="kords-card space-y-3 p-4">
          <h3 class="text-base font-semibold text-highlighted">{{ t("leave.settings.types") }}</h3>
          <p class="text-xs text-muted">{{ t("leave.settings.typesHint") }}</p>
          <ul class="space-y-2">
            <li v-for="ty in types" :key="ty.id" class="flex flex-wrap items-end gap-3 rounded-[10px] border border-default p-3">
              <UFormField :label="t('leave.settings.typeName')" class="min-w-40 flex-1"><UInput v-model="ty.name" class="w-full" /></UFormField>
              <UFormField :label="t('leave.settings.credit')"><UInputNumber v-model="ty.yearly_credit" :min="0" class="w-32" /></UFormField>
              <UCheckbox v-model="ty.requires_attachment" :label="t('leave.settings.requiresFile')" class="pb-2" />
              <UCheckbox v-model="ty.is_active" :label="t('leave.settings.active')" class="pb-2" />
              <UButton :label="t('common.save')" color="neutral" variant="outline" @click="saveType(ty)" />
            </li>
          </ul>
          <div class="flex flex-wrap items-end gap-3 border-t border-default pt-3">
            <UFormField :label="t('leave.settings.newType')" class="min-w-40 flex-1"><UInput v-model="newType.name" class="w-full" /></UFormField>
            <UFormField :label="t('leave.settings.credit')"><UInputNumber v-model="newType.credit" :min="0" class="w-32" /></UFormField>
            <UCheckbox v-model="newType.file" :label="t('leave.settings.requiresFile')" class="pb-2" />
            <UButton icon="i-lucide-plus" :label="t('leave.settings.add')" :disabled="!newType.name.trim()" @click="addType" />
          </div>
        </section>

        <!-- Each person's hours and credits -->
        <section class="kords-card space-y-3 p-4">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h3 class="text-base font-semibold text-highlighted">{{ t("leave.settings.people") }}</h3>
            <UInput v-model="search" icon="i-lucide-search" :placeholder="t('common.search')" class="w-56" />
          </div>
          <p class="text-xs text-muted">{{ t("leave.settings.peopleHint", { start: policy.default_start, end: policy.default_end }) }}</p>
          <div class="overflow-x-auto">
            <table class="w-full min-w-[40rem] text-sm">
              <thead>
                <tr class="border-b border-default text-xs text-muted">
                  <th class="px-3 py-2 text-start font-medium">{{ t("leave.employee") }}</th>
                  <th class="px-3 py-2 text-start font-medium">{{ t("leave.settings.approver") }}</th>
                  <th class="px-3 py-2 text-start font-medium">{{ t("leave.settings.attend") }}</th>
                  <th class="px-3 py-2 text-start font-medium">{{ t("leave.settings.exit") }}</th>
                  <th v-for="ty in types.filter((x) => x.is_active)" :key="ty.id" class="px-3 py-2 text-start font-medium">{{ ty.name }}</th>
                  <th class="w-20 px-3 py-2" />
                </tr>
              </thead>
              <tbody class="divide-y divide-default">
                <tr v-for="p in shownPeople" :key="p.id">
                  <td class="px-3 py-2 font-medium text-highlighted">{{ p.full_name || p.email }}</td>
                  <td class="px-3 py-2">
                    <USelect v-model="p.approver" :items="approverItems.filter((o) => o.value !== p.id)" value-key="value" size="sm" class="w-44" />
                  </td>
                  <td class="px-3 py-2"><UInput v-model="p.start" type="time" size="sm" class="w-28" /></td>
                  <td class="px-3 py-2"><UInput v-model="p.end" type="time" size="sm" class="w-28" /></td>
                  <td v-for="ty in types.filter((x) => x.is_active)" :key="ty.id" class="px-3 py-2">
                    <UInputNumber :model-value="p.credits[ty.id] ?? undefined" :min="0" size="sm" :placeholder="String(ty.yearly_credit)" class="w-24" @update:model-value="(v: number | null | undefined) => (p.credits[ty.id] = v ?? null)" />
                  </td>
                  <td class="px-3 py-2 text-end"><UButton size="xs" color="neutral" variant="outline" :label="t('common.save')" :loading="savingPerson === p.id" @click="savePerson(p)" /></td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </template>
  </UDashboardPanel>
</template>

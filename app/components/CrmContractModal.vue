<script setup lang="ts">
// A new contract from the CRM's contracts page, with everything a won deal records: the customer, the code and
// date, the value, the contract file, the products bought (warranty, payment, salesperson, notes) and, if there
// is one, the deal it belongs to.
const props = defineProps<{ takenDealIds: string[]; customerId?: string; customerLabel?: string }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();

const customerId = ref<string | null>(null);
const dealId = ref<string | null>(null);
// the contract itself and its products: the same form as when a deal is won
const draft = ref<ContractDraft>(newContractDraft());
const saving = ref(false);

const todayIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

// the customer: found by name, company or phone as you type
interface Option { label: string; value: string }
const customerOptions = ref<Option[]>([]);
const customerSearch = ref("");
const label = (c: { name: string; company: string | null; phone: string | null }) => [c.company, c.name, c.phone].filter(Boolean).join(" · ");
let timer: ReturnType<typeof setTimeout> | undefined;
watch(customerSearch, (q) => {
  clearTimeout(timer);
  timer = setTimeout(async () => {
    const term = q.trim();
    let query = supabase.from("customers").select("id, name, company, phone").order("created_at", { ascending: false }).limit(20);
    // leads (contacts) not yet customers: choosing one turns it into a customer when the contract is saved
    let leadQuery = supabase.from("leads").select("id, name, company_name, phone").is("customer_id", null).neq("status", "converted").order("created_at", { ascending: false }).limit(10);
    if (term) {
      query = query.or(`name.ilike.%${term}%,company.ilike.%${term}%,phone.ilike.%${term}%`);
      leadQuery = leadQuery.or(`name.ilike.%${term}%,company_name.ilike.%${term}%,phone.ilike.%${term}%`);
    }
    const [{ data }, { data: leadRows }] = await Promise.all([query, leadQuery]);
    const found = [
      ...(data ?? []).map((c) => ({ label: label(c as never), value: `c:${c.id}` })),
      ...(leadRows ?? []).map((l) => ({ label: `${label({ name: l.name as string, company: l.company_name as string | null, phone: l.phone as string | null })} · ${t("crm.contracts.leadTag")}`, value: `l:${l.id}` })),
    ];
    const chosen = customerOptions.value.find((o) => o.value === customerId.value);
    customerOptions.value = chosen && !found.some((o) => o.value === chosen.value) ? [chosen, ...found] : found;
  }, 250);
});

// a linked deal fills the value and the sales person when they are still empty
watch(dealId, async (id) => {
  if (!id) return;
  const { data } = await supabase.from("deals").select("value, assigned_to, title").eq("id", id).maybeSingle();
  if (!data) return;
  if (draft.value.value === null && data.value !== null) draft.value.value = Number(data.value);
  if (data.assigned_to) draft.value.salesPersonId = data.assigned_to as string;
  const first = draft.value.products[0];
  if (first && !first.name.trim() && data.title) first.name = data.title as string;
});

// the chosen customer's deals that have no contract yet
const dealOptions = ref<Option[]>([]);
watch(customerId, async (id) => {
  dealId.value = null;
  dealOptions.value = [];
  if (!id) return;
  const col = id.startsWith("l:") ? "lead_id" : "customer_id";
  const { data } = await supabase.from("deals").select("id, title").eq(col, id.slice(2)).order("created_at", { ascending: false });
  dealOptions.value = (data ?? []).filter((d) => !props.takenDealIds.includes(d.id as string)).map((d) => ({ label: (d.title as string) || "—", value: d.id as string }));
});

watch(open, (isOpen) => {
  if (!isOpen) return;
  customerId.value = null;
  dealId.value = null;
  draft.value = newContractDraft({ signedOn: todayIso(), salesPersonId: (me.value?.sub as string | undefined) ?? null });
  customerSearch.value = "";
  customerOptions.value = [];
  // the latest customers, to start the list
  customerSearch.value = " ";
  customerSearch.value = "";
  // opened from a customer's own page: that customer is already chosen
  if (props.customerId) {
    customerOptions.value = [{ label: props.customerLabel || "—", value: `c:${props.customerId}` }];
    customerId.value = `c:${props.customerId}`;
  }
});

const valid = computed(() => !!customerId.value && contractDraftValid(draft.value));
async function save() {
  if (!valid.value) return;
  saving.value = true;
  // a lead is turned into a customer first (the contract belongs to a customer); if the contract then fails,
  // the chosen entry becomes that customer, so trying again does not convert the lead twice
  let customer = customerId.value!;
  if (customer.startsWith("l:")) {
    const leadId = customer.slice(2);
    const { data: newCustomer, error: convertError } = await supabase.rpc("crm_convert_lead", { p_lead_id: leadId, p_pending: true });
    if (convertError || !newCustomer) {
      saving.value = false;
      toast.add({ title: t("crm.contracts.convertFailed"), description: convertError?.message, color: "error" });
      return;
    }
    // the deal chosen for the contract goes with the lead to its new customer
    if (dealId.value) await supabase.from("deals").update({ customer_id: newCustomer as string }).eq("id", dealId.value);
    const chosen = customerOptions.value.find((o) => o.value === customer);
    customer = `c:${newCustomer}`;
    customerOptions.value = [{ label: (chosen?.label ?? "").replace(/ · [^·]*$/, ""), value: customer }, ...customerOptions.value.filter((o) => o.value !== chosen?.value)];
    customerId.value = customer;
  }
  const { error } = await saveContractDraft(supabase, { customerId: customer.slice(2), linkDealId: dealId.value, draft: draft.value });
  saving.value = false;
  if (error) {
    toast.add({ title: t("crm.contracts.createFailed"), description: error, color: "error" });
    return;
  }
  toast.add({ title: t("crm.contracts.created"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('crm.contracts.new')" :ui="{ content: 'max-w-3xl' }">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('crm.contracts.customer')" required>
          <USelectMenu
            v-model="customerId"
            v-model:search-term="customerSearch"
            :items="customerOptions"
            value-key="value"
            :ignore-filter="true"
            icon="i-lucide-user-round"
            :placeholder="t('crm.contracts.pickCustomer')"
            :disabled="!!props.customerId"
            class="w-full"
          >
            <template #empty>{{ t("crm.contracts.noCustomers") }}</template>
          </USelectMenu>
        </UFormField>
        <UFormField v-if="dealOptions.length" :label="t('crm.contracts.deal')" :help="t('crm.contracts.dealHint')">
          <USelect v-model="dealId" :items="dealOptions" value-key="value" icon="i-lucide-handshake" :placeholder="t('crm.contracts.noDeal')" class="w-full" />
          <UButton v-if="dealId" size="xs" color="neutral" variant="link" :label="t('crm.contracts.clearDeal')" class="mt-1 px-0" @click="dealId = null" />
        </UFormField>
        <div class="border-t border-default pt-4">
          <ContractForm v-model="draft" />
        </div>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>

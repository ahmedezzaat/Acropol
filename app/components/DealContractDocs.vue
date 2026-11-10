<script setup lang="ts">
// In a deal's Files tab, section "العقد": the printed contracts made for this deal (before or after it is won), and
// the button to make a new one. The values start from the deal and the customer (or lead) it belongs to.
const props = defineProps<{
  dealId: string;
  deal: { title: string; value: number | null; customer_id: string | null; lead_id: string | null };
  canEdit: boolean;
}>();

const supabase = useSupabaseClient();
const { t } = useI18n();
const { formatDate } = useCs();

interface DocRow { id: string; template_key: string; year: number; seq: number; doc_date: string; variables: ContractDocVars; created_at: string }
const { data: docs, refresh } = await useAsyncData<DocRow[]>(`deal-contract-docs-${props.dealId}`, async () => {
  const { data } = await supabase.from("contract_documents").select("id, template_key, year, seq, doc_date, variables, created_at").eq("deal_id", props.dealId).order("created_at", { ascending: false });
  return (data ?? []) as unknown as DocRow[];
});

// who the contract is for: the customer of the deal, else its lead
const { data: party } = await useAsyncData(`deal-contract-party-${props.dealId}`, async () => {
  if (props.deal.customer_id) {
    const { data } = await supabase.from("customers").select("name, company, phone, address").eq("id", props.deal.customer_id).maybeSingle();
    if (data) return { name: (data.name as string) || (data.company as string) || "", phone: (data.phone as string) ?? "", address: (data.address as string) ?? "" };
  }
  if (props.deal.lead_id) {
    const { data } = await supabase.from("leads").select("name, company_name, phone").eq("id", props.deal.lead_id).maybeSingle();
    if (data) return { name: (data.name as string) || (data.company_name as string) || "", phone: (data.phone as string) ?? "", address: "" };
  }
  return { name: "", phone: "", address: "" };
});

// one template for now (heaters); with more, the user picks the one that fits what the deal is for
const templateKey = ref(contractTemplates[0]!.key);
const tpl = computed(() => templateByKey(templateKey.value)!);
const templateItems = computed(() => contractTemplates.map((x) => ({ label: t(`crm.contracts.doc.template.${x.key}`), value: x.key })));
const defaults = computed(() => tpl.value.defaults({ customerName: party.value?.name ?? "", address: party.value?.address ?? "", phone: party.value?.phone ?? "", date: new Date().toISOString().slice(0, 10), value: props.deal.value, count: 1 }));

const refOf = (d: DocRow) => {
  const x = templateByKey(d.template_key);
  return x ? contractRef(x.prefix, d.year, d.seq) : `${d.year} - ${d.seq}`;
};
const open = ref(false);
const editing = ref<DocRow | null>(null);
function newDoc() {
  editing.value = null;
  open.value = true;
}
function editDoc(d: DocRow) {
  editing.value = d;
  open.value = true;
}
async function onSaved(id: string) {
  await refresh();
  await navigateTo(`/print/contract/${id}`);
}
</script>

<template>
  <div class="space-y-2">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="text-xs text-muted">{{ t("crm.contracts.doc.fromDealHint") }}</p>
      <div v-if="canEdit" class="flex items-center gap-2">
        <USelect v-if="templateItems.length > 1" v-model="templateKey" :items="templateItems" value-key="value" size="xs" class="w-40" />
        <UButton size="xs" icon="i-lucide-file-plus" :label="t('crm.contracts.doc.new')" @click="newDoc" />
      </div>
    </div>
    <article v-for="d in docs" :key="d.id" class="kords-card flex flex-wrap items-center justify-between gap-3 p-3">
      <div class="flex min-w-0 items-center gap-3">
        <span class="flex size-9 shrink-0 items-center justify-center rounded-[10px] bg-primary/10 text-primary"><UIcon name="i-lucide-file-signature" class="size-5" /></span>
        <div class="min-w-0">
          <p class="text-sm font-medium text-highlighted"><bdi dir="ltr">{{ refOf(d) }}</bdi></p>
          <p class="truncate text-xs text-muted">{{ formatDate(d.doc_date) }} · {{ d.variables.count }} × {{ d.variables.capacity }} {{ t("crm.contracts.doc.litre") }} · {{ d.variables.ownerName }}</p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <UButton :to="`/print/contract/${d.id}`" icon="i-lucide-file-down" size="xs" :label="t('crm.contracts.doc.open')" />
        <UButton v-if="canEdit" icon="i-lucide-pencil" size="xs" color="neutral" variant="outline" :label="t('crm.contracts.doc.editValues')" @click="editDoc(d)" />
      </div>
    </article>
    <CrmContractDocModal
      v-if="canEdit"
      v-model:open="open"
      :deal-id="dealId"
      :template="editing?.template_key ?? templateKey"
      :defaults="editing ? editing.variables : defaults"
      :document="editing ? { id: editing.id, ref: refOf(editing), vars: editing.variables } : null"
      @saved="onSaved"
    />
  </div>
</template>

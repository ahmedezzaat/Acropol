<script setup lang="ts">
// Give a customer to a Customer Service agent. The list holds only the people who
// work in the module: administrators and users whose role has at least one
// Customer Service permission.
const props = defineProps<{ customerId: string; currentAgentId: string | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const agents = ref<{ id: string; full_name: string | null; email: string }[]>([]);
const agentId = ref<string | null>(null);
const loading = ref(false);
const saving = ref(false);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  agentId.value = props.currentAgentId;
  loading.value = true;
  const { data, error } = await supabase.rpc("cs_assignable_agents");
  loading.value = false;
  if (error) {
    toast.add({ title: t("cs.customers.assignFailed"), description: error.message, color: "error" });
    return;
  }
  agents.value = data ?? [];
});

const items = computed(() => [
  { label: t("cs.customers.noAgent"), value: null as string | null },
  ...agents.value.map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);

async function save() {
  saving.value = true;
  const { error } = await supabase.from("customers").update({ cs_agent_id: agentId.value }).eq("id", props.customerId);
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.customers.assignFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.customers.assigned"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.customers.assignTitle')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.customers.assignHint") }}</p>
        <UFormField :label="t('cs.customers.agent')">
          <USelectMenu
            v-model="agentId"
            :items="items"
            value-key="value"
            :loading="loading"
            searchable
            icon="i-lucide-user-round"
            class="w-full"
          />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="loading || agentId === props.currentAgentId" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>

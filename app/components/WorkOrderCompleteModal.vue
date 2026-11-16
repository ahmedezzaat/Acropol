<script setup lang="ts">
// A pending installation / operation / inspection work order is done: the date, the technician's notes and the
// customer's signature (or a tick that nobody was there to sign).
const props = defineProps<{ order: { id: string; kind: SimpleWorkOrderKind; subject_name: string; note: string | null } | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const doneOn = ref("");
const note = ref("");
const signed = ref(false);
const noSignature = ref(false);
const signaturePad = ref<{ toBlob: () => Promise<Blob | null>; clear: () => void } | null>(null);
const saving = ref(false);

watch(open, (isOpen) => {
  if (!isOpen) return;
  doneOn.value = new Date().toISOString().slice(0, 10);
  note.value = "";
  signed.value = false;
  noSignature.value = false;
  signaturePad.value?.clear();
});

const valid = computed(() => !!props.order && !!doneOn.value && (signed.value || noSignature.value));

async function save() {
  const o = props.order;
  if (!o || !valid.value) return;
  saving.value = true;
  const fail = (title: string, description?: string) => {
    saving.value = false;
    toast.add({ title, description, color: "error" });
  };
  let signaturePath: string | null = null;
  if (signed.value && !noSignature.value) {
    const blob = await signaturePad.value?.toBlob();
    if (blob) {
      const path = `work-orders/${o.id}/${Date.now()}.png`;
      const { error: uploadError } = await supabase.storage.from("visit-signatures").upload(path, blob, { contentType: "image/png" });
      if (uploadError) return fail(t("cs.maintenance.signatureFailed"), uploadError.message);
      signaturePath = path;
    }
  }
  const { error } = await supabase.rpc("cs_complete_work_order", { p_id: o.id, p_done_on: doneOn.value, p_note: note.value, p_signature_path: signaturePath });
  if (error) return fail(t("cs.maintenance.saveFailed"), error.message);
  saving.value = false;
  toast.add({ title: t("cs.workOrders.doneSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.workOrders.markDone')">
    <template #body>
      <div v-if="order" class="space-y-4">
        <div class="space-y-1">
          <p class="flex flex-wrap items-center gap-2 text-sm font-semibold text-highlighted">
            <KBadge :label="t(`cs.workOrders.kind.${order.kind}`)" :tone="WORK_ORDER_TONES[order.kind]" :icon="WORK_ORDER_ICONS[order.kind]" />{{ order.subject_name }}
          </p>
          <p v-if="order.note" class="whitespace-pre-line rounded-[10px] bg-muted p-3 text-sm text-toned">{{ order.note }}</p>
        </div>
        <UFormField :label="t('cs.workOrders.doneOn')" required>
          <UInput v-model="doneOn" type="date" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.workOrders.doneNote')">
          <UTextarea v-model="note" :rows="3" class="w-full" />
        </UFormField>
        <div class="space-y-2 border-t border-default pt-4">
          <p class="text-sm font-medium text-highlighted">{{ t("cs.maintenance.customerSignature") }} <span class="text-error">*</span></p>
          <UCheckbox v-model="noSignature" :label="t('cs.maintenance.noOneToSign')" />
          <SignaturePad v-show="!noSignature" ref="signaturePad" v-model:signed="signed" />
        </div>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>

<script setup lang="ts">
// The customer's tax card (البطاقة الضريبية). Shown when the customer's category asks for it (or when a card is already
// there). Two ways to use it:
//  - in a form: the person picks the files (v-model:files); the form uploads them with the customer when it is saved
//    (useTaxCard().uploadTaxCards), and `ok` says whether the requirement is met (a card on file or one picked);
//  - `immediate`: on a profile, picking files uploads them straight away.
const files = defineModel<File[]>("files", { default: () => [] });
const ok = defineModel<boolean>("ok", { default: true });
const props = defineProps<{ customerId?: string | null; categoryId: string | null; immediate?: boolean; canManage?: boolean }>();
const emit = defineEmits<{ changed: [] }>();

const toast = useToast();
const { t } = useI18n();
const { categories, loadCategories } = useCustomerCategories();
const { listTaxCards, uploadTaxCards, removeTaxCard, downloadTaxCard } = useTaxCard();
loadCategories();

const required = computed(() => !!props.categoryId && !!categories.value.find((c) => c.id === props.categoryId)?.requires_tax_card);
const existing = ref<TaxCardFile[]>([]);
async function reload() {
  existing.value = props.customerId ? await listTaxCards(props.customerId) : [];
}
watch(() => props.customerId, reload, { immediate: true });

const show = computed(() => required.value || existing.value.length > 0);
// the requirement is met by a card on file or files picked
watchEffect(() => {
  ok.value = !required.value || existing.value.length > 0 || files.value.length > 0;
});

const uploading = ref(false);
const picker = ref<HTMLInputElement | null>(null);
async function onPick(e: Event) {
  const input = e.target as HTMLInputElement;
  const picked = Array.from(input.files ?? []);
  input.value = "";
  if (!picked.length || !props.customerId) return;
  uploading.value = true;
  const error = await uploadTaxCards(props.customerId, picked);
  uploading.value = false;
  if (error) {
    toast.add({ title: t("taxCard.uploadFailed"), description: error, color: "error" });
    return;
  }
  toast.add({ title: t("taxCard.uploaded"), color: "success" });
  await reload();
  emit("changed");
}

// removing a file takes a second click to confirm
const confirmId = ref<string | null>(null);
async function onRemove(f: TaxCardFile) {
  if (confirmId.value !== f.id) {
    confirmId.value = f.id;
    return;
  }
  confirmId.value = null;
  const error = await removeTaxCard(f);
  if (error) {
    toast.add({ title: t("taxCard.removeFailed"), description: error, color: "error" });
    return;
  }
  await reload();
  emit("changed");
}
async function onDownload(f: TaxCardFile) {
  const error = await downloadTaxCard(f);
  if (error) toast.add({ title: t("taxCard.downloadFailed"), description: error, color: "error" });
}
</script>

<template>
  <div v-if="show" class="space-y-2 rounded-[10px] border p-3" :class="required && !ok ? 'border-error/50 bg-error/5' : 'border-default'">
    <p class="flex items-center gap-1.5 text-sm font-semibold text-highlighted">
      <UIcon name="i-lucide-file-badge" class="size-4 text-primary" />{{ t("taxCard.title") }}<span v-if="required" class="text-error">*</span>
    </p>
    <ul v-if="existing.length" class="space-y-1.5">
      <li v-for="f in existing" :key="f.id" class="flex items-center gap-2 rounded-[8px] bg-muted px-3 py-1.5 text-sm">
        <UIcon name="i-lucide-paperclip" class="size-4 shrink-0 text-primary" />
        <button type="button" class="min-w-0 flex-1 truncate text-start hover:underline" @click="onDownload(f)"><bdi>{{ f.file_name }}</bdi></button>
        <UButton icon="i-lucide-download" size="xs" color="neutral" variant="ghost" :aria-label="t('files.open')" @click="onDownload(f)" />
        <UButton v-if="canManage" size="xs" :color="confirmId === f.id ? 'error' : 'neutral'" :variant="confirmId === f.id ? 'solid' : 'ghost'" icon="i-lucide-trash" :label="confirmId === f.id ? t('taxCard.confirmRemove') : undefined" :aria-label="t('common.delete')" @click="onRemove(f)" />
      </li>
    </ul>
    <template v-if="immediate">
      <UButton v-if="canManage && customerId" size="sm" color="neutral" variant="outline" icon="i-lucide-upload" :label="t('taxCard.upload')" :loading="uploading" @click="picker?.click()" />
      <input ref="picker" type="file" multiple accept="image/*,application/pdf" class="hidden" @change="onPick" />
    </template>
    <UFileUpload v-else v-model="files" multiple accept="image/*,application/pdf" class="w-full" />
    <p v-if="required && !ok" class="text-xs text-error">{{ t("taxCard.required") }}</p>
  </div>
</template>

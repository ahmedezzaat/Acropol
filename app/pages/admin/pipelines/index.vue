<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Pipeline {
  id: string;
  name: string;
  sort_order: number;
}

const { data: pipelines, refresh, status } = await useAsyncData<Pipeline[]>(
  "admin-pipelines",
  async () => {
    const { data, error } = await supabase
      .from("pipelines")
      .select("id, name, sort_order")
      .order("sort_order");
    if (error) throw error;
    return data ?? [];
  },
);

const columns = computed<TableColumn<Pipeline>[]>(() => [
  { accessorKey: "name", header: t("admin.pipelines.name") },
]);

const createOpen = ref(false);
const creating = ref(false);
const schema = computed(() =>
  z.object({
    name: z.string().min(1, t("validation.required")),
  }),
);
type Schema = { name: string };
const state = reactive<Partial<Schema>>({ name: "" });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const nextSortOrder = (pipelines.value?.length ?? 0) + 1;
  const { error } = await supabase.from("pipelines").insert({
    name: event.data.name,
    sort_order: nextSortOrder,
  });
  creating.value = false;

  if (error) {
    toast.add({ title: t("admin.pipelines.createPipelineFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("admin.pipelines.pipelineCreated"), color: "success" });
  createOpen.value = false;
  state.name = "";
  refresh();
}

function openPipeline(pipeline: Pipeline) {
  navigateTo(`/admin/pipelines/${pipeline.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.pipelines.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('admin.pipelines.newPipeline')" @click="createOpen = true" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable
        :data="pipelines ?? []"
        :columns="columns"
        :loading="status === 'pending' || status === 'idle'"
        @select="(_e, row) => openPipeline(row.original)"
      />
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('admin.pipelines.createPipelineTitle')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="name" :label="t('admin.pipelines.name')">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>
        <UButton type="submit" :label="t('common.create')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>

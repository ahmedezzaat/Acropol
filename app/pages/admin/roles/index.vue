<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Role {
  id: string;
  name: string;
  description: string | null;
}

const { data: roles, refresh, status } = await useAsyncData<Role[]>(
  "admin-roles",
  async () => {
    const { data, error } = await supabase
      .from("roles")
      .select("id, name, description")
      .order("name");
    if (error) throw error;
    return data ?? [];
  },
);

const columns = computed<TableColumn<Role>[]>(() => [
  { accessorKey: "name", header: t("admin.roles.name") },
  { accessorKey: "description", header: t("admin.roles.description") },
]);

const createOpen = ref(false);
const creating = ref(false);

const schema = computed(() =>
  z.object({
    name: z.string().min(1, t("validation.required")),
    description: z.string().optional(),
  }),
);
type Schema = { name: string; description?: string };
const state = reactive<Partial<Schema>>({ name: "", description: "" });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const { error } = await supabase.from("roles").insert({
    name: event.data.name,
    description: event.data.description || null,
  });
  creating.value = false;

  if (error) {
    toast.add({ title: t("admin.roles.createRoleFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("admin.roles.roleCreated"), color: "success" });
  createOpen.value = false;
  state.name = "";
  state.description = "";
  refresh();
}

function openRole(role: Role) {
  navigateTo(`/admin/roles/${role.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.roles.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('admin.roles.newRole')" @click="createOpen = true" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable
        :data="roles ?? []"
        :columns="columns"
        :loading="status === 'pending' || status === 'idle'"
        @select="(_e, row) => openRole(row.original)"
      />
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('admin.roles.createRoleTitle')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="name" :label="t('admin.roles.name')">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>
        <UFormField name="description" :label="t('admin.roles.description')">
          <UTextarea v-model="state.description" class="w-full" />
        </UFormField>
        <UButton type="submit" :label="t('common.create')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>

<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();

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

const columns: TableColumn<Role>[] = [
  { accessorKey: "name", header: "Name" },
  { accessorKey: "description", header: "Description" },
];

const createOpen = ref(false);
const creating = ref(false);

const schema = z.object({
  name: z.string().min(1, "Name is required"),
  description: z.string().optional(),
});
type Schema = z.output<typeof schema>;
const state = reactive<Partial<Schema>>({ name: "", description: "" });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const { error } = await supabase.from("roles").insert({
    name: event.data.name,
    description: event.data.description || null,
  });
  creating.value = false;

  if (error) {
    toast.add({ title: "Failed to create role", description: error.message, color: "error" });
    return;
  }

  toast.add({ title: "Role created", color: "success" });
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
      <UDashboardNavbar title="Roles">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" label="New role" @click="createOpen = true" />
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

  <UModal v-model:open="createOpen" title="New role">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="name" label="Name">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>
        <UFormField name="description" label="Description">
          <UTextarea v-model="state.description" class="w-full" />
        </UFormField>
        <UButton type="submit" label="Create" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>

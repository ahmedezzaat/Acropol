<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Profile {
  id: string;
  email: string;
  full_name: string | null;
  role_id: string | null;
  is_admin: boolean;
  is_active: boolean;
}

interface Role {
  id: string;
  name: string;
}

const { data: users, refresh: refreshUsers, status: usersStatus } = await useAsyncData<Profile[]>(
  "admin-users",
  async () => {
    const { data, error } = await supabase
      .from("profiles")
      .select("id, email, full_name, role_id, is_admin, is_active")
      .order("email");
    if (error) throw error;
    return data ?? [];
  },
);

const { data: roles } = await useAsyncData<Role[]>("admin-users-roles", async () => {
  const { data, error } = await supabase.from("roles").select("id, name").order("name");
  if (error) throw error;
  return data ?? [];
});

const roleOptions = computed(() => [
  { label: t("admin.users.noRole"), value: null },
  ...(roles.value ?? []).map((r) => ({ label: r.name, value: r.id })),
]);

function roleName(roleId: string | null) {
  return roles.value?.find((r) => r.id === roleId)?.name ?? "—";
}

const columns = computed<TableColumn<Profile>[]>(() => [
  { accessorKey: "email", header: t("common.email") },
  { accessorKey: "full_name", header: t("common.name") },
  { id: "role", header: t("admin.users.role") },
  { id: "status", header: t("common.status") },
  { id: "actions" },
]);

// --- Create user ---
const createOpen = ref(false);
const creating = ref(false);
const createSchema = computed(() =>
  z.object({
    email: z.email(t("validation.invalidEmail")),
    password: z.string().min(8, t("validation.minLength", { min: 8 })),
    full_name: z.string().min(1, t("validation.required")),
    role_id: z.uuid().nullable(),
    is_admin: z.boolean(),
  }),
);
type CreateSchema = {
  email: string;
  password: string;
  full_name: string;
  role_id: string | null;
  is_admin: boolean;
};
const createState = reactive<CreateSchema>({
  email: "",
  password: "",
  full_name: "",
  role_id: null,
  is_admin: false,
});

async function onCreate(event: FormSubmitEvent<CreateSchema>) {
  creating.value = true;
  try {
    await $fetch("/api/admin/users", { method: "POST", body: event.data });
    toast.add({ title: t("admin.users.userCreated"), color: "success" });
    createOpen.value = false;
    createState.email = "";
    createState.password = "";
    createState.full_name = "";
    createState.role_id = null;
    createState.is_admin = false;
    refreshUsers();
  } catch (err: any) {
    toast.add({
      title: t("admin.users.createUserFailed"),
      description: err?.data?.statusMessage ?? err.message,
      color: "error",
    });
  } finally {
    creating.value = false;
  }
}

// --- Edit user ---
const editOpen = ref(false);
const editing = ref(false);
const editTarget = ref<Profile | null>(null);
const editState = reactive({
  full_name: "",
  role_id: null as string | null,
  is_admin: false,
  is_active: true,
});

function openEdit(user: Profile) {
  editTarget.value = user;
  editState.full_name = user.full_name ?? "";
  editState.role_id = user.role_id;
  editState.is_admin = user.is_admin;
  editState.is_active = user.is_active;
  editOpen.value = true;
}

async function saveEdit() {
  if (!editTarget.value) return;
  editing.value = true;
  try {
    await $fetch(`/api/admin/users/${editTarget.value.id}/update`, {
      method: "POST",
      body: editState,
    });
    toast.add({ title: t("admin.users.userUpdated"), color: "success" });
    editOpen.value = false;
    refreshUsers();
  } catch (err: any) {
    toast.add({
      title: t("admin.users.updateUserFailed"),
      description: err?.data?.statusMessage ?? err.message,
      color: "error",
    });
  } finally {
    editing.value = false;
  }
}

// --- Reset password ---
const resetOpen = ref(false);
const resetting = ref(false);
const resetTarget = ref<Profile | null>(null);
const resetPassword = ref("");

function openReset(user: Profile) {
  resetTarget.value = user;
  resetPassword.value = "";
  resetOpen.value = true;
}

async function saveReset() {
  if (!resetTarget.value) return;
  resetting.value = true;
  try {
    await $fetch(`/api/admin/users/${resetTarget.value.id}/reset-password`, {
      method: "POST",
      body: { password: resetPassword.value },
    });
    toast.add({ title: t("admin.users.passwordReset"), color: "success" });
    resetOpen.value = false;
  } catch (err: any) {
    toast.add({
      title: t("admin.users.resetPasswordFailed"),
      description: err?.data?.statusMessage ?? err.message,
      color: "error",
    });
  } finally {
    resetting.value = false;
  }
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.users.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('admin.users.newUser')" @click="createOpen = true" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable :data="users ?? []" :columns="columns" :loading="usersStatus === 'pending' || usersStatus === 'idle'">
        <template #role-cell="{ row }">
          {{ roleName(row.original.role_id) }}
        </template>
        <template #status-cell="{ row }">
          <div class="flex gap-1">
            <UBadge v-if="row.original.is_admin" :label="t('admin.users.admin')" color="primary" variant="subtle" />
            <UBadge
              :label="row.original.is_active ? t('common.active') : t('common.inactive')"
              :color="row.original.is_active ? 'success' : 'neutral'"
              variant="subtle"
            />
          </div>
        </template>
        <template #actions-cell="{ row }">
          <UDropdownMenu
            :items="[
              [{ label: t('common.edit'), icon: 'i-lucide-pencil', onSelect: () => openEdit(row.original) }],
              [{ label: t('admin.users.resetPassword'), icon: 'i-lucide-key', onSelect: () => openReset(row.original) }],
            ]"
          >
            <UButton icon="i-lucide-ellipsis" color="neutral" variant="ghost" />
          </UDropdownMenu>
        </template>
      </UTable>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('admin.users.createUserTitle')">
    <template #body>
      <UForm :schema="createSchema" :state="createState" class="space-y-4" @submit="onCreate">
        <UFormField name="full_name" :label="t('admin.users.fullName')">
          <UInput v-model="createState.full_name" class="w-full" />
        </UFormField>
        <UFormField name="email" :label="t('common.email')">
          <UInput v-model="createState.email" type="email" class="w-full" />
        </UFormField>
        <UFormField name="password" :label="t('admin.users.password')">
          <UInput v-model="createState.password" type="password" class="w-full" />
        </UFormField>
        <UFormField name="role_id" :label="t('admin.users.role')">
          <USelect v-model="createState.role_id" :items="roleOptions" value-key="value" class="w-full" />
        </UFormField>
        <UCheckbox v-model="createState.is_admin" :label="t('admin.users.administratorFullAccess')" />
        <UButton type="submit" :label="t('admin.users.createUser')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>

  <UModal v-model:open="editOpen" :title="t('admin.users.editUserTitle', { email: editTarget?.email ?? '' })">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('admin.users.fullName')">
          <UInput v-model="editState.full_name" class="w-full" />
        </UFormField>
        <UFormField :label="t('admin.users.role')">
          <USelect v-model="editState.role_id" :items="roleOptions" value-key="value" class="w-full" />
        </UFormField>
        <UCheckbox v-model="editState.is_admin" :label="t('admin.users.administratorFullAccess')" />
        <UCheckbox v-model="editState.is_active" :label="t('admin.users.activeCanSignIn')" />
        <UButton :label="t('common.save')" :loading="editing" block @click="saveEdit" />
      </div>
    </template>
  </UModal>

  <UModal v-model:open="resetOpen" :title="t('admin.users.resetPasswordTitle', { email: resetTarget?.email ?? '' })">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('admin.users.newPassword')">
          <UInput v-model="resetPassword" type="password" class="w-full" />
        </UFormField>
        <UButton
          :label="t('admin.users.resetPassword')"
          :loading="resetting"
          :disabled="resetPassword.length < 8"
          block
          @click="saveReset"
        />
      </div>
    </template>
  </UModal>
</template>

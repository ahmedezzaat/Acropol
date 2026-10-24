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
  can_login: boolean;
  is_technician: boolean;
  phone: string | null;
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
      .select("id, email, full_name, role_id, is_admin, is_active, can_login, is_technician, phone")
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
    // someone who can sign in needs an email or a phone number
    email: z.union([z.email(t("validation.invalidEmail")), z.literal("")]),
    phone: z.string(),
    password: createState.can_login ? z.string().min(8, t("validation.minLength", { min: 8 })) : z.string(),
    full_name: z.string().min(1, t("validation.required")),
    role_id: z.uuid().nullable(),
    is_admin: z.boolean(),
    can_login: z.boolean(),
    is_technician: z.boolean(),
  }).refine((v) => !v.can_login || !!v.email || !!v.phone.trim(), { message: t("admin.users.emailOrPhone"), path: ["email"] }),
);
type CreateSchema = {
  email: string;
  phone: string;
  password: string;
  full_name: string;
  role_id: string | null;
  is_admin: boolean;
  can_login: boolean;
  is_technician: boolean;
};
const createState = reactive<CreateSchema>({
  email: "",
  phone: "",
  password: "",
  full_name: "",
  role_id: null,
  is_admin: false,
  can_login: true,
  is_technician: false,
});

function openCreate() {
  createOpen.value = true;
}

async function onCreate(event: FormSubmitEvent<CreateSchema>) {
  creating.value = true;
  try {
    const { email, password, phone, ...rest } = event.data;
    await $fetch("/api/admin/users", {
      method: "POST",
      body: { ...rest, ...(email ? { email } : {}), ...(phone.trim() ? { phone } : {}), ...(event.data.can_login ? { password } : {}) },
    });
    toast.add({ title: t("admin.users.userCreated"), color: "success" });
    createOpen.value = false;
    createState.email = "";
    createState.phone = "";
    createState.password = "";
    createState.full_name = "";
    createState.role_id = null;
    createState.is_admin = false;
    createState.can_login = true;
    createState.is_technician = false;
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
  email: "",
  phone: "",
  full_name: "",
  role_id: null as string | null,
  is_admin: false,
  is_active: true,
  can_login: true,
  is_technician: false,
});
// someone who signs in with a phone number and has no email carries a placeholder address
const isPhoneOnly = (u: Profile) => u.email.endsWith("@phone.acropol.invalid");
const emailShown = (u: Profile) => (isPhoneOnly(u) ? (u.phone ?? "") : u.email);
const editEmailValid = computed(() => editState.email === "" ? !!editState.phone.trim() : z.email().safeParse(editState.email).success);

function openEdit(user: Profile) {
  editTarget.value = user;
  editState.email = isPhoneOnly(user) ? "" : user.email;
  editState.phone = user.phone ?? "";
  editState.full_name = user.full_name ?? "";
  editState.role_id = user.role_id;
  editState.is_admin = user.is_admin;
  editState.is_active = user.is_active;
  editState.can_login = user.can_login;
  editState.is_technician = user.is_technician;
  editOpen.value = true;
}

async function saveEdit() {
  if (!editTarget.value) return;
  editing.value = true;
  try {
    const { email, ...fields } = editState;
    await $fetch(`/api/admin/users/${editTarget.value.id}/update`, {
      method: "POST",
      // an empty email leaves the placeholder one as it is
      body: { ...fields, ...(email ? { email } : {}), phone: editState.phone.trim() || null },
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

// --- Delete user ---
const deleteOpen = ref(false);
const deleting = ref(false);
const deleteTarget = ref<Profile | null>(null);

function openDelete(user: Profile) {
  deleteTarget.value = user;
  deleteOpen.value = true;
}

async function confirmDelete() {
  if (!deleteTarget.value) return;
  deleting.value = true;
  try {
    await $fetch(`/api/admin/users/${deleteTarget.value.id}/delete`, { method: "POST" });
    toast.add({ title: t("admin.users.userDeleted"), color: "success" });
    deleteOpen.value = false;
    refreshUsers();
  } catch (err: any) {
    const code = err?.data?.statusMessage ?? "";
    const description = code === "cannot_delete_self"
      ? t("admin.users.cannotDeleteSelf")
      : code.startsWith("has_data:")
        ? t("admin.users.deleteUserBlocked")
        : (code || err.message);
    toast.add({ title: t("admin.users.deleteUserFailed"), description, color: "error" });
  } finally {
    deleting.value = false;
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
          <UButton icon="i-lucide-plus" :label="t('admin.users.newUser')" @click="openCreate" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable :data="users ?? []" :columns="columns" :loading="usersStatus === 'pending' || usersStatus === 'idle'">
        <template #email-cell="{ row }">
          <span v-if="row.original.email.endsWith('@no-login.acropol.invalid')" class="text-muted">—</span>
          <span v-else-if="isPhoneOnly(row.original)" dir="ltr" class="inline-flex items-center gap-1"><UIcon name="i-lucide-phone" class="size-3.5 text-muted" />{{ emailShown(row.original) }}</span>
          <span v-else>{{ row.original.email }}</span>
          <div v-if="row.original.phone && !isPhoneOnly(row.original)" dir="ltr" class="text-start text-xs text-muted">{{ row.original.phone }}</div>
        </template>
        <template #role-cell="{ row }">
          {{ roleName(row.original.role_id) }}
        </template>
        <template #status-cell="{ row }">
          <div class="flex gap-1">
            <UBadge v-if="row.original.is_admin" :label="t('admin.users.admin')" color="primary" variant="subtle" />
            <UBadge v-if="row.original.is_technician" :label="t('admin.users.technicianBadge')" icon="i-lucide-wrench" color="info" variant="subtle" />
            <UBadge v-if="!row.original.can_login" :label="t('admin.users.noLoginBadge')" icon="i-lucide-lock" color="warning" variant="subtle" />
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
              [
                {
                  label: t('admin.users.deleteUser'),
                  icon: 'i-lucide-trash',
                  color: 'error',
                  onSelect: () => openDelete(row.original),
                },
              ],
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
        <UCheckbox v-model="createState.can_login" :label="t('admin.users.canLogin')" />
        <UCheckbox v-model="createState.is_technician" :label="t('admin.users.isTechnician')" />
        <p v-if="!createState.can_login" class="text-xs text-muted">{{ t("admin.users.noLoginHint") }}</p>
        <UFormField name="email" :label="`${t('common.email')} (${t('admin.users.optional')})`">
          <UInput v-model="createState.email" type="email" class="w-full" />
        </UFormField>
        <UFormField name="phone" :label="t('admin.users.phoneLogin')" :help="t('admin.users.phoneLoginHint')">
          <UInput v-model="createState.phone" type="tel" dir="ltr" placeholder="01xxxxxxxxx" class="w-full" />
        </UFormField>
        <UFormField v-if="createState.can_login" name="password" :label="t('admin.users.password')">
          <UInput v-model="createState.password" type="password" class="w-full" />
        </UFormField>
        <UFormField name="role_id" :label="t('admin.users.role')">
          <USelect v-model="createState.role_id" :items="roleOptions" value-key="value" class="w-full" />
        </UFormField>
        <UCheckbox v-if="createState.can_login" v-model="createState.is_admin" :label="t('admin.users.administratorFullAccess')" />
        <UButton type="submit" :label="t('admin.users.createUser')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>

  <UModal v-model:open="editOpen" :title="t('admin.users.editUserTitle', { email: editTarget?.email ?? '' })">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('common.email')">
          <UInput v-model="editState.email" type="email" class="w-full" />
        </UFormField>
        <UFormField :label="t('admin.users.phoneLogin')" :help="t('admin.users.phoneLoginHint')">
          <UInput v-model="editState.phone" type="tel" dir="ltr" placeholder="01xxxxxxxxx" class="w-full" />
        </UFormField>
        <UFormField :label="t('admin.users.fullName')">
          <UInput v-model="editState.full_name" class="w-full" />
        </UFormField>
        <UFormField :label="t('admin.users.role')">
          <USelect v-model="editState.role_id" :items="roleOptions" value-key="value" class="w-full" />
        </UFormField>
        <UCheckbox v-model="editState.is_admin" :label="t('admin.users.administratorFullAccess')" />
        <UCheckbox v-model="editState.is_active" :label="t('admin.users.activeCanSignIn')" />
        <UCheckbox v-model="editState.can_login" :label="t('admin.users.canLogin')" />
        <UCheckbox v-model="editState.is_technician" :label="t('admin.users.isTechnician')" />
        <p v-if="!editState.can_login" class="text-xs text-muted">{{ t("admin.users.noLoginHint") }}</p>
        <p v-else-if="editTarget && !editTarget.can_login" class="text-xs text-muted">{{ t("admin.users.enableLoginHint") }}</p>
        <UButton :label="t('common.save')" :loading="editing" :disabled="!editEmailValid" block @click="saveEdit" />
      </div>
    </template>
  </UModal>

  <UModal v-model:open="deleteOpen" :title="t('admin.users.deleteUserTitle', { email: deleteTarget?.email ?? '' })">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("admin.users.deleteUserWarning") }}</p>
        <UButton
          :label="t('admin.users.deleteUser')"
          color="error"
          :loading="deleting"
          block
          @click="confirmDelete"
        />
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

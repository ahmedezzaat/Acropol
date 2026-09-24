<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const route = useRoute();
const roleId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const name = ref("");
const description = ref("");
const permSet = reactive<Record<string, boolean>>({});
const saving = ref(false);
const deleting = ref(false);

function permKey(resourceKey: string, actionKey: string) {
  return `${resourceKey}:${actionKey}`;
}

const { status } = await useAsyncData(`admin-role-${roleId}`, async () => {
  const [{ data: role, error: roleError }, { data: perms, error: permsError }] =
    await Promise.all([
      supabase.from("roles").select("*").eq("id", roleId).single(),
      supabase.from("role_permissions").select("module, action").eq("role_id", roleId),
    ]);

  if (roleError) throw roleError;
  if (permsError) throw permsError;

  name.value = role.name;
  description.value = role.description ?? "";
  for (const p of perms ?? []) {
    permSet[permKey(p.module, p.action)] = true;
  }

  return true;
});

async function saveDetails() {
  saving.value = true;
  const { error } = await supabase
    .from("roles")
    .update({ name: name.value, description: description.value || null })
    .eq("id", roleId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("admin.roles.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.roles.roleSaved"), color: "success" });
}

async function savePermissions() {
  saving.value = true;

  const selected = Object.entries(permSet)
    .filter(([, checked]) => checked)
    .map(([key]) => {
      const [module, action] = key.split(":");
      return { role_id: roleId, module, action };
    });

  // Simplest correct approach for a small permission set: replace wholesale
  // rather than diffing adds/removes.
  const { error: deleteError } = await supabase
    .from("role_permissions")
    .delete()
    .eq("role_id", roleId);

  if (deleteError) {
    saving.value = false;
    toast.add({ title: t("admin.roles.savePermissionsFailed"), description: deleteError.message, color: "error" });
    return;
  }

  if (selected.length > 0) {
    const { error: insertError } = await supabase.from("role_permissions").insert(selected);
    if (insertError) {
      saving.value = false;
      toast.add({ title: t("admin.roles.savePermissionsFailed"), description: insertError.message, color: "error" });
      return;
    }
  }

  saving.value = false;
  toast.add({ title: t("admin.roles.permissionsSaved"), color: "success" });
}

async function deleteRole() {
  deleting.value = true;
  const { error } = await supabase.from("roles").delete().eq("id", roleId);
  deleting.value = false;

  if (error) {
    toast.add({ title: t("admin.roles.deleteRoleFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.roles.roleDeleted"), color: "success" });
  navigateTo("/admin/roles");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.roles.editRole')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            icon="i-lucide-trash"
            :label="t('admin.roles.deleteRole')"
            color="error"
            variant="soft"
            :loading="deleting"
            @click="deleteRole"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="max-w-2xl space-y-8">
        <UPageCard :title="t('admin.roles.detailsTitle')">
          <div class="space-y-4">
            <UFormField :label="t('admin.roles.name')">
              <UInput v-model="name" class="w-full" />
            </UFormField>
            <UFormField :label="t('admin.roles.description')">
              <UTextarea v-model="description" class="w-full" />
            </UFormField>
            <UButton :label="t('admin.roles.saveDetails')" :loading="saving" @click="saveDetails" />
          </div>
        </UPageCard>

        <UPageCard :title="t('admin.roles.permissionsTitle')" :description="t('admin.roles.permissionsDescription')">
          <div class="space-y-6">
            <div v-for="module in MODULES" :key="module.key">
              <h3 class="mb-2 flex items-center gap-2 font-medium text-highlighted">
                <UIcon :name="module.icon" class="size-4" />
                {{ t(module.labelKey) }}
              </h3>
              <div class="space-y-3 ps-6">
                <div v-for="resource in module.resources" :key="resource.key">
                  <p class="mb-1 text-sm text-muted">{{ t(resource.labelKey) }}</p>
                  <div class="flex flex-wrap gap-x-6 gap-y-2">
                    <UCheckbox
                      v-for="action in resource.actions"
                      :key="action.key"
                      v-model="permSet[permKey(resource.key, action.key)]"
                      :label="t(action.labelKey)"
                    />
                  </div>
                </div>
              </div>
            </div>
            <UButton :label="t('admin.roles.savePermissions')" :loading="saving" @click="savePermissions" />
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>

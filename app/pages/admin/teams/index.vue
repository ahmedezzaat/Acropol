<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Team {
  id: string;
  name: string;
  leader_id: string;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const { data: teams, refresh, status } = await useAsyncData<Team[]>("admin-teams", async () => {
  const { data, error } = await supabase.from("teams").select("id, name, leader_id").order("name");
  if (error) throw error;
  return data ?? [];
});

const { data: profiles } = await useAsyncData<Profile[]>("admin-teams-profiles", async () => {
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email")
    .eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

function profileLabel(id: string | null) {
  if (!id) return "—";
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}

interface TeamRow extends Team {
  leaderLabel: string;
}
const rows = computed<TeamRow[]>(
  () => (teams.value ?? []).map((tm) => ({ ...tm, leaderLabel: profileLabel(tm.leader_id) })),
);

const columns = computed<TableColumn<TeamRow>[]>(() => [
  { accessorKey: "name", header: t("admin.teams.name") },
  { accessorKey: "leaderLabel", header: t("admin.teams.leader") },
]);

// A profile already leading a team can't lead a second one (leader_id is
// unique on the teams table).
const leaderOptions = computed(() => {
  const takenLeaderIds = new Set((teams.value ?? []).map((tm) => tm.leader_id));
  return (profiles.value ?? [])
    .filter((p) => !takenLeaderIds.has(p.id))
    .map((p) => ({ label: p.full_name || p.email, value: p.id }));
});

const createOpen = ref(false);
const creating = ref(false);
const schema = computed(() =>
  z.object({
    name: z.string().min(1, t("validation.required")),
    leader_id: z.uuid(t("validation.required")),
  }),
);
type Schema = { name: string; leader_id: string };
const state = reactive<Partial<Schema>>({ name: "", leader_id: undefined });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const { data, error } = await supabase
    .from("teams")
    .insert({ name: event.data.name, leader_id: event.data.leader_id })
    .select("id")
    .single();

  if (error) {
    creating.value = false;
    toast.add({ title: t("admin.teams.createTeamFailed"), description: error.message, color: "error" });
    return;
  }

  // The leader is naturally part of their own team.
  await supabase.from("profiles").update({ team_id: data.id }).eq("id", event.data.leader_id);
  creating.value = false;

  toast.add({ title: t("admin.teams.teamCreated"), color: "success" });
  createOpen.value = false;
  state.name = "";
  state.leader_id = undefined;
  refresh();
}

function openTeam(team: Team) {
  navigateTo(`/admin/teams/${team.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.teams.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('admin.teams.newTeam')" @click="createOpen = true" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable
        :data="rows"
        :columns="columns"
        :loading="status === 'pending' || status === 'idle'"
        @select="(_e, row) => openTeam(row.original)"
      />
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('admin.teams.createTeamTitle')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="name" :label="t('admin.teams.name')">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>
        <UFormField name="leader_id" :label="t('admin.teams.leader')">
          <USelect v-model="state.leader_id" :items="leaderOptions" value-key="value" class="w-full" />
        </UFormField>
        <UButton type="submit" :label="t('admin.teams.createTeam')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>

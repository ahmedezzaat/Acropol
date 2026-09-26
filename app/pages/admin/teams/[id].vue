<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const route = useRoute();
const teamId = route.params.id as string;
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
  team_id: string | null;
}

const name = ref("");
const leaderId = ref<string | undefined>(undefined);
const selectedMemberIds = ref<string[]>([]);
const saving = ref(false);
const savingMembers = ref(false);
const deleting = ref(false);

// See crm/leads/[id].vue for why this goes through useAsyncData's own
// `data` (via watchEffect) instead of only mutating the local refs inside
// the handler.
const { data: teamPayload, status } = await useAsyncData(`admin-team-${teamId}`, async () => {
  const [{ data: team, error: teamError }, { data: allProfiles, error: profilesError }, { data: otherTeams, error: teamsError }] =
    await Promise.all([
      supabase.from("teams").select("*").eq("id", teamId).single(),
      supabase.from("profiles").select("id, full_name, email, team_id").eq("is_active", true),
      supabase.from("teams").select("id, leader_id").neq("id", teamId),
    ]);

  if (teamError) throw teamError;
  if (profilesError) throw profilesError;
  if (teamsError) throw teamsError;

  return { team, allProfiles: allProfiles ?? [], otherTeams: otherTeams ?? [] };
});

const profiles = ref<Profile[]>([]);
const takenLeaderIds = ref<Set<string>>(new Set());

watchEffect(() => {
  if (!teamPayload.value) return;
  const { team, allProfiles, otherTeams } = teamPayload.value;
  name.value = team.name;
  leaderId.value = team.leader_id;
  profiles.value = allProfiles;
  selectedMemberIds.value = allProfiles.filter((p) => p.team_id === teamId).map((p) => p.id);
  takenLeaderIds.value = new Set(otherTeams.map((tm) => tm.leader_id));
});

function profileLabel(profile: Profile) {
  return profile.full_name || profile.email;
}

// A profile already leading another team can't lead this one too
// (leader_id is unique) — the current leader stays selectable.
const leaderOptions = computed(() =>
  profiles.value
    .filter((p) => !takenLeaderIds.value.has(p.id) || p.id === leaderId.value)
    .map((p) => ({ label: profileLabel(p), value: p.id })),
);

const memberOptions = computed(() =>
  profiles.value.map((p) => ({
    label:
      p.team_id && p.team_id !== teamId
        ? `${profileLabel(p)} (${t("admin.teams.memberOfOtherTeam")})`
        : profileLabel(p),
    value: p.id,
  })),
);

async function saveDetails() {
  if (!leaderId.value) return;
  saving.value = true;
  const { error } = await supabase
    .from("teams")
    .update({ name: name.value, leader_id: leaderId.value })
    .eq("id", teamId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("admin.teams.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.teams.teamSaved"), color: "success" });
}

async function saveMembers() {
  savingMembers.value = true;
  const currentMemberIds = new Set(profiles.value.filter((p) => p.team_id === teamId).map((p) => p.id));
  const nextMemberIds = new Set(selectedMemberIds.value);

  const toAdd = [...nextMemberIds].filter((id) => !currentMemberIds.has(id));
  const toRemove = [...currentMemberIds].filter((id) => !nextMemberIds.has(id));

  if (toAdd.length > 0) {
    const { error } = await supabase.from("profiles").update({ team_id: teamId }).in("id", toAdd);
    if (error) {
      savingMembers.value = false;
      toast.add({ title: t("admin.teams.saveMembersFailed"), description: error.message, color: "error" });
      return;
    }
  }
  if (toRemove.length > 0) {
    const { error } = await supabase.from("profiles").update({ team_id: null }).in("id", toRemove);
    if (error) {
      savingMembers.value = false;
      toast.add({ title: t("admin.teams.saveMembersFailed"), description: error.message, color: "error" });
      return;
    }
  }

  savingMembers.value = false;
  toast.add({ title: t("admin.teams.membersSaved"), color: "success" });
  profiles.value = profiles.value.map((p) => ({
    ...p,
    team_id: nextMemberIds.has(p.id) ? teamId : p.team_id === teamId ? null : p.team_id,
  }));
}

async function deleteTeam() {
  deleting.value = true;
  const { error } = await supabase.from("teams").delete().eq("id", teamId);
  deleting.value = false;

  if (error) {
    toast.add({ title: t("admin.teams.deleteTeamFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.teams.teamDeleted"), color: "success" });
  navigateTo("/admin/teams");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="name || t('admin.teams.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            icon="i-lucide-trash"
            :label="t('admin.teams.deleteTeam')"
            color="error"
            variant="soft"
            :loading="deleting"
            @click="deleteTeam"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="max-w-2xl space-y-6">
        <UPageCard :title="t('admin.teams.detailsTitle')">
          <div class="space-y-4">
            <UFormField :label="t('admin.teams.name')">
              <UInput v-model="name" class="w-full" />
            </UFormField>
            <UFormField :label="t('admin.teams.leader')">
              <USelect v-model="leaderId" :items="leaderOptions" value-key="value" class="w-full" />
            </UFormField>
            <UButton :label="t('admin.teams.saveDetails')" :loading="saving" @click="saveDetails" />
          </div>
        </UPageCard>

        <UPageCard :title="t('admin.teams.membersTitle')" :description="t('admin.teams.membersDescription')">
          <div class="space-y-4">
            <USelectMenu
              v-model="selectedMemberIds"
              :items="memberOptions"
              value-key="value"
              multiple
              searchable
              :placeholder="t('admin.teams.selectMembers')"
              class="w-full"
            />
            <UButton :label="t('common.save')" :loading="savingMembers" @click="saveMembers" />
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>

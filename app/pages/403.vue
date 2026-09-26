<script setup lang="ts">
definePageMeta({ layout: "default" });
const supabase = useSupabaseClient();
const { t } = useI18n();

async function signOut() {
  await supabase.auth.signOut();
  await navigateTo("/login");
}
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center p-6">
    <UPageCard class="w-full max-w-md text-center">
      <UIcon name="i-lucide-shield-alert" class="mx-auto size-10 text-error" />
      <h1 class="mt-4 text-xl font-semibold text-default">{{ t("forbidden.title") }}</h1>
      <p class="mt-1 text-sm text-muted">{{ t("forbidden.description") }}</p>
      <div class="mt-6 flex flex-col gap-2">
        <UButton to="/" :label="t('forbidden.backHome')" block />
        <UButton :label="t('nav.signOut')" color="neutral" variant="ghost" block @click="signOut" />
      </div>
    </UPageCard>
  </div>
</template>

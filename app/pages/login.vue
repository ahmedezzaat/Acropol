<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, AuthFormField } from "@nuxt/ui";

definePageMeta({ layout: "default" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const submitting = ref(false);
const errorMessage = ref("");

const fields = computed<AuthFormField[]>(() => [
  {
    name: "email",
    type: "email",
    label: t("auth.login.email"),
    // Hardcoded, not routed through $t(): vue-i18n's message compiler treats
    // "@" as the start of a linked-message token, so "you@example.com" as a
    // translation value fails to parse — and this string isn't actually
    // language-specific content anyway.
    placeholder: "you@example.com",
    required: true,
  },
  {
    name: "password",
    type: "password",
    label: t("auth.login.password"),
    placeholder: t("auth.login.passwordPlaceholder"),
    required: true,
  },
]);

const schema = computed(() =>
  z.object({
    email: z.email(t("validation.invalidEmail")),
    password: z.string().min(1, t("validation.required")),
  }),
);

type Schema = { email: string; password: string };

async function onSubmit(payload: FormSubmitEvent<Schema>) {
  submitting.value = true;
  errorMessage.value = "";

  const { error } = await supabase.auth.signInWithPassword({
    email: payload.data.email,
    password: payload.data.password,
  });

  if (error) {
    submitting.value = false;
    errorMessage.value = t("auth.login.error");
    return;
  }

  // useSupabaseUser() updates asynchronously (the module's auth-state-change
  // listener awaits a separate getClaims() call) — navigating immediately
  // after signIn races it, and auth.global.ts's middleware sees a still-null
  // user and bounces straight back to /login. Wait for the ref to actually
  // reflect the new session first.
  const user = useSupabaseUser();
  if (!user.value) {
    await new Promise<void>((resolve) => {
      const stop = watch(
        user,
        (value) => {
          if (value) {
            stop();
            resolve();
          }
        },
        { immediate: true },
      );
    });
  }

  submitting.value = false;
  toast.add({ title: t("auth.login.signedIn"), color: "success" });
  await navigateTo("/");
}
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center">
    <UPageCard class="w-full max-w-md">
      <UAuthForm
        :schema="schema"
        :fields="fields"
        :submit="{ label: t('auth.login.submit'), loading: submitting, block: true }"
        :title="t('auth.login.title')"
        :description="t('auth.login.description')"
        icon="i-lucide-lock"
        @submit="onSubmit"
      >
        <template v-if="errorMessage" #validation>
          <UAlert color="error" variant="subtle" :title="errorMessage" />
        </template>
      </UAuthForm>
    </UPageCard>
  </div>
</template>

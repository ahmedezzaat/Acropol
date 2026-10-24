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
    // an email, or a phone number (technicians sign in with their phone)
    name: "identifier",
    type: "text",
    label: t("auth.login.identifier"),
    // Hardcoded, not routed through $t(): vue-i18n's message compiler treats
    // "@" as the start of a linked-message token, and this isn't language content.
    placeholder: "you@example.com / 01xxxxxxxxx",
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
    identifier: z.string().min(1, t("validation.required")),
    password: z.string().min(1, t("validation.required")),
  }),
);

type Schema = { identifier: string; password: string };

async function onSubmit(payload: FormSubmitEvent<Schema>) {
  submitting.value = true;
  errorMessage.value = "";

  const identifier = payload.data.identifier.trim();
  let error: unknown = null;
  if (identifier.includes("@")) {
    ({ error } = await supabase.auth.signInWithPassword({ email: identifier, password: payload.data.password }));
  } else {
    // a phone number: the server finds the account and checks the password
    try {
      const session = await $fetch<{ access_token: string; refresh_token: string }>("/api/auth/phone-login", {
        method: "POST",
        body: { phone: identifier, password: payload.data.password },
      });
      ({ error } = await supabase.auth.setSession(session));
    } catch (e) {
      error = e;
    }
  }

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

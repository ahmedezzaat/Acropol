<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, AuthFormField } from "@nuxt/ui";

definePageMeta({ layout: "default" });

const supabase = useSupabaseClient();
const toast = useToast();
const submitting = ref(false);
const errorMessage = ref("");

const fields: AuthFormField[] = [
  {
    name: "email",
    type: "email",
    label: "Email",
    placeholder: "you@example.com",
    required: true,
  },
  {
    name: "password",
    type: "password",
    label: "Password",
    placeholder: "Enter your password",
    required: true,
  },
];

const schema = z.object({
  email: z.email("Invalid email"),
  password: z.string().min(1, "Password is required"),
});

type Schema = z.output<typeof schema>;

async function onSubmit(payload: FormSubmitEvent<Schema>) {
  submitting.value = true;
  errorMessage.value = "";

  const { error } = await supabase.auth.signInWithPassword({
    email: payload.data.email,
    password: payload.data.password,
  });

  submitting.value = false;

  if (error) {
    errorMessage.value = "Incorrect email or password.";
    return;
  }

  toast.add({ title: "Signed in", color: "success" });
  await navigateTo("/");
}
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center">
    <UPageCard class="w-full max-w-md">
      <UAuthForm
        :schema="schema"
        :fields="fields"
        :submit="{ label: 'Sign in', loading: submitting, block: true }"
        title="Welcome back"
        description="Sign in with the account your administrator created for you."
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

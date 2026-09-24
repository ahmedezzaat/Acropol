<script setup lang="ts">
definePageMeta({ layout: "default" });
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center p-6">
    <UPageCard class="w-full max-w-md text-center">
      <UIcon name="i-lucide-shield-alert" class="mx-auto size-10 text-error" />
      <h1 class="mt-4 text-xl font-semibold text-default">Not authorized</h1>
      <p class="mt-1 text-sm text-muted">
        You don't have permission to access this page. Ask an administrator
        to grant you access.
      </p>
      <UButton to="/" label="Back to home" class="mt-6" block />
    </UPageCard>
  </div>
</template>

<script setup lang="ts">
// The Click-to-WhatsApp ad a chat (or one message) came from: its picture, headline and text, and a link to the ad.
const props = defineProps<{ ad: AdRef }>();
const { t } = useI18n();
// the embedded thumbnail always works; the picture link expires, so it is only a fallback
const imageFailed = ref(false);
const picture = computed(() => props.ad.thumb || (imageFailed.value ? null : props.ad.image));
</script>

<template>
  <div class="flex items-start gap-3 rounded-[10px] border border-info/30 bg-info/5 p-2.5 text-start">
    <img v-if="picture" :src="picture" alt="" referrerpolicy="no-referrer" loading="lazy" class="size-14 shrink-0 rounded-[8px] object-cover" @error="imageFailed = true" />
    <span v-else class="flex size-14 shrink-0 items-center justify-center rounded-[8px] bg-info/10 text-info"><UIcon name="i-lucide-megaphone" class="size-6" /></span>
    <div class="min-w-0 flex-1 space-y-0.5">
      <p class="flex items-center gap-1.5 text-[11px] font-medium text-info"><UIcon name="i-lucide-megaphone" class="size-3.5" />{{ t("chats.ad.from") }}</p>
      <p class="truncate text-sm font-semibold text-highlighted">{{ ad.title || t("chats.ad.noTitle") }}</p>
      <p v-if="ad.body" class="line-clamp-2 whitespace-pre-line text-xs text-toned">{{ ad.body }}</p>
      <a v-if="ad.url" :href="ad.url" target="_blank" rel="noopener noreferrer" class="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline">
        <UIcon name="i-lucide-external-link" class="size-3.5" />{{ t("chats.ad.open") }}
      </a>
    </div>
  </div>
</template>

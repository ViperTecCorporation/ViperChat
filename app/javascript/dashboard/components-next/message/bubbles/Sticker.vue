<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { contentAttributes, attachments } = useMessageContext();
const { t } = useI18n();

const stickerUrl = computed(() => {
  const attachment = attachments.value?.[0];
  const url =
    contentAttributes.value?.stickerUrl ||
    contentAttributes.value?.sticker_url ||
    attachment?.dataUrl ||
    attachment?.data_url ||
    attachment?.downloadUrl ||
    attachment?.download_url ||
    attachment?.thumbUrl ||
    attachment?.thumb_url ||
    '';
  return url;
});
</script>

<template>
  <BaseBubble class="overflow-hidden p-3" data-bubble-name="sticker">
    <img
      v-if="stickerUrl"
      :src="stickerUrl"
      :alt="t('CONVERSATION.REPLYBOX.STICKERS.ALT')"
      class="skip-context-menu w-36 h-36 object-contain"
    />
  </BaseBubble>
</template>

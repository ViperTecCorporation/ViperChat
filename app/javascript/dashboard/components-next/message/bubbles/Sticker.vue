<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();

const stickerUrl = computed(() => {
  return (
    contentAttributes.value?.stickerUrl ||
    contentAttributes.value?.sticker_url ||
    ''
  );
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

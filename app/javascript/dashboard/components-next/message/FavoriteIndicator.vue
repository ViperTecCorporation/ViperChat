<script setup>
import { computed, watch } from 'vue';
import { useStore } from 'vuex';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  messageId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], required: true },
});
const store = useStore();
const favorite = computed(() =>
  store.getters['messageFavorites/isFavorite']?.(
    props.conversationId,
    props.messageId
  )
);
watch(
  () => props.conversationId,
  id => {
    if (id) store.dispatch('messageFavorites/load', id).catch(() => {});
  },
  { immediate: true }
);
</script>

<template>
  <Icon
    v-if="favorite"
    icon="i-lucide-star"
    class="size-3.5 shrink-0 text-n-amber-11 fill-current"
    :aria-label="$t('CONVERSATION.FAVORITES.STARRED')"
  />
</template>

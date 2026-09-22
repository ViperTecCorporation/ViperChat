<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({ message: { type: Object, required: true } });
const emit = defineEmits(['close']);
const store = useStore();
const { t } = useI18n();
const busy = ref(false);
const conversationId = computed(
  () => props.message.conversation_id ?? props.message.conversationId
);
const persisted = computed(
  () =>
    Number.isInteger(Number(props.message.id)) && Number(props.message.id) > 0
);
const favorite = computed(() =>
  store.getters['messageFavorites/isFavorite'](
    conversationId.value,
    props.message.id
  )
);
const toggle = async () => {
  if (busy.value) return;
  busy.value = true;
  try {
    await store.dispatch('messageFavorites/load', conversationId.value);
    await store.dispatch('messageFavorites/setFavorite', {
      conversationId: conversationId.value,
      messageId: props.message.id,
      favorite: !favorite.value,
    });
    emit('close');
  } catch {
    useAlert(t('CONVERSATION.FAVORITES.ERROR'));
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <button
    v-if="persisted"
    type="button"
    :disabled="busy"
    class="flex items-center gap-2 min-h-9 w-full p-1 rounded-md text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
    @click.stop="toggle"
  >
    <Icon
      icon="i-lucide-star"
      class="size-4 shrink-0"
      :class="favorite && 'fill-current text-n-amber-11'"
    />
    {{
      favorite
        ? t('CONVERSATION.FAVORITES.REMOVE')
        : t('CONVERSATION.FAVORITES.ADD')
    }}
  </button>
</template>

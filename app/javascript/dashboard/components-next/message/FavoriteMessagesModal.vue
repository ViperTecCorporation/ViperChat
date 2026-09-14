<script setup>
import { ref, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'next/dialog/Dialog.vue';
import Button from 'next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import api from 'dashboard/api/messageFavorites';
import { getMessagePreviewContent } from 'dashboard/helper/messagePreviewHelper';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  contactId: { type: [String, Number], default: null },
  conversationId: { type: [String, Number], default: null },
});
const emit = defineEmits(['navigate']);
const { t, locale } = useI18n();
const { getPlainText } = useMessageFormatter();
const store = useStore();
const router = useRouter();
const dialog = ref(null);
const rows = ref([]);
const busy = ref(false);
const hasMore = ref(false);
const error = ref('');
let generation = 0;

const fetchRows = async (append = false) => {
  const request = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await api.list({
      contact_id: props.contactId || undefined,
      conversation_id: props.conversationId || undefined,
      before: append ? rows.value.at(-1)?.id : undefined,
    });
    if (request !== generation) return;
    rows.value = append ? [...rows.value, ...data.payload] : data.payload;
    hasMore.value = data.has_more;
  } catch {
    if (request === generation) error.value = t('CONVERSATION.FAVORITES.ERROR');
  } finally {
    if (request === generation) busy.value = false;
  }
};
const open = () => {
  generation += 1;
  rows.value = [];
  hasMore.value = false;
  dialog.value.open();
  fetchRows();
};
const close = () => {
  generation += 1;
  dialog.value?.close();
};
watch(() => [props.contactId, props.conversationId], close);
const preview = message =>
  getPlainText(getMessagePreviewContent({ message, t }));
const thumbnail = message => {
  const attachment = message.attachments?.[0];
  return (
    attachment?.thumb_url ||
    (attachment?.file_type === 'image' ? attachment.data_url : '')
  );
};
const timestamp = message =>
  new Date(message.created_at * 1000).toLocaleString(
    locale.value.replace('_', '-')
  );
const remove = async row => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    await store.dispatch('messageFavorites/setFavorite', {
      conversationId: row.message.conversation_id,
      messageId: row.message.id,
      favorite: false,
    });
    rows.value = rows.value.filter(item => item.id !== row.id);
  } catch {
    error.value = t('CONVERSATION.FAVORITES.ERROR');
  } finally {
    busy.value = false;
  }
};
const navigate = async row => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const conversationId = row.message.conversation_id;
    const messageId = row.message.id;
    await store.dispatch('loadFavoriteMessage', { conversationId, messageId });
    await router.push({
      name: 'inbox_conversation',
      params: {
        accountId: store.getters.getCurrentAccountId,
        conversation_id: conversationId,
      },
      query: { messageId },
    });
    close();
    emit('navigate');
    await nextTick();
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
  } catch {
    error.value = t('CONVERSATION.FAVORITES.UNAVAILABLE');
  } finally {
    busy.value = false;
  }
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('CONVERSATION.FAVORITES.TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="t('CONVERSATION.FAVORITES.CLOSE')"
    width="lg"
    dialog-class="!w-[calc(100%-2rem)] !p-0 max-h-[90dvh]"
    content-class="!max-h-[90dvh] !overflow-hidden !mb-0"
    @close="generation += 1"
  >
    <div
      class="flex flex-col gap-3 min-w-0 min-h-0 max-h-[60dvh] overflow-y-auto"
    >
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <Button
        v-if="error"
        :label="t('CONVERSATION.FAVORITES.RETRY')"
        :disabled="busy"
        @click="fetchRows()"
      />
      <p v-if="!busy && !error && !rows.length" class="text-sm text-n-slate-11">
        {{ t('CONVERSATION.FAVORITES.EMPTY') }}
      </p>
      <article
        v-for="row in rows"
        :key="row.id"
        class="p-3 rounded-xl border border-n-weak bg-n-alpha-1 min-w-0"
      >
        <div class="flex items-center gap-2 min-w-0 mb-2">
          <Avatar :name="row.contact_name" :src="row.thumbnail" :size="28" />
          <div class="flex-1 min-w-0">
            <p class="m-0 text-sm font-medium text-n-slate-12 truncate">
              {{ row.message.sender?.name || row.contact_name }}
            </p>
            <p class="m-0 text-xs text-n-slate-11 truncate">
              {{ row.inbox_name }} · {{ timestamp(row.message) }}
            </p>
          </div>
          <Button
            icon="i-lucide-star"
            color="amber"
            :aria-label="t('CONVERSATION.FAVORITES.REMOVE')"
            :title="t('CONVERSATION.FAVORITES.REMOVE')"
            :disabled="busy"
            ghost
            sm
            @click="remove(row)"
          />
        </div>
        <button
          type="button"
          class="flex items-center gap-2 w-full text-start min-w-0 text-n-slate-12"
          :disabled="busy"
          :aria-label="t('CONVERSATION.FAVORITES.GO_TO_MESSAGE')"
          @click="navigate(row)"
        >
          <div class="flex-1 min-w-0">
            <img
              v-if="thumbnail(row.message)"
              :src="thumbnail(row.message)"
              alt=""
              class="max-h-40 max-w-full rounded-lg object-contain mb-2"
              loading="lazy"
              @error="$event.target.hidden = true"
            />
            <span
              v-if="row.message.attachments?.length"
              class="flex items-center gap-1 mb-1 text-xs text-n-slate-11"
            >
              <Icon
                :icon="
                  row.message.attachments[0].file_type === 'audio'
                    ? 'i-lucide-mic'
                    : 'i-lucide-paperclip'
                "
                class="size-3.5 shrink-0"
              />
              <span class="truncate">{{
                row.message.attachments[0].file_name ||
                t('CONVERSATION.FAVORITES.MEDIA')
              }}</span>
            </span>
            <span class="whitespace-pre-wrap break-words line-clamp-5">{{
              preview(row.message)
            }}</span>
          </div>
          <Icon icon="i-lucide-chevron-right" class="size-4 shrink-0" />
        </button>
      </article>
      <p v-if="busy" role="status" class="text-sm text-n-slate-11">
        {{ t('CONVERSATION.FAVORITES.LOADING') }}
      </p>
      <Button
        v-if="hasMore"
        :disabled="busy"
        :label="t('CONVERSATION.FAVORITES.MORE')"
        @click="fetchRows(true)"
      />
    </div>
  </Dialog>
</template>

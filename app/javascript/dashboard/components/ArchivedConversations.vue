<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import Dialog from 'next/dialog/Dialog.vue';
import Button from 'next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import MessagePreview from './widgets/conversation/MessagePreview.vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import api from 'dashboard/api/conversations';
import { useConversationArchives } from 'dashboard/composables/useConversationArchives';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { archives, setArchived } = useConversationArchives();
const dialog = ref(null);
const rows = ref([]);
const busy = ref(false);
const error = ref(false);
const page = ref(1);
const hasMore = ref(false);
let generation = 0;
const load = async (append = false) => {
  generation += 1;
  const request = generation;
  busy.value = true;
  error.value = false;
  try {
    const nextPage = append ? page.value + 1 : 1;
    const { data } = await api.getArchived(nextPage);
    if (request !== generation) return;
    rows.value = append ? [...rows.value, ...data.payload] : data.payload;
    page.value = nextPage;
    hasMore.value = data.has_more;
  } catch {
    if (request === generation) error.value = true;
  } finally {
    if (request === generation) busy.value = false;
  }
};
const open = () => {
  rows.value = [];
  dialog.value.open();
  load();
};
const restore = async row => {
  busy.value = true;
  error.value = false;
  try {
    await setArchived(row.id, false);
    await load();
  } catch {
    error.value = true;
  } finally {
    busy.value = false;
  }
};
const navigate = async row => {
  await router.push({
    name: 'inbox_conversation',
    params: {
      accountId: store.getters.getCurrentAccountId,
      conversation_id: row.id,
    },
  });
  dialog.value.close();
};
</script>

<template>
  <button
    type="button"
    class="flex items-center gap-3 w-full px-4 py-3 text-n-slate-12 hover:bg-n-alpha-2"
    @click="open"
  >
    <span class="i-lucide-archive size-5 shrink-0" />
    <span class="flex-1 text-start">{{ t('CONVERSATION.ARCHIVE.TITLE') }}</span>
    <span>{{ archives.length }}</span>
  </button>
  <Dialog
    ref="dialog"
    :title="t('CONVERSATION.ARCHIVE.TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="t('CONVERSATION.ARCHIVE.CLOSE')"
    dialog-class="!w-[calc(100%-2rem)] !p-0 max-h-[90dvh]"
    content-class="!max-h-[90dvh] !overflow-hidden !mb-0"
    @close="generation += 1"
  >
    <div
      class="flex flex-col gap-2 min-w-0 min-h-0 max-h-[60dvh] overflow-y-auto"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('CONVERSATION.ARCHIVE.DESCRIPTION') }}
      </p>
      <p v-if="error" role="alert">{{ t('CONVERSATION.ARCHIVE.ERROR') }}</p>
      <Button
        v-if="error"
        :label="t('CONVERSATION.ARCHIVE.RETRY')"
        :disabled="busy"
        @click="load()"
      />
      <p v-if="!busy && !error && !rows.length">
        {{ t('CONVERSATION.ARCHIVE.EMPTY') }}
      </p>
      <article
        v-for="row in rows"
        :key="row.id"
        class="flex flex-wrap items-center gap-2 p-3 rounded-lg border border-n-weak min-w-0"
      >
        <button
          type="button"
          class="flex items-center gap-2 flex-1 min-w-0 text-start"
          @click="navigate(row)"
        >
          <Avatar
            :name="row.group_title || row.meta?.sender?.name || ''"
            :src="row.group ? row.group_picture : row.meta?.sender?.thumbnail"
            :size="32"
          />
          <div class="flex-1 min-w-0 overflow-hidden">
            <p class="truncate text-n-slate-12 m-0">
              {{ row.group_title || row.meta?.sender?.name }}
            </p>
            <MessagePreview
              v-if="getLastMessage(row)"
              :message="getLastMessage(row)"
              class="text-sm text-n-slate-11 min-w-0"
            />
            <p v-else class="truncate text-sm text-n-slate-11 m-0">
              {{ t('CHAT_LIST.NO_MESSAGES') }}
            </p>
          </div>
        </button>
        <Button
          icon="i-lucide-archive-restore"
          :label="t('CONVERSATION.ARCHIVE.RESTORE')"
          :disabled="busy"
          sm
          ghost
          @click="restore(row)"
        />
      </article>
      <p v-if="busy" role="status">{{ t('CONVERSATION.ARCHIVE.LOADING') }}</p>
      <Button
        v-if="hasMore"
        :label="t('CONVERSATION.ARCHIVE.MORE')"
        :disabled="busy"
        @click="load(true)"
      />
    </div>
  </Dialog>
</template>

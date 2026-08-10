<script setup>
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  consumePendingShare,
  dismissPendingShare,
  initializeNativeShare,
  usePendingNativeShare,
} from '../platform/nativeShareService';

const store = useStore();
const route = useRoute();
const router = useRouter();
const pendingShare = usePendingNativeShare();

const conversations = computed(() =>
  (store.getters.getAllConversations || []).slice(0, 12)
);
const conversationContact = conversation => conversation.meta?.sender || {};
const conversationName = conversation =>
  conversation.group_title ||
  conversationContact(conversation).name ||
  conversationContact(conversation).phone_number ||
  'Conversa';
const conversationThumbnail = conversation =>
  conversation.group_picture ||
  conversation.additional_attributes?.group_picture ||
  conversationContact(conversation).thumbnail ||
  '';
const conversationInbox = conversation =>
  store.getters['inboxes/getInbox'](conversation.inbox_id)?.name || '';
const selectedConversationId = computed(() => route.params.conversation_id);
const summary = computed(() => {
  const fileCount = pendingShare.value?.files.length || 0;
  const hasText = Boolean(pendingShare.value?.text);
  if (fileCount && hasText) return `${fileCount} arquivo(s) e texto`;
  if (fileCount) return `${fileCount} arquivo(s)`;
  return 'Texto compartilhado';
});

onMounted(initializeNativeShare);

const chooseConversation = conversation => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: store.getters.getCurrentAccountId,
      conversation_id: conversation.id,
    },
  });
};

const attachToComposer = async () => {
  const payload = await consumePendingShare();
  if (payload) emitter.emit(BUS_EVENTS.NATIVE_SHARE_RECEIVED, payload);
};
</script>

<template>
  <aside
    v-if="pendingShare"
    class="fixed inset-x-3 bottom-3 z-[1000] mx-auto max-w-md rounded-xl border border-n-weak bg-n-solid-2 p-4 shadow-xl"
  >
    <div class="flex items-start justify-between gap-3">
      <div>
        <p class="font-medium text-n-slate-12">Conteúdo recebido</p>
        <p class="mt-1 text-sm text-n-slate-10">{{ summary }}</p>
      </div>
      <button class="text-sm text-n-slate-10" @click="dismissPendingShare">
        Fechar
      </button>
    </div>

    <button
      v-if="selectedConversationId"
      class="mt-4 h-10 w-full rounded-lg bg-n-brand font-medium text-white"
      @click="attachToComposer"
    >
      Anexar nesta conversa
    </button>

    <div v-else class="mt-4">
      <p class="mb-2 text-xs font-medium text-n-slate-11">
        Escolha uma conversa
      </p>
      <div class="max-h-72 space-y-1 overflow-y-auto">
        <button
          v-for="conversation in conversations"
          :key="conversation.id"
          class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left hover:bg-n-alpha-2"
          @click="chooseConversation(conversation)"
        >
          <Avatar
            :name="conversationName(conversation)"
            :src="conversationThumbnail(conversation)"
            :size="32"
            rounded-full
          />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-n-slate-12">
              {{ conversationName(conversation) }}
            </span>
            <span class="block truncate text-xs text-n-slate-10">
              #{{ conversation.display_id || conversation.id }}
              <template v-if="conversationInbox(conversation)">
                · {{ conversationInbox(conversation) }}
              </template>
            </span>
          </span>
        </button>
      </div>
    </div>
  </aside>
</template>

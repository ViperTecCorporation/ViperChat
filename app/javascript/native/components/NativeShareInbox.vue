<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import SearchAPI from 'dashboard/api/search';
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
const searchQuery = ref('');
const searchResults = ref([]);
const isSearching = ref(false);
const searchError = ref('');
const copy = Object.freeze({
  title: 'Conteúdo recebido',
  close: 'Fechar',
  attach: 'Anexar nesta conversa',
  choose: 'Escolha uma conversa',
  searchPlaceholder: 'Pesquisar nome, telefone ou conversa',
  searching: 'Pesquisando…',
  searchEmpty: 'Nenhuma conversa encontrada.',
  searchError: 'Não foi possível pesquisar as conversas.',
});

const recentConversations = computed(() =>
  (store.getters.getAllConversations || []).slice(0, 12)
);
const conversations = computed(() =>
  searchQuery.value.trim() ? searchResults.value : recentConversations.value
);
const conversationContact = conversation =>
  conversation.contact || conversation.meta?.sender || {};
const conversationName = conversation =>
  conversation.groupTitle ||
  conversation.group_title ||
  conversationContact(conversation).name ||
  conversationContact(conversation).phoneNumber ||
  conversationContact(conversation).phone_number ||
  'Conversa';
const conversationThumbnail = conversation =>
  conversation.groupPicture ||
  conversation.group_picture ||
  conversation.additionalAttributes?.groupPicture ||
  conversation.additional_attributes?.group_picture ||
  conversationContact(conversation).thumbnail ||
  '';
const conversationAvatarKey = conversation =>
  `${conversation.id}:${conversationContact(conversation).id || ''}:${conversationThumbnail(conversation)}`;
const conversationInbox = conversation =>
  conversation.inbox?.name ||
  store.getters['inboxes/getInbox'](conversation.inboxId)?.name ||
  store.getters['inboxes/getInbox'](conversation.inbox_id)?.name ||
  '';
const conversationMeta = conversation => {
  const id =
    conversation.displayId || conversation.display_id || conversation.id;
  const inbox = conversationInbox(conversation);
  return inbox ? `#${id} · ${inbox}` : `#${id}`;
};
const selectedConversationId = computed(() => route.params.conversation_id);
const summary = computed(() => {
  const fileCount = pendingShare.value?.files.length || 0;
  const hasText = Boolean(pendingShare.value?.text);
  if (fileCount && hasText) return `${fileCount} arquivo(s) e texto`;
  if (fileCount) return `${fileCount} arquivo(s)`;
  return 'Texto compartilhado';
});

onMounted(initializeNativeShare);

let searchTimer;
let searchRequestId = 0;
const searchConversations = value => {
  searchQuery.value = value;
  searchError.value = '';
  window.clearTimeout(searchTimer);
  searchRequestId += 1;
  const requestId = searchRequestId;

  const query = value.trim();
  if (!query) {
    searchResults.value = [];
    isSearching.value = false;
    return;
  }

  searchResults.value = [];
  isSearching.value = true;
  searchTimer = window.setTimeout(async () => {
    try {
      const { data } = await SearchAPI.conversations({ q: query });
      if (requestId !== searchRequestId) return;

      searchResults.value = data.payload?.conversations || [];
    } catch {
      if (requestId !== searchRequestId) return;

      searchResults.value = [];
      searchError.value = copy.searchError;
    } finally {
      if (requestId === searchRequestId) isSearching.value = false;
    }
  }, 300);
};

onBeforeUnmount(() => {
  searchRequestId += 1;
  window.clearTimeout(searchTimer);
});

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
    @click.stop
    @pointerdown.stop
  >
    <div class="flex items-start justify-between gap-3">
      <div>
        <p class="font-medium text-n-slate-12">{{ copy.title }}</p>
        <p class="mt-1 text-sm text-n-slate-10">{{ summary }}</p>
      </div>
      <button class="text-sm text-n-slate-10" @click="dismissPendingShare">
        {{ copy.close }}
      </button>
    </div>

    <button
      v-if="selectedConversationId"
      class="mt-4 h-10 w-full rounded-lg bg-n-brand font-medium text-white"
      @click="attachToComposer"
    >
      {{ copy.attach }}
    </button>

    <div v-else class="mt-4">
      <p class="mb-2 text-xs font-medium text-n-slate-11">
        {{ copy.choose }}
      </p>
      <div class="max-h-72 space-y-1 overflow-y-auto">
        <label class="relative mb-3 block">
          <span
            class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            :value="searchQuery"
            type="search"
            autocomplete="off"
            :placeholder="copy.searchPlaceholder"
            class="h-10 w-full rounded-lg border border-n-weak bg-n-alpha-2 pl-9 pr-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            @input="searchConversations($event.target.value)"
          />
        </label>
        <p v-if="isSearching" class="px-3 py-4 text-sm text-n-slate-10">
          {{ copy.searching }}
        </p>
        <p v-else-if="searchError" class="px-3 py-4 text-sm text-n-ruby-11">
          {{ searchError }}
        </p>
        <p
          v-else-if="searchQuery.trim() && !conversations.length"
          class="px-3 py-4 text-sm text-n-slate-10"
        >
          {{ copy.searchEmpty }}
        </p>
        <button
          v-for="conversation in conversations"
          :key="conversation.id"
          type="button"
          class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left hover:bg-n-alpha-2"
          @click="chooseConversation(conversation)"
        >
          <Avatar
            :key="conversationAvatarKey(conversation)"
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
              {{ conversationMeta(conversation) }}
            </span>
          </span>
        </button>
      </div>
    </div>
  </aside>
</template>

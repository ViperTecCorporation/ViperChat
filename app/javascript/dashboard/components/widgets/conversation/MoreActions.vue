<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import MediaLibraryModal from './MediaLibraryModal.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);
const showMediaModal = ref(false);
const isLoadingMedia = ref(false);
const isLoadingMoreMedia = ref(false);

const currentChat = computed(() => store.getters.getSelectedChat);
const currentAttachments = computed(
  () => store.getters.getSelectedChatAttachments
);
const currentAttachmentsMeta = computed(
  () => store.getters.getSelectedChatAttachmentsMeta
);
const conversationMessages = computed(() => currentChat.value?.messages || []);

const mediaCounter = computed(() => currentAttachments.value.length || 0);

const actionMenuItems = computed(() => {
  const items = [];

  if (!currentChat.value.muted) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  return items;
});

const handleActionClick = async ({ action }) => {
  toggleDropdown(false);

  if (action === 'mute') {
    store.dispatch('muteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
  } else if (action === 'unmute') {
    store.dispatch('unmuteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  }
};

// These functions are needed for the event listeners
const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

const openMediaModal = async () => {
  if (!currentChat.value?.id) {
    showMediaModal.value = true;
    return;
  }

  try {
    isLoadingMedia.value = true;
    await store.dispatch('fetchAllAttachments', currentChat.value.id);
  } catch (error) {
    useAlert(t('CONVERSATION.MEDIA_LIBRARY.LOAD_ERROR'));
  } finally {
    isLoadingMedia.value = false;
    showMediaModal.value = true;
  }
};

const loadMoreAttachments = async () => {
  if (!currentChat.value?.id || isLoadingMoreMedia.value) return;
  try {
    isLoadingMoreMedia.value = true;
    await store.dispatch('loadMoreAttachments', currentChat.value.id);
  } catch (error) {
    useAlert(t('CONVERSATION.MEDIA_LIBRARY.LOAD_ERROR'));
  } finally {
    isLoadingMoreMedia.value = false;
  }
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <ButtonV4
      v-tooltip="$t('CONVERSATION.MEDIA_LIBRARY.BUTTON')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-images"
      class="rounded-md group-hover:bg-n-alpha-2"
      @click="openMediaModal"
    >
      <span class="flex items-center gap-2">
        <span>{{ $t('CONVERSATION.MEDIA_LIBRARY.BUTTON') }}</span>
        <span
          class="rounded-md capitalize text-xs leading-5 font-medium text-center outline outline-1 px-1 flex-shrink-0 text-n-slate-11 outline-n-strong"
        >
          {{ mediaCounter }}
        </span>
      </span>
    </ButtonV4>
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center group"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="rounded-md group-hover:bg-n-alpha-2"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
    <MediaLibraryModal
      :show="showMediaModal"
      :attachments="currentAttachments"
      :messages="conversationMessages"
      :conversation-id="currentChat?.id"
      :is-loading="isLoadingMedia"
      :attachments-meta="currentAttachmentsMeta"
      :is-loading-more="isLoadingMoreMedia"
      @close="showMediaModal = false"
      @load-more="loadMoreAttachments"
    />
  </div>
</template>

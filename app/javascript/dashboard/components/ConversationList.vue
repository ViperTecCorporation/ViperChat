<script setup>
import { ref, computed, provide } from 'vue';
import { Virtualizer } from 'virtua/vue';
import { useBreakpoints } from '@vueuse/core';
import { useChatListKeyboardEvents } from 'dashboard/composables/chatlist/useChatListKeyboardEvents';
import ConversationItem from './ConversationItem.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  conversationList: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  showEndOfListMessage: { type: Boolean, default: false },
  label: { type: String, default: '' },
  teamId: { type: [String, Number], default: 0 },
  foldersId: { type: [String, Number], default: 0 },
  conversationType: { type: String, default: '' },
  showAssignee: { type: Boolean, default: false },
  isOnExpandedLayout: { type: Boolean, default: false },
});

const emit = defineEmits(['loadMore']);

const conversationListRef = ref(null);
const virtualListRef = ref(null);
const isContextMenuOpen = ref(false);
let pullStart = null;
const pullReady = ref(false);
const startPull = event => {
  const list = conversationListRef.value;
  pullReady.value = false;
  pullStart =
    !props.isLoading &&
    !isContextMenuOpen.value &&
    event.touches.length === 1 &&
    list.scrollTop + list.clientHeight >= list.scrollHeight - 2
      ? { x: event.touches[0].clientX, y: event.touches[0].clientY }
      : null;
};
const movePull = event => {
  if (!pullStart || event.touches.length !== 1) return;
  const touch = event.touches[0];
  pullReady.value =
    pullStart.y - touch.clientY > 90 &&
    Math.abs(touch.clientX - pullStart.x) < 50;
};
const cancelPull = () => {
  pullStart = null;
  pullReady.value = false;
};
const finishPull = () => {
  if (pullReady.value && !props.isLoading)
    emitter.emit('refresh_conversation_list');
  cancelPull();
};

provide('contextMenuElementTarget', virtualListRef);

const breakpoints = useBreakpoints({
  lg: wootConstants.LARGE_SCREEN_BREAKPOINT,
});
const isLgScreen = breakpoints.greaterOrEqual('lg');
const showExpandedCards = computed(
  () => props.isOnExpandedLayout && isLgScreen.value
);

useChatListKeyboardEvents(conversationListRef);

const intersectionObserverOptions = computed(() => ({
  root: conversationListRef.value,
  rootMargin: '100px 0px 100px 0px',
}));

const onContextMenuToggle = state => {
  isContextMenuOpen.value = state;
};

const loadMoreConversations = () => {
  emit('loadMore');
};

provide('toggleContextMenu', onContextMenuToggle);

defineExpose({ conversationListRef });
</script>

<template>
  <div
    ref="conversationListRef"
    class="flex-1 min-h-0 overflow-y-auto conversations-list"
    :class="{ '!overflow-hidden': isContextMenuOpen }"
    @touchstart.passive="startPull"
    @touchmove.passive="movePull"
    @touchend="finishPull"
    @touchcancel="cancelPull"
  >
    <Virtualizer
      ref="virtualListRef"
      v-slot="{ item }"
      :data="conversationList"
      class="[&>div:has(+_div_.active)>*]:!border-n-surface-1 [&>div:has(+_div_.selected)>*]:!border-n-surface-1"
    >
      <ConversationItem
        :source="item"
        :label="label"
        :team-id="teamId"
        :folders-id="foldersId"
        :conversation-type="conversationType"
        :show-assignee="showAssignee"
        :show-expanded="showExpandedCards"
      />
    </Virtualizer>
    <div
      v-if="isLoading || pullReady"
      class="flex justify-center my-4"
      role="status"
    >
      <Spinner class="text-n-brand" />
    </div>
    <p v-else-if="showEndOfListMessage" class="p-4 text-center text-n-slate-11">
      {{ $t('CHAT_LIST.EOF') }}
    </p>
    <IntersectionObserver
      v-else
      :options="intersectionObserverOptions"
      @observed="loadMoreConversations"
    />
  </div>
</template>

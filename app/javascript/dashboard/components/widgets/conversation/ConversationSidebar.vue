<script setup>
import { computed } from 'vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import { useConversationSidepanel } from 'dashboard/composables/useConversationSidepanel';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { isContactSidebarOpen, closeContactSidebar } =
  useConversationSidepanel();
const { width: windowWidth } = useWindowSize();

const activeTab = computed(() => {
  if (isContactSidebarOpen.value) {
    return 0;
  }
  return null;
});

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeContactPanel = () => {
  if (isSmallScreen.value && isContactSidebarOpen.value) {
    closeContactSidebar();
  }
};
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
    ]"
  >
    <div class="flex flex-1 overflow-auto">
      <ContactPanel
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>

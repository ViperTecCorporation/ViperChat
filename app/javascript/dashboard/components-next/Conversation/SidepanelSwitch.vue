<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { computed, ref } from 'vue';
import WebAttendanceInvitation from './WebAttendanceInvitation.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useMapGetter } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useConversationSidepanel } from 'dashboard/composables/useConversationSidepanel';
import { supportsWebAttendance } from 'dashboard/helper/webAttendance';

const { uiSettings, updateUISettings } = useUISettings();
const {
  isContactSidebarOpen,
  openContactSidebar,
  closeContactSidebar,
  toggleContactSidebar,
} = useConversationSidepanel();

const currentAccountId = useMapGetter('getCurrentAccountId');
const currentChat = useMapGetter('getSelectedChat');
const getInbox = useMapGetter('inboxes/getInbox');
const showWebInvitation = ref(false);
const canInviteToWeb = computed(() => {
  const inbox = getInbox.value(currentChat.value?.inbox_id);
  return (
    supportsWebAttendance(inbox) &&
    inbox.web_attendance_enabled &&
    !currentChat.value?.group
  );
});
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const showCopilotTab = computed(() =>
  isFeatureEnabledonAccount.value(currentAccountId.value, FEATURE_FLAGS.CAPTAIN)
);

const isCopilotPanelOpen = computed(
  () => uiSettings.value.is_copilot_panel_open
);

const toggleConversationSidebarToggle = () => {
  toggleContactSidebar();
  updateUISettings({
    is_copilot_panel_open: false,
  });
};

const handleConversationSidebarToggle = () => {
  openContactSidebar();
  updateUISettings({
    is_copilot_panel_open: false,
  });
};

const handleCopilotSidebarToggle = () => {
  closeContactSidebar();
  updateUISettings({
    is_copilot_panel_open: true,
  });
};

const keyboardEvents = {
  'Alt+KeyO': {
    action: toggleConversationSidebarToggle,
  },
};
useKeyboardEvents(keyboardEvents);
</script>

<template>
  <ButtonGroup
    class="flex flex-col justify-center items-center absolute top-36 xl:top-24 ltr:right-2 rtl:left-2 bg-n-solid-2/90 backdrop-blur-lg border border-n-weak/50 rounded-full gap-1.5 p-1.5 shadow-sm transition-shadow duration-200 hover:shadow !z-20"
  >
    <Button
      v-tooltip.top="$t('CONVERSATION.SIDEBAR.CONTACT')"
      ghost
      slate
      sm
      class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
      :class="{
        'bg-n-alpha-2 active:shadow-sm': isContactSidebarOpen,
      }"
      icon="i-ph-user-bold"
      @click="handleConversationSidebarToggle"
    />
    <Button
      v-if="canInviteToWeb"
      v-tooltip.left="$t('WEB_ATTENDANCE.INVITE')"
      :aria-label="$t('WEB_ATTENDANCE.INVITE')"
      ghost
      slate
      sm
      class="!rounded-full shrink-0"
      icon="i-ph-browser"
      @click="showWebInvitation = true"
    />
    <Button
      v-if="showCopilotTab"
      v-tooltip.bottom="$t('CONVERSATION.SIDEBAR.COPILOT')"
      ghost
      slate
      sm
      class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:duration-75"
      :class="{
        'bg-n-alpha-2 !text-n-iris-9 active:!brightness-105 active:shadow-sm':
          isCopilotPanelOpen,
      }"
      icon="i-woot-captain"
      @click="handleCopilotSidebarToggle"
    />
  </ButtonGroup>
  <WebAttendanceInvitation
    v-if="canInviteToWeb"
    v-model:show="showWebInvitation"
  />
</template>

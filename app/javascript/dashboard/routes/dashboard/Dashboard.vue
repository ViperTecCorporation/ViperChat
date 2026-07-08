<script>
import { defineAsyncComponent, ref, computed } from 'vue';
import { toHex, mix } from 'color2k';

import NextSidebar from 'next/sidebar/Sidebar.vue';
import WootKeyShortcutModal from 'dashboard/components/widgets/modal/WootKeyShortcutModal.vue';
import AddAccountModal from 'dashboard/components/app/AddAccountModal.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useWindowSize } from '@vueuse/core';

import wootConstants from 'dashboard/constants/globals';

const CommandBar = defineAsyncComponent(
  () => import('./commands/commandbar.vue')
);

const FloatingCallWidget = defineAsyncComponent(
  () => import('dashboard/components/widgets/FloatingCallWidget.vue')
);
const VoiceDialerFab = defineAsyncComponent(
  () => import('dashboard/components/widgets/VoiceDialerFab.vue')
);
const VoiceAudioPlaybackModal = defineAsyncComponent(
  () => import('dashboard/components/widgets/VoiceAudioPlaybackModal.vue')
);
const VoiceAutoRegister = defineAsyncComponent(
  () => import('dashboard/components/widgets/VoiceAutoRegister.vue')
);

import CopilotLauncher from 'dashboard/components-next/copilot/CopilotLauncher.vue';
import CopilotContainer from 'dashboard/components/copilot/CopilotContainer.vue';

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    CommandBar,
    WootKeyShortcutModal,
    AddAccountModal,
    UpgradePage,
    CopilotLauncher,
    CopilotContainer,
    FloatingCallWidget,
    VoiceDialerFab,
    VoiceAudioPlaybackModal,
    VoiceAutoRegister,
    MobileSidebarLauncher,
  },
  setup() {
    const upgradePageRef = ref(null);
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();
    const callsStore = useCallsStore();

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      windowWidth,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
    };
  },
  data() {
    return {
      showAccountModal: false,
      showCreateAccountModal: false,
      showShortcutModal: false,
      isMobileSidebarOpen: false,
    };
  },
  computed: {
    isSmallScreen() {
      return this.windowWidth < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    showUpgradePage() {
      return this.upgradePageRef?.shouldShowUpgradePage;
    },
    bypassUpgradePage() {
      return [
        'billing_settings_index',
        'settings_inbox_list',
        'general_settings_index',
        'agent_list',
      ].includes(this.$route.name);
    },
    previouslyUsedDisplayType() {
      const {
        previously_used_conversation_display_type: conversationDisplayType,
      } = this.uiSettings;
      return conversationDisplayType;
    },
    activeTheme() {
      return this.uiSettings.active_theme || 'default';
    },
  },
  watch: {
    isSmallScreen: {
      handler() {
        const { LAYOUT_TYPES } = wootConstants;
        if (window.innerWidth <= wootConstants.SMALL_SCREEN_BREAKPOINT) {
          this.updateUISettings({
            conversation_display_type: LAYOUT_TYPES.EXPANDED,
          });
        } else {
          this.updateUISettings({
            conversation_display_type: this.previouslyUsedDisplayType,
          });
        }
      },
      immediate: true,
    },
    activeTheme: {
      handler(theme) {
        document.documentElement.classList.remove('brand-viper', 'brand-glow');
        if (theme === 'viper') {
          document.documentElement.classList.add('brand-viper');
          this.resetCustomBrandColors();
        } else if (theme === 'glow') {
          document.documentElement.classList.add('brand-glow');
          this.resetCustomBrandColors();
        } else if (theme === 'custom') {
          const color = this.uiSettings.custom_brand_color || '#2781f6';
          this.applyCustomBrandColors(color);
        } else {
          this.resetCustomBrandColors();
        }
      },
      immediate: true,
    },
    'uiSettings.custom_brand_color': {
      handler(color) {
        if (this.activeTheme === 'custom' && color) {
          this.applyCustomBrandColors(color);
        }
      },
      immediate: true,
    },
  },
  methods: {
    toggleMobileSidebar() {
      this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    },
    closeMobileSidebar() {
      this.isMobileSidebarOpen = false;
    },
    openCreateAccountModal() {
      this.showAccountModal = false;
      this.showCreateAccountModal = true;
    },
    closeCreateAccountModal() {
      this.showCreateAccountModal = false;
    },
    toggleAccountModal() {
      this.showAccountModal = !this.showAccountModal;
    },
    toggleKeyShortcutModal() {
      this.showShortcutModal = true;
    },
    closeKeyShortcutModal() {
      this.showShortcutModal = false;
    },
    applyCustomBrandColors(hexColor) {
      const mixWhite = weight => toHex(mix(hexColor, '#ffffff', weight));
      const mixBlack = weight => toHex(mix(hexColor, '#0a0a0a', weight));
      const root = document.documentElement;
      root.style.setProperty('--blue-1', mixWhite(0.96));
      root.style.setProperty('--blue-2', mixWhite(0.92));
      root.style.setProperty('--blue-3', mixWhite(0.86));
      root.style.setProperty('--blue-4', mixWhite(0.76));
      root.style.setProperty('--blue-5', mixWhite(0.62));
      root.style.setProperty('--blue-6', mixWhite(0.46));
      root.style.setProperty('--blue-7', mixWhite(0.28));
      root.style.setProperty('--blue-8', mixWhite(0.15));
      root.style.setProperty('--blue-9', hexColor);
      root.style.setProperty('--blue-10', mixBlack(0.15));
      root.style.setProperty('--blue-11', mixBlack(0.35));
      root.style.setProperty('--blue-12', mixBlack(0.55));
    },
    resetCustomBrandColors() {
      const root = document.documentElement;
      for (let i = 1; i <= 12; i += 1) {
        root.style.removeProperty(`--blue-${i}`);
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-grow overflow-hidden text-n-slate-12">
    <NextSidebar
      :is-mobile-sidebar-open="isMobileSidebarOpen"
      @toggle-account-modal="toggleAccountModal"
      @open-key-shortcut-modal="toggleKeyShortcutModal"
      @close-key-shortcut-modal="closeKeyShortcutModal"
      @show-create-account-modal="openCreateAccountModal"
      @close-mobile-sidebar="closeMobileSidebar"
    />

    <main
      class="flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden bg-n-surface-1"
    >
      <UpgradePage
        v-show="showUpgradePage"
        ref="upgradePageRef"
        :bypass-upgrade-page="bypassUpgradePage"
      >
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
      </UpgradePage>
      <template v-if="!showUpgradePage">
        <router-view />
        <CommandBar />
        <CopilotLauncher />
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
        <CopilotContainer />
        <VoiceAutoRegister />
        <VoiceDialerFab />
        <VoiceAudioPlaybackModal />
        <FloatingCallWidget v-if="hasActiveCall || hasIncomingCall" />
      </template>
      <AddAccountModal
        :show="showCreateAccountModal"
        @close-account-create-modal="closeCreateAccountModal"
      />
      <WootKeyShortcutModal
        v-model:show="showShortcutModal"
        @close="closeKeyShortcutModal"
        @clickaway="closeKeyShortcutModal"
      />
    </main>
  </div>
</template>

<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { LocalStorage } from 'shared/helpers/localStorage';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
      listPanelWidth: 412,
      isResizingLayout: false,
      viewportWidth: typeof window !== 'undefined' ? window.innerWidth : 0,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },
    isDesktop() {
      return this.viewportWidth >= wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    isResizableLayout() {
      return !this.isOnExpandedLayout && this.isDesktop;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initializeResizableLayout();
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
    window.addEventListener('resize', this.handleWindowResize);
    window.addEventListener('mousemove', this.handleResizeMouseMove);
    window.addEventListener('mouseup', this.stopResizeLayout);
  },

  beforeUnmount() {
    window.removeEventListener('resize', this.handleWindowResize);
    window.removeEventListener('mousemove', this.handleResizeMouseMove);
    window.removeEventListener('mouseup', this.stopResizeLayout);
  },

  methods: {
    initializeResizableLayout() {
      const storedWidth = LocalStorage.get(
        LOCAL_STORAGE_KEYS.CONVERSATION_LIST_PANEL_WIDTH
      );
      if (Number.isFinite(storedWidth)) {
        this.listPanelWidth = this.clampListPanelWidth(storedWidth);
      }
    },
    clampListPanelWidth(width) {
      const minWidth = 320;
      const reservedConversationWidth = this.shouldShowSidebar ? 720 : 420;
      const maxAvailableWidth = Math.max(
        minWidth,
        this.viewportWidth - reservedConversationWidth
      );
      const maxWidth = Math.min(720, maxAvailableWidth);
      return Math.max(minWidth, Math.min(width, maxWidth));
    },
    persistListPanelWidth(width) {
      LocalStorage.set(LOCAL_STORAGE_KEYS.CONVERSATION_LIST_PANEL_WIDTH, width);
    },
    handleWindowResize() {
      this.viewportWidth = window.innerWidth;
      if (this.isResizableLayout) {
        this.listPanelWidth = this.clampListPanelWidth(this.listPanelWidth);
      }
    },
    startResizeLayout() {
      if (!this.isResizableLayout) {
        return;
      }
      this.isResizingLayout = true;
    },
    handleResizeMouseMove(event) {
      if (!this.isResizingLayout || !this.isResizableLayout) {
        return;
      }
      this.listPanelWidth = this.clampListPanelWidth(event.clientX);
    },
    stopResizeLayout() {
      if (!this.isResizingLayout) {
        return;
      }
      this.isResizingLayout = false;
      this.persistListPanelWidth(this.listPanelWidth);
    },
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section class="flex w-full h-full min-w-0">
    <ChatList
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      :list-panel-width="listPanelWidth"
      @conversation-load="onConversationLoad"
    />
    <button
      v-if="isResizableLayout"
      type="button"
      class="hidden sm:flex w-1 shrink-0 cursor-col-resize bg-n-alpha-2 hover:bg-n-brand/40 active:bg-n-brand/50 transition-colors"
      :class="{ 'bg-n-brand/50': isResizingLayout }"
      :aria-label="$t('CONVERSATION.SWITCH_VIEW_LAYOUT')"
      @mousedown.prevent="startResizeLayout"
    />
    <ConversationBox
      v-if="showMessageView"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>
    <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
    <CmdBarConversationSnooze />
  </section>
</template>

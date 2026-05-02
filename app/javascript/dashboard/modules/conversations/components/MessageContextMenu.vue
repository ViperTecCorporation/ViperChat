<script>
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import AddCannedModal from 'dashboard/routes/dashboard/settings/canned/AddCanned.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { conversationUrl, frontendURL } from '../../../helper/URLHelper';
import {
  ACCOUNT_EVENTS,
  CONVERSATION_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import MenuItem from '../../../components/widgets/conversation/contextMenu/menuItem.vue';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import EmojiInput from 'shared/components/emoji/EmojiInput.vue';

export default {
  components: {
    AddCannedModal,
    MenuItem,
    ContextMenu,
    NextButton,
    EmojiInput,
  },
  props: {
    message: {
      type: Object,
      required: true,
    },
    isOpen: {
      type: Boolean,
      default: false,
    },
    enabledOptions: {
      type: Object,
      default: () => ({}),
    },
    contextMenuPosition: {
      type: Object,
      default: () => ({}),
    },
    hideButton: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['open', 'close', 'replyTo', 'forward'],
  setup() {
    const { getPlainText } = useMessageFormatter();

    return {
      getPlainText,
    };
  },
  data() {
    return {
      isCannedResponseModalOpen: false,
      isEditModalOpen: false,
      editedContent: '',
      isSavingEdit: false,
      showDeleteModal: false,
      isReactionModalOpen: false,
      isSendingReaction: false,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      currentAccountId: 'getCurrentAccountId',
      getUISettings: 'getUISettings',
    }),
    plainTextContent() {
      return this.getPlainText(this.messageContent);
    },
    conversationId() {
      return this.message.conversation_id ?? this.message.conversationId;
    },
    messageId() {
      return this.message.id;
    },
    messageContent() {
      return this.message.content;
    },
    contentAttributes() {
      return useSnakeCase(
        this.message.content_attributes ?? this.message.contentAttributes
      );
    },
  },
  methods: {
    async copyLinkToMessage() {
      const fullConversationURL =
        window.chatwootConfig.hostURL +
        frontendURL(
          conversationUrl({
            id: this.conversationId,
            accountId: this.currentAccountId,
          })
        );
      await copyTextToClipboard(
        `${fullConversationURL}?messageId=${this.messageId}`
      );
      useAlert(this.$t('CONVERSATION.CONTEXT_MENU.LINK_COPIED'));
      this.handleClose();
    },
    async handleCopy() {
      await copyTextToClipboard(this.plainTextContent);
      useAlert(this.$t('CONTACT_PANEL.COPY_SUCCESSFUL'));
      this.handleClose();
    },
    showCannedResponseModal() {
      useTrack(ACCOUNT_EVENTS.ADDED_TO_CANNED_RESPONSE);
      this.isCannedResponseModalOpen = true;
    },
    hideCannedResponseModal() {
      this.isCannedResponseModalOpen = false;
      this.handleClose();
    },
    handleOpen(e) {
      this.$emit('open', e);
    },
    handleClose(e) {
      this.$emit('close', e);
    },
    handleTranslate() {
      const { locale: accountLocale } = this.getAccount(this.currentAccountId);
      const agentLocale = this.getUISettings?.locale;
      const targetLanguage = agentLocale || accountLocale || 'en';
      this.$store.dispatch('translateMessage', {
        conversationId: this.conversationId,
        messageId: this.messageId,
        targetLanguage,
      });
      useTrack(CONVERSATION_EVENTS.TRANSLATE_A_MESSAGE);
      this.handleClose();
    },
    handleReplyTo() {
      this.$emit('replyTo', this.message);
      this.handleClose();
    },
    handleForward() {
      this.$emit('forward', this.message);
      this.handleClose();
    },
    openEditModal() {
      this.editedContent = this.plainTextContent;
      this.isEditModalOpen = true;
      this.handleClose();
    },
    closeEditModal() {
      this.isEditModalOpen = false;
      this.isSavingEdit = false;
    },
    async saveEdit() {
      const content = this.editedContent.trim();
      if (!content || this.isSavingEdit) return;

      this.isSavingEdit = true;
      try {
        await this.$store.dispatch('editMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
          content,
        });
        useAlert(this.$t('CONVERSATION.EDIT_MESSAGE.SUCCESS'));
        this.closeEditModal();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.EDIT_MESSAGE.ERROR'));
      } finally {
        this.isSavingEdit = false;
      }
    },
    openDeleteModal() {
      this.handleClose();
      this.showDeleteModal = true;
    },
    async confirmDeletion() {
      try {
        await this.$store.dispatch('deleteMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_DELETE_MESSAGE'));
        this.handleClose();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
      }
    },
    closeDeleteModal() {
      this.showDeleteModal = false;
    },
    openReactionModal() {
      this.isReactionModalOpen = true;
      this.handleClose();
    },
    closeReactionModal() {
      this.isReactionModalOpen = false;
    },
    async handleReactionSelect(emoji) {
      if (!emoji || this.isSendingReaction) return;

      this.isSendingReaction = true;
      try {
        await this.$store.dispatch('sendMessageReaction', {
          conversationId: this.conversationId,
          messageId: this.messageId,
          emoji,
        });
        this.isReactionModalOpen = false;
      } catch (error) {
        useAlert(this.$t('CONVERSATION.REACTION.ERROR'));
      } finally {
        this.isSendingReaction = false;
      }
    },
  },
};
</script>

<template>
  <div class="context-menu">
    <!-- Add To Canned Responses -->
    <woot-modal
      v-if="isCannedResponseModalOpen && enabledOptions['cannedResponse']"
      v-model:show="isCannedResponseModalOpen"
      :on-close="hideCannedResponseModal"
    >
      <AddCannedModal
        :response-content="plainTextContent"
        :on-close="hideCannedResponseModal"
      />
    </woot-modal>
    <!-- Reaction Picker -->
    <woot-modal
      v-if="isReactionModalOpen && enabledOptions['reaction']"
      v-model:show="isReactionModalOpen"
      :on-close="closeReactionModal"
    >
      <div class="p-4">
        <h4 class="text-base font-medium text-n-slate-12 mb-4">
          {{ $t('CONVERSATION.REACTION.TITLE') }}
        </h4>
        <EmojiInput
          class="!relative !top-0 !left-0 !right-auto !w-full max-w-sm mx-auto"
          :on-click="handleReactionSelect"
        />
      </div>
    </woot-modal>
    <!-- Confirm Deletion -->
    <woot-delete-modal
      v-if="showDeleteModal && enabledOptions['delete']"
      v-model:show="showDeleteModal"
      class="context-menu--delete-modal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDeletion"
      :title="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.TITLE')"
      :message="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.MESSAGE')"
      :confirm-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.DELETE')"
      :reject-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.CANCEL')"
    />
    <!-- Edit message -->
    <woot-modal
      v-if="isEditModalOpen && enabledOptions['edit']"
      v-model:show="isEditModalOpen"
      :on-close="closeEditModal"
    >
      <form class="flex flex-col gap-4 p-4" @submit.prevent="saveEdit">
        <div>
          <h4 class="mb-1 text-base font-medium text-n-slate-12">
            {{ $t('CONVERSATION.EDIT_MESSAGE.TITLE') }}
          </h4>
          <p class="m-0 text-sm text-n-slate-11">
            {{ $t('CONVERSATION.EDIT_MESSAGE.DESCRIPTION') }}
          </p>
        </div>
        <textarea
          v-model="editedContent"
          class="w-full min-h-28 px-3 py-2 text-sm rounded-lg resize-y bg-n-alpha-2 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
        />
        <div class="flex justify-end gap-2">
          <NextButton
            type="button"
            slate
            ghost
            :label="$t('CONVERSATION.EDIT_MESSAGE.CANCEL')"
            @click="closeEditModal"
          />
          <NextButton
            type="submit"
            :label="$t('CONVERSATION.EDIT_MESSAGE.SAVE')"
            :is-loading="isSavingEdit"
            :disabled="!editedContent.trim()"
          />
        </div>
      </form>
    </woot-modal>
    <NextButton
      v-if="!hideButton"
      ghost
      slate
      sm
      icon="i-lucide-ellipsis-vertical"
      class="visible md:invisible md:group-hover/context-menu:visible"
      @click="handleOpen"
    />
    <ContextMenu
      v-if="isOpen && !isCannedResponseModalOpen"
      :x="contextMenuPosition.x"
      :y="contextMenuPosition.y"
      @close="handleClose"
    >
      <div class="menu-container">
        <MenuItem
          v-if="enabledOptions['replyTo']"
          :option="{
            icon: 'arrow-reply',
            label: $t('CONVERSATION.CONTEXT_MENU.REPLY_TO'),
          }"
          variant="icon"
          @click.stop="handleReplyTo"
        />
        <MenuItem
          v-if="enabledOptions['reaction']"
          :option="{
            icon: 'emoji',
            label: $t('CONVERSATION.CONTEXT_MENU.REACTION'),
          }"
          variant="icon"
          @click.stop="openReactionModal"
        />
        <MenuItem
          v-if="enabledOptions['forward']"
          :option="{
            icon: 'share',
            label: $t('CONVERSATION.CONTEXT_MENU.FORWARD_MESSAGES'),
          }"
          variant="icon"
          @click.stop="handleForward"
        />
        <MenuItem
          v-if="enabledOptions['copy']"
          :option="{
            icon: 'clipboard',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY'),
          }"
          variant="icon"
          @click.stop="handleCopy"
        />
        <MenuItem
          v-if="enabledOptions['edit']"
          :option="{
            icon: 'edit',
            label: $t('CONVERSATION.CONTEXT_MENU.EDIT'),
          }"
          variant="icon"
          @click.stop="openEditModal"
        />
        <MenuItem
          v-if="enabledOptions['translate']"
          :option="{
            icon: 'translate',
            label: $t('CONVERSATION.CONTEXT_MENU.TRANSLATE'),
          }"
          variant="icon"
          @click.stop="handleTranslate"
        />
        <hr />
        <MenuItem
          v-if="enabledOptions['copyLink']"
          :option="{
            icon: 'link',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY_PERMALINK'),
          }"
          variant="icon"
          @click.stop="copyLinkToMessage"
        />
        <MenuItem
          v-if="enabledOptions['cannedResponse']"
          :option="{
            icon: 'comment-add',
            label: $t('CONVERSATION.CONTEXT_MENU.CREATE_A_CANNED_RESPONSE'),
          }"
          variant="icon"
          @click.stop="showCannedResponseModal"
        />
        <hr v-if="enabledOptions['delete']" />
        <MenuItem
          v-if="enabledOptions['delete']"
          :option="{
            icon: 'delete',
            label: $t('CONVERSATION.CONTEXT_MENU.DELETE'),
          }"
          variant="icon"
          @click.stop="openDeleteModal"
        />
      </div>
    </ContextMenu>
  </div>
</template>

<style lang="scss" scoped>
.menu-container {
  @apply p-1 bg-n-background shadow-xl rounded-md;

  hr:first-child {
    @apply hidden;
  }

  hr {
    @apply m-1 border-b border-solid border-n-strong;
  }
}

.context-menu--delete-modal {
  ::v-deep {
    .modal-container {
      @apply max-w-[30rem];

      h2 {
        @apply font-medium text-base;
      }
    }
  }
}
</style>

<script>
import { ref } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import FileUpload from 'vue-upload-component';
import * as ActiveStorage from 'activestorage';
import { mapGetters } from 'vuex';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useTrack } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { CAPTAIN_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import inboxMixin from 'shared/mixins/inboxMixin';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CopilotMenuBar from './CopilotMenuBar.vue';
import VideoCallButton from '../VideoCallButton.vue';
import { REPLY_EDITOR_MODES, CHAR_LENGTH_WARNING } from './constants';

export default {
  name: 'CompactReplyComposer',
  components: {
    CopilotMenuBar,
    FileUpload,
    NextButton,
    VideoCallButton,
  },
  directives: {
    OnClickOutside: vOnClickOutside,
  },
  mixins: [inboxMixin],
  props: {
    mode: {
      type: String,
      default: REPLY_EDITOR_MODES.REPLY,
    },
    conversationId: {
      type: Number,
      required: true,
    },
    inbox: {
      type: Object,
      default: () => ({}),
    },
    editorContent: {
      type: String,
      default: '',
    },
    hasContent: {
      type: Boolean,
      default: false,
    },
    isSendDisabled: {
      type: Boolean,
      default: false,
    },
    isEditorDisabled: {
      type: Boolean,
      default: false,
    },
    isReplyRestricted: {
      type: Boolean,
      default: false,
    },
    showFileUpload: {
      type: Boolean,
      default: false,
    },
    showAudioRecorder: {
      type: Boolean,
      default: false,
    },
    enableMultipleFileUpload: {
      type: Boolean,
      default: true,
    },
    newConversationModalActive: {
      type: Boolean,
      default: false,
    },
    conversationType: {
      type: String,
      default: '',
    },
    enableWhatsAppTemplates: {
      type: Boolean,
      default: false,
    },
    enableContentTemplates: {
      type: Boolean,
      default: false,
    },
    portalSlug: {
      type: String,
      default: '',
    },
    showPixButton: {
      type: Boolean,
      default: false,
    },
    showQuotedReplyToggle: {
      type: Boolean,
      default: false,
    },
    quotedReplyEnabled: {
      type: Boolean,
      default: false,
    },
    signaturePreferenceChannel: {
      type: String,
      default: '',
    },
    isMessageLengthReachingThreshold: {
      type: Boolean,
      default: false,
    },
    charactersRemaining: {
      type: Number,
      default: 0,
    },
    isRecordingAudio: {
      type: Boolean,
      default: false,
    },
    recordingAudioState: {
      type: String,
      default: '',
    },
    recordingAudioDurationText: {
      type: String,
      default: '00:00',
    },
    hasRecordedAudio: {
      type: Boolean,
      default: false,
    },
    isCopilotActive: {
      type: Boolean,
      default: false,
    },
    onFileUpload: {
      type: Function,
      default: () => {},
    },
    sendButtonText: {
      type: String,
      default: '',
    },
  },
  emits: [
    'cancelAudioRecorder',
    'executeCopilotAction',
    'openContactPicker',
    'restartAudioRecorder',
    'selectContentTemplate',
    'selectWhatsappTemplate',
    'send',
    'sendPixPayment',
    'setReplyMode',
    'toggleAudioRecorder',
    'toggleAudioRecorderPlayPause',
    'toggleEmojiPicker',
    'toggleInsertArticle',
    'toggleQuotedReply',
    'toggleStickerPicker',
    'schedule',
  ],
  setup(props, { emit }) {
    const uploadRef = ref(false);
    const showActionsMenu = ref(false);
    const showCopilotMenu = ref(false);
    const copilotToggleRef = ref(null);
    const { captainTasksEnabled } = useCaptain();
    const { setSignatureFlagForInbox, fetchSignatureFlagFromUISettings } =
      useUISettings();

    const toggleCopilotMenu = () => {
      const isOpening = !showCopilotMenu.value;
      if (isOpening) {
        useTrack(CAPTAIN_EVENTS.EDITOR_AI_MENU_OPENED, {
          conversationId: props.conversationId,
          entryPoint: 'compact_composer',
        });
      }
      showCopilotMenu.value = isOpening;
    };

    const handleCopilotAction = (actionKey, data) => {
      emit('executeCopilotAction', actionKey, data || props.editorContent);
      showCopilotMenu.value = false;
    };

    return {
      captainTasksEnabled,
      copilotToggleRef,
      fetchSignatureFlagFromUISettings,
      handleCopilotAction,
      setSignatureFlagForInbox,
      showActionsMenu,
      showCopilotMenu,
      toggleCopilotMenu,
      uploadRef,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    isNote() {
      return this.mode === REPLY_EDITOR_MODES.NOTE;
    },
    showAttachButton() {
      return !this.isEditorDisabled && (this.showFileUpload || this.isNote);
    },
    showAudioRecorderButton() {
      if (this.isEditorDisabled || this.isNote) return false;
      if (this.isALineChannel || this.isATiktokChannel) return false;

      return (
        this.showAudioRecorder &&
        this.isFeatureEnabledonAccount(
          this.accountId,
          FEATURE_FLAGS.VOICE_RECORDER
        )
      );
    },
    showContactPickerButton() {
      return (
        !this.isNote &&
        !this.isEditorDisabled &&
        (this.isAWhatsAppCloudChannel || this.isAUnoapiChannel)
      );
    },
    showStickerButton() {
      return (
        !this.isNote &&
        !this.isEditorDisabled &&
        (this.isAWhatsAppCloudChannel || this.isAUnoapiChannel)
      );
    },
    showScheduleButton() {
      return !this.isNote && this.inbox.channel_type === 'Channel::Whatsapp';
    },
    showMessageSignatureButton() {
      return !this.isNote && !this.isEditorDisabled && !this.isAUnoapiChannel;
    },
    showVideoCallButton() {
      return (
        (this.isAWebWidgetInbox || this.isAPIInbox) &&
        !this.isNote &&
        !this.isEditorDisabled
      );
    },
    showSecondaryActions() {
      return (
        this.enableWhatsAppTemplates ||
        this.enableContentTemplates ||
        this.portalSlug ||
        this.showMessageSignatureButton ||
        this.showQuotedReplyToggle ||
        this.showVideoCallButton
      );
    },
    sendWithSignature() {
      if (this.isAUnoapiChannel) return false;

      return this.fetchSignatureFlagFromUISettings(
        this.signaturePreferenceChannel || this.channelType,
        false
      );
    },
    signatureToggleTooltip() {
      return this.sendWithSignature
        ? this.$t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
        : this.$t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP');
    },
    allowedFileTypes() {
      if (this.isNote) return getAllowedFileTypesByChannel();

      let channelType = this.channelType || this.inbox?.channel_type;
      if (
        this.isAnInstagramChannel ||
        this.conversationType === 'instagram_direct_message'
      ) {
        channelType = INBOX_TYPES.INSTAGRAM;
      }

      return getAllowedFileTypesByChannel({
        channelType,
        medium: this.inbox?.medium,
      });
    },
    enableDragAndDrop() {
      return !this.newConversationModalActive;
    },
    audioActionIcon() {
      if (!this.recordingAudioState) return 'i-ph-stop-fill';
      return this.recordingAudioState === 'playing'
        ? 'i-ph-pause-fill'
        : 'i-ph-play-fill';
    },
    charLengthClass() {
      return this.charactersRemaining < 0 ? 'text-n-ruby-9' : 'text-n-slate-11';
    },
    characterLengthWarning() {
      return this.charactersRemaining < 0
        ? `${-this.charactersRemaining} ${CHAR_LENGTH_WARNING.NEGATIVE}`
        : `${this.charactersRemaining} ${CHAR_LENGTH_WARNING.UNDER_50}`;
    },
    quotedReplyLabel() {
      return this.quotedReplyEnabled
        ? this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.DISABLE_TOOLTIP')
        : this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.ENABLE_TOOLTIP');
    },
    replyModeLabel() {
      return this.isNote
        ? this.$t('CONVERSATION.REPLYBOX.COMPACT.BACK_TO_REPLY')
        : this.$t('CONVERSATION.REPLYBOX.COMPACT.PRIVATE_NOTE');
    },
  },
  mounted() {
    ActiveStorage.start();
  },
  methods: {
    closeActionsMenu() {
      this.showActionsMenu = false;
    },
    openContactPicker() {
      this.$emit('openContactPicker');
      this.closeActionsMenu();
    },
    selectContentTemplate() {
      this.$emit('selectContentTemplate');
      this.closeActionsMenu();
    },
    selectWhatsappTemplate() {
      this.$emit('selectWhatsappTemplate');
      this.closeActionsMenu();
    },
    sendPixPayment() {
      this.$emit('sendPixPayment');
      this.closeActionsMenu();
    },
    scheduleMessage() {
      this.$emit('schedule');
      this.closeActionsMenu();
    },
    toggleEmojiPicker() {
      this.$emit('toggleEmojiPicker');
      this.closeActionsMenu();
    },
    toggleInsertArticle() {
      this.$emit('toggleInsertArticle');
      this.closeActionsMenu();
    },
    toggleQuotedReply() {
      this.$emit('toggleQuotedReply');
      this.closeActionsMenu();
    },
    toggleStickerPicker() {
      this.$emit('toggleStickerPicker');
      this.closeActionsMenu();
    },
    toggleReplyMode() {
      const mode = this.isNote
        ? REPLY_EDITOR_MODES.REPLY
        : REPLY_EDITOR_MODES.NOTE;
      if (mode === REPLY_EDITOR_MODES.REPLY && this.isReplyRestricted) return;
      this.$emit('setReplyMode', mode);
      this.closeActionsMenu();
    },
    toggleMessageSignature() {
      this.setSignatureFlagForInbox(
        this.signaturePreferenceChannel || this.channelType,
        !this.sendWithSignature
      );
      this.closeActionsMenu();
    },
  },
};
</script>

<template>
  <div
    class="compact-composer"
    :class="{
      'compact-composer--note': isNote,
      'compact-composer--audio': isRecordingAudio,
      'compact-composer--copilot': isCopilotActive,
    }"
  >
    <template v-if="isRecordingAudio">
      <div class="compact-composer__audio-actions">
        <NextButton
          v-tooltip.top="$t('CONVERSATION.REPLYBOX.COMPACT.DISCARD_AUDIO')"
          icon="i-ph-trash"
          color="ruby"
          variant="ghost"
          sm
          @click="$emit('cancelAudioRecorder')"
        />
        <NextButton
          :icon="audioActionIcon"
          color="slate"
          variant="outline"
          sm
          class="!rounded-full"
          @click="$emit('toggleAudioRecorderPlayPause')"
        />
      </div>
      <div class="compact-composer__audio-wave">
        <slot name="audio" />
      </div>
      <span class="text-sm tabular-nums text-n-slate-12">
        {{ recordingAudioDurationText || '00:00' }}
      </span>
      <NextButton
        v-if="recordingAudioState"
        v-tooltip.top="$t('CONVERSATION.REPLYBOX.COMPACT.RECORD_AGAIN')"
        icon="i-ph-microphone"
        color="ruby"
        variant="ghost"
        sm
        @click="$emit('restartAudioRecorder')"
      />
      <NextButton
        v-if="hasRecordedAudio"
        v-tooltip.top="sendButtonText"
        icon="i-lucide-send"
        color="blue"
        sm
        class="!rounded-full"
        :disabled="isSendDisabled"
        @click="$emit('send')"
      />
    </template>

    <template v-else>
      <div v-if="!isCopilotActive" class="compact-composer__leading">
        <div
          v-on-click-outside="closeActionsMenu"
          class="relative flex items-center"
        >
          <NextButton
            v-tooltip.top="$t('CONVERSATION.REPLYBOX.COMPACT.MORE_ACTIONS')"
            icon="i-lucide-plus"
            color="slate"
            variant="ghost"
            sm
            class="!rounded-full"
            :aria-expanded="showActionsMenu"
            @click="showActionsMenu = !showActionsMenu"
          />
          <div v-if="showActionsMenu" class="compact-composer__menu">
            <button
              v-if="!isEditorDisabled"
              type="button"
              class="compact-composer__menu-item"
              @click="toggleEmojiPicker"
            >
              <span class="i-ph-smiley-sticker size-4" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.EMOJI') }}
            </button>
            <button
              v-if="showContactPickerButton"
              type="button"
              class="compact-composer__menu-item"
              @click="openContactPicker"
            >
              <span class="i-ph-address-book-tabs size-4" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.CONTACT') }}
            </button>
            <button
              v-if="showPixButton"
              type="button"
              class="compact-composer__menu-item"
              @click="sendPixPayment"
            >
              <span class="i-lucide-qr-code size-4 text-n-teal-10" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.PIX') }}
            </button>
            <button
              v-if="showStickerButton"
              type="button"
              class="compact-composer__menu-item"
              @click="toggleStickerPicker"
            >
              <span class="i-ph-sticker size-4" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.STICKER') }}
            </button>
            <button
              v-if="showScheduleButton"
              type="button"
              class="compact-composer__menu-item"
              :disabled="isSendDisabled"
              @click="scheduleMessage"
            >
              <span class="i-lucide-calendar-clock size-4" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.SCHEDULE') }}
            </button>

            <div
              v-if="showSecondaryActions"
              class="compact-composer__separator"
            />
            <button
              v-if="enableWhatsAppTemplates"
              type="button"
              class="compact-composer__menu-item"
              @click="selectWhatsappTemplate"
            >
              <span class="i-ph-whatsapp-logo size-4" />
              {{ $t('CONVERSATION.FOOTER.WHATSAPP_TEMPLATES') }}
            </button>
            <button
              v-if="enableContentTemplates"
              type="button"
              class="compact-composer__menu-item"
              @click="selectContentTemplate"
            >
              <span class="i-ph-whatsapp-logo size-4" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.CONTENT_TEMPLATES') }}
            </button>
            <button
              v-if="portalSlug"
              type="button"
              class="compact-composer__menu-item"
              @click="toggleInsertArticle"
            >
              <span class="i-ph-article-ny-times size-4" />
              {{ $t('CONVERSATION.REPLYBOX.COMPACT.ARTICLE') }}
            </button>
            <button
              v-if="showMessageSignatureButton"
              type="button"
              class="compact-composer__menu-item"
              @click="toggleMessageSignature"
            >
              <span class="i-ph-signature size-4" />
              {{ signatureToggleTooltip }}
            </button>
            <button
              v-if="showQuotedReplyToggle"
              type="button"
              class="compact-composer__menu-item"
              @click="toggleQuotedReply"
            >
              <span class="i-ph-quotes size-4" />
              {{ quotedReplyLabel }}
            </button>
            <VideoCallButton
              v-if="showVideoCallButton"
              :conversation-id="conversationId"
              menu-item
              @action-complete="closeActionsMenu"
            />

            <div class="compact-composer__separator" />
            <button
              type="button"
              class="compact-composer__menu-item"
              :disabled="isNote && isReplyRestricted"
              @click="toggleReplyMode"
            >
              <span
                :class="isNote ? 'i-ph-chat-circle-text' : 'i-ph-note-pencil'"
                class="size-4"
              />
              {{ replyModeLabel }}
            </button>
          </div>
        </div>

        <FileUpload
          v-if="showAttachButton"
          ref="uploadRef"
          v-tooltip.top="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
          input-id="conversationAttachment"
          :size="4096 * 4096"
          :accept="allowedFileTypes"
          :multiple="enableMultipleFileUpload"
          :drop="enableDragAndDrop"
          :drop-directory="false"
          :data="{
            direct_upload_url: '/rails/active_storage/direct_uploads',
            direct_upload: true,
          }"
          @input-file="onFileUpload"
        >
          <NextButton
            icon="i-ph-paperclip"
            color="slate"
            variant="ghost"
            sm
            class="!rounded-full"
          />
        </FileUpload>
      </div>

      <div class="compact-composer__editor">
        <span
          v-if="isNote && !isCopilotActive"
          class="compact-composer__note-label"
        >
          {{ $t('CONVERSATION.REPLYBOX.COMPACT.PRIVATE_NOTE_ACTIVE') }}
        </span>
        <slot />
      </div>

      <div v-if="!isCopilotActive" class="compact-composer__trailing">
        <span
          v-if="isMessageLengthReachingThreshold"
          class="hidden text-xs sm:inline"
          :class="charLengthClass"
        >
          {{ characterLengthWarning }}
        </span>
        <div v-if="captainTasksEnabled" class="relative flex items-center">
          <NextButton
            ref="copilotToggleRef"
            v-tooltip.top="$t('CONVERSATION.REPLYBOX.COMPACT.AI')"
            icon="i-ph-sparkle-fill"
            variant="ghost"
            sm
            class="!rounded-full text-n-violet-9 hover:enabled:!bg-n-violet-3"
            :disabled="isEditorDisabled"
            @click="toggleCopilotMenu"
          />
          <CopilotMenuBar
            v-if="showCopilotMenu"
            v-on-click-outside="[
              () => (showCopilotMenu = false),
              { ignore: [copilotToggleRef] },
            ]"
            :has-selection="false"
            :has-content="hasContent"
            :conversation-id="conversationId"
            class="ltr:right-0 rtl:left-0 bottom-full mb-2"
            @execute-copilot-action="handleCopilotAction"
          />
        </div>
        <NextButton
          v-if="!hasContent && showAudioRecorderButton"
          v-tooltip.top="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
          icon="i-ph-microphone"
          color="blue"
          variant="ghost"
          sm
          class="!rounded-full"
          @click="$emit('toggleAudioRecorder')"
        />
        <NextButton
          v-else
          v-tooltip.top="sendButtonText"
          icon="i-lucide-send"
          :color="isNote ? 'amber' : 'blue'"
          sm
          class="!rounded-full"
          :disabled="isSendDisabled"
          @click="$emit('send')"
        />
      </div>
    </template>

    <transition name="modal-fade">
      <div
        v-show="uploadRef && uploadRef.dropActive"
        class="fixed inset-0 z-20 flex h-full w-full flex-col items-center justify-center gap-2 bg-modal-backdrop-light text-n-slate-12 dark:bg-modal-backdrop-dark"
      >
        <span class="i-ph-cloud-arrow-up size-10" />
        <h4 class="text-2xl break-words text-n-slate-12">
          {{ $t('CONVERSATION.REPLYBOX.DRAG_DROP') }}
        </h4>
      </div>
    </transition>
  </div>
</template>

<style lang="scss" scoped>
.compact-composer {
  @apply relative flex min-h-14 w-full items-center gap-1 rounded-2xl border border-n-weak bg-n-solid-1 px-2 py-1.5;
}

.compact-composer--note {
  @apply border-n-amber-6/40 bg-n-solid-amber;
}

.compact-composer--copilot {
  @apply items-stretch py-2;

  .compact-composer__editor {
    @apply block w-full;
  }

  :deep(.copilot-editor__content) {
    @apply mb-0;
  }
}

.compact-composer__leading,
.compact-composer__trailing,
.compact-composer__audio-actions {
  @apply flex flex-shrink-0 items-center gap-1;
}

.compact-composer__editor,
.compact-composer__audio-wave {
  @apply min-w-0 flex-1;
}

.compact-composer__editor {
  @apply flex items-center gap-2;
}

.compact-composer__note-label {
  @apply hidden flex-shrink-0 rounded-md bg-n-amber-4 px-2 py-1 text-xs font-medium text-n-amber-12 sm:inline-flex;
}

.compact-composer__menu {
  @apply absolute bottom-full left-0 z-50 mb-2 flex min-w-56 flex-col gap-0.5 rounded-xl border border-n-weak bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px];
}

.compact-composer__menu-item {
  @apply flex h-9 w-full items-center gap-3 rounded-lg border-0 px-3 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2 disabled:pointer-events-none disabled:opacity-50;
}

.compact-composer__separator {
  @apply mx-2 my-1 h-px bg-n-alpha-2;
}

:deep(.file-uploads label) {
  @apply cursor-pointer;
}

:deep(.ProseMirror-menubar-wrapper) {
  @apply gap-0;
}

:deep(.ProseMirror-woot-style) {
  min-height: 1.5rem !important;
  max-height: 6rem !important;
  @apply overflow-y-auto py-1;
}

:deep(.ProseMirror p) {
  @apply mb-0;
}

:deep(.ProseMirror p.empty-node:first-child::before) {
  @apply text-n-slate-10;
  white-space: nowrap;
}

.compact-composer__audio-wave :deep(> div) {
  @apply p-0;
}

@media (max-width: 639px) {
  .compact-composer {
    @apply min-h-12 rounded-xl px-1 py-1;
  }

  :deep(.ProseMirror-woot-style) {
    max-height: 4.5rem !important;
  }

  :deep(.ProseMirror p.empty-node:first-child::before) {
    content: '' !important;
  }

  .compact-composer__menu {
    @apply fixed bottom-16 left-2 right-2 min-w-0;
  }
}
</style>

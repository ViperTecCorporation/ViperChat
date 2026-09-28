import fileUploadMixin from './fileUploadMixin';
import { isEditableMedia, MEDIA_LIMIT } from 'dashboard/helper/mediaProfiles';
import { createPendingMessage } from 'dashboard/helper/commons';
import { DirectUpload, needsMultipart } from 'dashboard/helper/multipartUpload';
import {
  getDirectUploadUrl,
  setDirectUploadAuthHeaders,
} from 'dashboard/helper/directUploadsHelper';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { useAlert } from 'dashboard/composables';
import { getUndefinedVariablesInMessage } from '@chatwoot/utils';

export default {
  data() {
    return { mediaEditorFiles: [], mediaEditorSession: null };
  },
  watch: {
    accountId() {
      this.closeMediaEditor();
    },
    'currentChat.id'() {
      this.closeMediaEditor();
    },
    replyType() {
      this.closeMediaEditor();
    },
  },
  beforeUnmount() {
    this.closeMediaEditor();
  },
  methods: {
    onFileUpload(item) {
      const file = item?.file;
      if (!file) return false;
      if (this.mediaEditorFiles.some(existing => existing === file))
        return false;
      const canEdit =
        !this.isPrivate &&
        !this.isOnPrivateNote &&
        !this.isEditorDisabled &&
        !this.isReplyRestricted &&
        this.showFileUpload &&
        !this.attachedFiles.length &&
        !this.attachedContacts.length &&
        (this.isAUnoapiChannel ||
          this.isAWhatsAppCloudChannel ||
          this.is360DialogWhatsAppChannel ||
          this.isATwilioWhatsAppChannel);
      if (canEdit && isEditableMedia(file)) {
        if (this.mediaEditorFiles.length >= MEDIA_LIMIT) {
          useAlert(this.$t('MEDIA_EDITOR.QUEUE_LIMIT'));
          return false;
        }
        if (!this.mediaEditorSession)
          this.mediaEditorSession = {
            conversationId: this.currentChat.id,
            accountId: this.accountId,
            caption: this.message,
            reply: { ...this.inReplyTo },
            consumed: false,
          };
        this.mediaEditorFiles.push(file);
        return true;
      }
      if (this.mediaEditorSession) {
        useAlert(this.$t('MEDIA_EDITOR.UNSUPPORTED_FILE'));
        return false;
      }
      return fileUploadMixin.methods.onFileUpload.call(this, item);
    },
    closeMediaEditor() {
      this.mediaEditorFiles = [];
      this.mediaEditorSession = null;
    },
    async submitEditedMedia(file, caption, { videoQuality, onProgress } = {}) {
      const session = this.mediaEditorSession;
      const valid = () =>
        session &&
        this.mediaEditorSession === session &&
        this.currentChat.id === session.conversationId &&
        this.accountId === session.accountId &&
        !this.isPrivate &&
        !this.isEditorDisabled &&
        !this.isReplyRestricted &&
        this.showFileUpload;
      if (!valid()) return { ok: false, dispatched: false };
      if (
        getUndefinedVariablesInMessage({
          message: caption,
          variables: this.messageVariables,
        }).length
      ) {
        useAlert(this.$t('MEDIA_EDITOR.UNDEFINED_VARIABLES'));
        return { ok: false, dispatched: false };
      }
      const limit = this.maxSizeFor(file.type);
      if (!checkFileSizeLimit({ size: file.size }, limit)) {
        this.alertOverLimit(limit);
        return { ok: false, dispatched: false };
      }
      let attachment = file;
      const uploadProgress = event => {
        onProgress?.({
          phase:
            event.total && event.loaded >= event.total
              ? 'COMPLETING'
              : 'UPLOADING',
          percent: event.total
            ? Math.floor((event.loaded / event.total) * 100)
            : null,
          loaded: event.loaded,
          total: event.total,
        });
      };
      onProgress?.({ phase: 'PREPARING', percent: null });
      if (this.globalConfig.directUploadsEnabled || needsMultipart(file)) {
        try {
          attachment = await new Promise((resolve, reject) => {
            const upload = new DirectUpload(
              file,
              getDirectUploadUrl(
                `/api/v1/accounts/${this.accountId}/conversations/${session.conversationId}/direct_uploads`
              ),
              {
                indirect: !this.globalConfig.directUploadsEnabled,
                directUploadWillCreateBlobWithXHR: setDirectUploadAuthHeaders,
                onUploadProgress: onProgress,
                directUploadWillStoreFileWithXHR: xhr => {
                  xhr.upload.addEventListener('progress', uploadProgress);
                },
              }
            );
            upload.create((error, blob) =>
              error ? reject(error) : resolve(blob?.signed_id || file)
            );
          });
        } catch {
          return { ok: false, dispatched: false };
        }
      }
      if (!valid()) return { ok: false, dispatched: false };
      const payload = {
        conversationId: session.conversationId,
        files: [attachment],
        message: caption,
        private: false,
        sender: this.sender,
      };
      if (session.reply.id)
        payload.contentAttributes = { in_reply_to: session.reply.id };
      if (
        this.isAUnoapiChannel &&
        file.type.startsWith('video/') &&
        ['sd', 'hd'].includes(videoQuality)
      ) {
        payload.contentAttributes = {
          ...payload.contentAttributes,
          video_quality: videoQuality,
        };
      }
      const pending = createPendingMessage(
        this.withGroupMentionsInPayload(payload, caption)
      );
      // Once dispatched, retry belongs to the existing failed-message bubble, never to this editor.
      if (!session.consumed) {
        session.consumed = true;
        if (this.message === session.caption) {
          this.message = '';
          this.removeFromDraft();
        }
        this.resetReplyToMessage();
      }
      try {
        onProgress?.({
          phase: attachment === file ? 'UPLOADING' : 'COMPLETING',
          percent: null,
        });
        if (attachment === file) pending.onUploadProgress = uploadProgress;
        await this.$store.dispatch('sendMessageWithData', pending);
        return { ok: true, dispatched: true };
      } catch {
        return { ok: false, dispatched: true };
      } finally {
        delete pending.onUploadProgress;
      }
    },
  },
};

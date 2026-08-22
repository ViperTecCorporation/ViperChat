import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { getMaxUploadSizeByChannel } from '@chatwoot/utils';
import { DirectUpload } from 'activestorage';
import {
  getDirectUploadUrl,
  setDirectUploadAuthHeaders,
} from 'dashboard/helper/directUploadsHelper';
import { resolveMaximumFileUploadSize } from 'shared/helpers/FileHelper';
import { MAXIMUM_FILE_UPLOAD_SIZE } from 'shared/constants/messages';

export default {
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
    }),
    installationLimit() {
      return resolveMaximumFileUploadSize(
        this.globalConfig.maximumFileUploadSize
      );
    },
  },

  methods: {
    maxSizeFor(mime) {
      // Use default/installation limit for private notes
      if (this.isOnPrivateNote) {
        return this.installationLimit;
      }

      const globalLimit =
        Number(this.globalConfig?.maxFileUploadSizeInMb) ||
        MAXIMUM_FILE_UPLOAD_SIZE;

      if (this.isAUnoapiChannel) {
        return globalLimit;
      }

      const channelLimit = getMaxUploadSizeByChannel({
        channelType: this.inbox?.channel_type,
        medium: this.inbox?.medium,
        mime,
      });

      if (!channelLimit) {
        return globalLimit;
      }

      return Math.min(globalLimit, channelLimit);
    },
    alertOverLimit(maxSizeMB) {
      useAlert(
        this.$t('CONVERSATION.FILE_SIZE_LIMIT', {
          MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
        })
      );
    },
    onFileUpload(file) {
      if (this.globalConfig.directUploadsEnabled) {
        return this.onDirectFileUpload(file);
      }
      return this.onIndirectFileUpload(file);
    },

    onDirectFileUpload(file) {
      if (!file) return Promise.resolve(false);

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return Promise.resolve(false);
      }

      const upload = new DirectUpload(
        file.file,
        getDirectUploadUrl(
          `/api/v1/accounts/${this.accountId}/conversations/${this.currentChat.id}/direct_uploads`
        ),
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            setDirectUploadAuthHeaders(xhr);
          },
        }
      );

      return new Promise(resolve => {
        upload.create((error, blob) => {
          if (error) {
            useAlert(error);
            resolve(false);
            return;
          }

          resolve(this.attachFile({ file, blob }) !== false);
        });
      });
    },

    onIndirectFileUpload(file) {
      if (!file) return false;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return false;
      }

      return this.attachFile({ file }) !== false;
    },
  },
};

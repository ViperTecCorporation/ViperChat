import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { DirectUpload } from 'activestorage';
import { setDirectUploadAuthHeaders } from 'dashboard/helper/directUploadsHelper';
import { checkFileSizeLimit, resolveMaximumFileUploadSize } from 'shared/helpers/FileHelper';
import { MAXIMUM_FILE_UPLOAD_SIZE } from 'shared/constants/messages';

/**
 * Composable for handling file uploads in conversations
 * @param {Object} options
 * @param {Object} options.inbox - Current inbox object (has channel_type, medium, etc.)
 * @param {Function} options.attachFile - Callback to handle file attachment
 * @param {boolean} options.isPrivateNote - Whether the upload is for a private note
 */
export const useFileUpload = ({ inbox, attachFile, isPrivateNote = false }) => {
  const { t } = useI18n();

  const accountId = useMapGetter('getCurrentAccountId');
  const currentChat = useMapGetter('getSelectedChat');
  const globalConfig = useMapGetter('globalConfig/get');

  const installationLimit = resolveMaximumFileUploadSize(
    globalConfig.value?.maximumFileUploadSize
  );

  // helper: compute max upload size for a given file's mime
  const maxSizeFor = mime => {
    const configured =
      Number(globalConfig.value.maxFileUploadSizeInMb) || MAXIMUM_FILE_UPLOAD_SIZE;

    // Por enquanto usamos um limite global, independente do canal.
    // O valor é definido via env MAXIMUM_FILE_UPLOAD_SIZE (em MB),
    // com fallback para o constante padrão.
    return configured;
  };

  const alertOverLimit = maxSizeMB =>
    useAlert(
      t('CONVERSATION.FILE_SIZE_LIMIT', {
        MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
      })
    );

  const handleDirectFileUpload = file => {
    if (!file) return;

    const mime = file.file?.type || file.type;
    const maxSizeMB = maxSizeFor(mime);

    if (!checkFileSizeLimit(file, maxSizeMB)) {
      alertOverLimit(maxSizeMB);
      return;
    }

    const upload = new DirectUpload(
      file.file,
      `/api/v1/accounts/${accountId.value}/conversations/${currentChat.value.id}/direct_uploads`,
      {
        directUploadWillCreateBlobWithXHR: xhr => {
          setDirectUploadAuthHeaders(xhr);
        },
      }
    );

    upload.create((error, blob) => {
      if (error) {
        useAlert(error);
      } else {
        attachFile({ file, blob });
      }
    });
  };

  const handleIndirectFileUpload = file => {
    if (!file) return;

    const mime = file.file?.type || file.type;
    const maxSizeMB = maxSizeFor(mime);

    if (!checkFileSizeLimit(file, maxSizeMB)) {
      alertOverLimit(maxSizeMB);
      return;
    }

    attachFile({ file });
  };

  const onFileUpload = file => {
    if (globalConfig.value.directUploadsEnabled) {
      handleDirectFileUpload(file);
    } else {
      handleIndirectFileUpload(file);
    }
  };

  return { onFileUpload };
};

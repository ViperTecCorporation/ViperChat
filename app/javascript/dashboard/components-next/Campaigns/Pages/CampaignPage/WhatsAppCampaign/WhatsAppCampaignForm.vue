<script setup>
import { reactive, computed, watch, ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, helpers } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { MAXIMUM_FILE_UPLOAD_SIZE } from 'shared/constants/messages';
import { uploadFile } from 'dashboard/helper/uploadHelper';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const props = defineProps({
  initialData: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const formState = {
  uiFlags: useMapGetter('campaigns/getUIFlags'),
  labels: useMapGetter('labels/getLabels'),
  inboxes: useMapGetter('inboxes/getWhatsAppInboxes'),
  globalConfig: useMapGetter('globalConfig/get'),
  getFilteredWhatsAppTemplates: useMapGetter(
    'inboxes/getFilteredWhatsAppTemplates'
  ),
};

const initialState = {
  title: '',
  inboxId: null,
  templateId: null,
  scheduledAt: null,
  selectedAudience: [],
  message: '',
  audienceText: '',
  mediaBlobSignedId: null,
  mediaFileName: '',
};

const state = reactive({ ...initialState });
const templateParserRef = ref(null);
const mediaInputRef = ref(null);
const pendingTemplateSelection = ref(null);
const isUploadingMedia = ref(false);
const isApplyingInitialData = ref(false);

const selectedInbox = computed(() => {
  if (!state.inboxId) return null;
  return formState.inboxes.value.find(
    inbox => inbox.id === Number(state.inboxId)
  );
});

const isUnoapiInbox = computed(
  () => selectedInbox.value?.provider === 'unoapi'
);

const rules = computed(() => {
  const baseRules = {
    title: { required, minLength: minLength(1) },
    inboxId: { required },
    scheduledAt: { required },
  };

  if (isUnoapiInbox.value) {
    const hasUnoapiAudience = helpers.withMessage(
      t('CAMPAIGN.WHATSAPP.CREATE.FORM.UNOAPI_AUDIENCE.ERROR'),
      () =>
        state.audienceText.trim().length > 0 ||
        state.selectedAudience.length > 0
    );
    return {
      ...baseRules,
      message: { required, minLength: minLength(1) },
      audienceText: { hasUnoapiAudience },
    };
  }

  return {
    ...baseRules,
    templateId: { required },
    selectedAudience: { required },
  };
});

const v$ = useVuelidate(rules, state);

const isCreating = computed(() => formState.uiFlags.value.isCreating);
const maxUploadSize = computed(
  () =>
    Number(formState.globalConfig.value?.maxFileUploadSizeInMb) ||
    MAXIMUM_FILE_UPLOAD_SIZE
);

const currentDateTime = computed(() => {
  const now = new Date();
  const localTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
});

const mapToOptions = (items, valueKey, labelKey) =>
  items?.map(item => ({
    value: item[valueKey],
    label: item[labelKey],
  })) ?? [];

const audienceList = computed(() =>
  mapToOptions(formState.labels.value, 'id', 'title')
);

const inboxOptions = computed(() =>
  mapToOptions(formState.inboxes.value, 'id', 'name')
);

const templateOptions = computed(() => {
  if (!state.inboxId || isUnoapiInbox.value) return [];
  const templates = formState.getFilteredWhatsAppTemplates.value(state.inboxId);
  return templates.map(template => {
    const friendlyName = template.name
      .replace(/_/g, ' ')
      .replace(/\b\w/g, l => l.toUpperCase());

    return {
      value: template.id,
      label: `${friendlyName} (${template.language || 'en'})`,
      template,
    };
  });
});

const selectedTemplate = computed(() => {
  if (!state.templateId || !templateOptions.value.length) return null;
  return templateOptions.value.find(option => option.value === state.templateId)
    ?.template;
});

const getErrorMessage = (field, errorKey) => {
  const baseKey = 'CAMPAIGN.WHATSAPP.CREATE.FORM';
  const fieldState = v$.value[field];
  if (!fieldState) return '';
  return fieldState.$error ? t(`${baseKey}.${errorKey}.ERROR`) : '';
};

const formErrors = computed(() => ({
  title: getErrorMessage('title', 'TITLE'),
  inbox: getErrorMessage('inboxId', 'INBOX'),
  template: !isUnoapiInbox.value
    ? getErrorMessage('templateId', 'TEMPLATE')
    : '',
  message: isUnoapiInbox.value ? getErrorMessage('message', 'MESSAGE') : '',
  scheduledAt: getErrorMessage('scheduledAt', 'SCHEDULED_AT'),
  audience: isUnoapiInbox.value
    ? getErrorMessage('audienceText', 'UNOAPI_AUDIENCE')
    : getErrorMessage('selectedAudience', 'AUDIENCE'),
}));

const hasRequiredTemplateParams = computed(() => {
  if (isUnoapiInbox.value) return true;
  return templateParserRef.value?.v$?.$invalid === false || true;
});

const isSubmitDisabled = computed(
  () =>
    v$.value.$invalid ||
    !hasRequiredTemplateParams.value ||
    isUploadingMedia.value
);

const formatToUTCString = localDateTime =>
  localDateTime ? new Date(localDateTime).toISOString() : null;

const resetState = () => {
  Object.assign(state, initialState);
  v$.value.$reset();
};

const handleCancel = () => emit('cancel');

const parseUnoapiAudience = () => {
  const lines =
    state.audienceText
      ?.split('\n')
      .map(line => line.trim())
      .filter(line => line.length) || [];

  return lines.map(line => {
    const parts = line.split(';').map(part => part.trim());
    const [
      phoneNumber,
      name,
      identifier,
      email,
      value,
      dueAt,
      scheduledAt,
      waitForSeconds,
    ] = parts;

    const audience = {};
    if (name) audience.name = name;
    if (phoneNumber) audience.phone_number = phoneNumber;
    if (identifier) audience.identifier = identifier;
    if (email) audience.email = email;
    if (value) audience.value = value;
    if (dueAt) audience.due_at = dueAt;
    if (scheduledAt) audience.scheduled_at = scheduledAt;
    if (waitForSeconds && !Number.isNaN(Number(waitForSeconds))) {
      audience.wait_for_seconds = Number(waitForSeconds);
    }
    return audience;
  });
};

const formatUnoapiAudienceText = audience => {
  const rows = (audience || []).filter(entry => entry.type !== 'Label');
  if (!rows.length) return '';

  return rows
    .map(entry => {
      const parts = [
        entry.phone_number || '',
        entry.name || '',
        entry.identifier || '',
        entry.email || '',
        entry.value || '',
        entry.due_at || '',
        entry.scheduled_at || '',
        entry.wait_for_seconds || '',
      ];
      return parts.join(';').replace(/;+$/, '');
    })
    .join('\n');
};

const applyInitialData = async data => {
  if (!data) return;

  isApplyingInitialData.value = true;
  state.title = data.title || '';
  state.inboxId = data.inboxId || null;
  state.templateId = null;
  state.scheduledAt = null;
  state.message = data.message || '';
  state.mediaBlobSignedId = data.mediaBlobSignedId || null;
  state.mediaFileName = data.mediaFileName || '';

  const labelIds = (data.audience || [])
    .filter(entry => entry.type === 'Label')
    .map(entry => entry.id)
    .filter(Boolean);
  state.selectedAudience = labelIds;
  state.audienceText = formatUnoapiAudienceText(data.audience);

  const templateParams = data.templateParams || {};
  if (templateParams.name) {
    pendingTemplateSelection.value = {
      name: templateParams.name,
      language: templateParams.language,
    };
  } else {
    pendingTemplateSelection.value = null;
  }

  await nextTick();
  isApplyingInitialData.value = false;
};

const prepareCampaignDetails = () => {
  if (isUnoapiInbox.value) {
    return {
      title: state.title,
      message: state.message,
      inbox_id: state.inboxId,
      scheduled_at: formatToUTCString(state.scheduledAt),
      audience: [
        ...state.selectedAudience.map(id => ({ id, type: 'Label' })),
        ...parseUnoapiAudience(),
      ],
      media_blob_signed_id: state.mediaBlobSignedId,
    };
  }

  const currentTemplate = selectedTemplate.value;
  const parserData = templateParserRef.value;

  if (!currentTemplate) {
    return {
      title: state.title,
      message: '',
      template_params: {},
      inbox_id: state.inboxId,
      scheduled_at: formatToUTCString(state.scheduledAt),
      audience: [],
    };
  }

  const templateContent = parserData?.renderProcessedTemplate?.() || '';

  const templateParams = {
    name: currentTemplate?.name || '',
    namespace: currentTemplate?.namespace || '',
    category: currentTemplate?.category || 'UTILITY',
    language: currentTemplate?.language || 'en_US',
    processed_params: parserData?.processedParams || {},
  };

  return {
    title: state.title,
    message: templateContent,
    template_params: templateParams,
    inbox_id: state.inboxId,
    scheduled_at: formatToUTCString(state.scheduledAt),
    audience: state.selectedAudience?.map(id => ({
      id,
      type: 'Label',
    })),
  };
};

const handleMediaPick = () => {
  mediaInputRef.value?.click();
};

const handleMediaSelected = async event => {
  const file = event.target.files?.[0];
  if (!file) return;

  const isMediaFile =
    file.type?.startsWith('image/') || file.type?.startsWith('video/');
  if (!isMediaFile) {
    useAlert(t('CAMPAIGN.WHATSAPP.CREATE.FORM.MEDIA.ERROR'));
    event.target.value = '';
    return;
  }

  if (!checkFileSizeLimit(file, maxUploadSize.value)) {
    useAlert(
      t('CONVERSATION.FILE_SIZE_LIMIT', {
        MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxUploadSize.value,
      })
    );
    event.target.value = '';
    return;
  }

  isUploadingMedia.value = true;
  try {
    const { blobSignedId } = await uploadFile(file);
    state.mediaBlobSignedId = blobSignedId;
    state.mediaFileName = file.name;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.CREATE.FORM.MEDIA.UPLOAD_ERROR'));
    state.mediaBlobSignedId = null;
    state.mediaFileName = '';
  } finally {
    isUploadingMedia.value = false;
  }
};

const removeMedia = () => {
  state.mediaBlobSignedId = null;
  state.mediaFileName = '';
  if (mediaInputRef.value) mediaInputRef.value.value = '';
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  emit('submit', prepareCampaignDetails());
  resetState();
  handleCancel();
};

watch(
  () => state.inboxId,
  () => {
    if (isApplyingInitialData.value) return;
    state.templateId = null;
    state.selectedAudience = [];
    state.message = '';
    state.audienceText = '';
    state.mediaBlobSignedId = null;
    state.mediaFileName = '';
  }
);

watch(
  () => props.initialData,
  data => {
    applyInitialData(data);
  },
  { immediate: true }
);

watch(
  () => templateOptions.value,
  options => {
    if (!pendingTemplateSelection.value || !options.length) return;
    const { name, language } = pendingTemplateSelection.value;
    const match = options.find(option => {
      const template = option.template;
      return (
        template?.name === name &&
        (!language || template?.language === language)
      );
    });
    if (match) {
      state.templateId = match.value;
      pendingTemplateSelection.value = null;
    }
  }
);
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.title"
      :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TITLE.LABEL')"
      :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TITLE.PLACEHOLDER')"
      :message="formErrors.title"
      :message-type="formErrors.title ? 'error' : 'info'"
    />

    <div class="flex flex-col gap-1">
      <label for="inbox" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.INBOX.LABEL') }}
      </label>
      <ComboBox
        id="inbox"
        v-model="state.inboxId"
        :options="inboxOptions"
        :has-error="!!formErrors.inbox"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.INBOX.PLACEHOLDER')"
        :message="formErrors.inbox"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <template v-if="!isUnoapiInbox">
      <div class="flex flex-col gap-1">
        <label
          for="template"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.LABEL') }}
        </label>
        <ComboBox
          id="template"
          v-model="state.templateId"
          :options="templateOptions"
          :has-error="!!formErrors.template"
          :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.PLACEHOLDER')"
          :message="formErrors.template"
          class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        />
        <p class="mt-1 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.INFO') }}
        </p>
      </div>

      <WhatsAppTemplateParser
        v-if="selectedTemplate"
        ref="templateParserRef"
        :template="selectedTemplate"
      />

      <div class="flex flex-col gap-1">
        <label
          for="audience"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL') }}
        </label>
        <TagMultiSelectComboBox
          v-model="state.selectedAudience"
          :options="audienceList"
          :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL')"
          :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.PLACEHOLDER')"
          :has-error="!!formErrors.audience"
          :message="formErrors.audience"
          class="[&>div>button]:bg-n-alpha-black2"
        />
      </div>
    </template>

    <template v-else>
      <TextArea
        v-model="state.message"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.MESSAGE.LABEL')"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.MESSAGE.PLACEHOLDER')"
        show-character-count
        :message="formErrors.message"
        :message-type="formErrors.message ? 'error' : 'info'"
      />

      <div class="flex flex-col gap-1">
        <label
          for="audience"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL') }}
        </label>
        <TagMultiSelectComboBox
          v-model="state.selectedAudience"
          :options="audienceList"
          :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL')"
          :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.PLACEHOLDER')"
          :has-error="!!formErrors.audience"
          :message="formErrors.audience"
          class="[&>div>button]:bg-n-alpha-black2"
        />
      </div>

      <TextArea
        v-model="state.audienceText"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.UNOAPI_AUDIENCE.LABEL')"
        :placeholder="
          t('CAMPAIGN.WHATSAPP.CREATE.FORM.UNOAPI_AUDIENCE.PLACEHOLDER')
        "
        :rows="6"
        :message="formErrors.audience"
        :message-type="formErrors.audience ? 'error' : 'info'"
      />

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.MEDIA.LABEL') }}
        </label>
        <input
          ref="mediaInputRef"
          type="file"
          accept="image/*,video/*"
          class="hidden"
          @change="handleMediaSelected"
        />
        <div class="flex items-center gap-2">
          <Button
            variant="faded"
            color="slate"
            type="button"
            :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.MEDIA.BUTTON')"
            class="bg-n-alpha-2 text-n-blue-text hover:bg-n-alpha-3"
            @click="handleMediaPick"
          />
          <span
            v-if="state.mediaFileName"
            class="text-xs text-n-slate-11 truncate max-w-[12rem]"
          >
            {{ state.mediaFileName }}
          </span>
          <Button
            v-if="state.mediaFileName"
            variant="faded"
            color="ruby"
            type="button"
            icon="i-lucide-x"
            @click="removeMedia"
          />
        </div>
      </div>
    </template>

    <Input
      v-model="state.scheduledAt"
      :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SCHEDULED_AT.LABEL')"
      type="datetime-local"
      :min="currentDateTime"
      :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SCHEDULED_AT.PLACEHOLDER')"
      :message="formErrors.scheduledAt"
      :message-type="formErrors.scheduledAt ? 'error' : 'info'"
    />

    <div class="flex gap-3 justify-between items-center w-full">
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CREATE')"
        class="w-full"
        type="submit"
        :is-loading="isCreating"
        :disabled="isCreating || isSubmitDisabled"
      />
    </div>
  </form>
</template>

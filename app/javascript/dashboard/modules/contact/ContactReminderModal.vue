<script setup>
import { ref, computed, watch } from 'vue';
import { DirectUpload } from 'activestorage';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { setDirectUploadAuthHeaders } from 'dashboard/helper/directUploadsHelper';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import scheduledMessagesApi from 'dashboard/api/scheduledMessages';
import ScheduledMessageSequenceEditor from 'dashboard/routes/dashboard/conversation/components/ScheduledMessageSequenceEditor.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  conversationId: {
    type: [Number, String],
    default: null,
  },
  reminder: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');

const toDatetimeLocal = date => {
  const timezoneOffset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - timezoneOffset).toISOString().slice(0, 16);
};

const getInitialTime = () => {
  return props.reminder
    ? toDatetimeLocal(new Date(props.reminder.scheduledAt * 1000))
    : toDatetimeLocal(new Date(Date.now() + 3600000));
};

const scheduledAt = ref(getInitialTime());
const sendMessage = ref(props.reminder ? props.reminder.sendMessage : false);
const description = ref(props.reminder ? props.reminder.description : '');
const selectedLabelId = ref(props.reminder ? props.reminder.labelId : '');
const isSaving = ref(false);
const isUploading = ref(false);

const messages = ref(
  props.reminder
    ? (props.reminder.messages || []).map(msg => ({
        content: msg.content || '',
        content_type: msg.content_type || 'text',
        content_attributes: msg.content_attributes || {},
        voice_message: Boolean(msg.voice_message),
        attachments: (msg.attachment_blob_ids || []).map((signedId, index) => ({
          signedId,
          name: `Anexo ${index + 1}`,
          voiceMessage: Boolean(msg.voice_message),
        })),
      }))
    : [
        {
          content: '',
          content_type: 'text',
          content_attributes: {},
          voice_message: false,
          attachments: [],
        },
      ]
);

const audioRecordFormat = computed(() => AUDIO_FORMATS.MP3);
const allowedFileTypes = computed(() => '');

const labelOptions = computed(() =>
  (labels.value || []).map(label => ({ value: label.id, label: label.title }))
);

const messagesValid = computed(
  () =>
    messages.value.length >= 1 &&
    messages.value.length <= 5 &&
    messages.value.every(msg => msg.content?.trim() || msg.attachments?.length)
);

const minDatetime = computed(() =>
  toDatetimeLocal(new Date(Date.now() + 300000))
);

const resetForm = () => {
  scheduledAt.value = getInitialTime();
  messages.value = props.reminder
    ? (props.reminder.messages || []).map(msg => ({
        content: msg.content || '',
        content_type: msg.content_type || 'text',
        content_attributes: msg.content_attributes || {},
        voice_message: Boolean(msg.voice_message),
        attachments: (msg.attachment_blob_ids || []).map((signedId, index) => ({
          signedId,
          name: `Anexo ${index + 1}`,
          voiceMessage: Boolean(msg.voice_message),
        })),
      }))
    : [
        {
          content: '',
          content_type: 'text',
          content_attributes: {},
          voice_message: false,
          attachments: [],
        },
      ];
  sendMessage.value = props.reminder ? props.reminder.sendMessage : false;
  description.value = props.reminder ? props.reminder.description : '';
  selectedLabelId.value = props.reminder ? props.reminder.labelId : '';
};

watch(
  () => props.reminder,
  () => {
    resetForm();
  }
);

const uploadAttachment = ({ file, index, voiceMessage }) => {
  if (!file?.file) return;
  isUploading.value = true;
  const upload = new DirectUpload(
    file.file,
    '/rails/active_storage/direct_uploads',
    {
      directUploadWillCreateBlobWithXHR: xhr => {
        const user = store.getters.getCurrentUser;
        if (user?.access_token) {
          xhr.setRequestHeader('api_access_token', user.access_token);
        } else {
          setDirectUploadAuthHeaders(xhr);
        }
      },
    }
  );

  upload.create((error, blob) => {
    isUploading.value = false;
    if (error) {
      useAlert(error);
      return;
    }
    const message = messages.value[index];
    if (!message) return;
    message.attachments.push({
      signedId: blob.signed_id,
      name: blob.filename,
      voiceMessage,
    });
    message.voice_message = message.voice_message || Boolean(voiceMessage);
  });
};

const onSubmit = async hide => {
  if (!scheduledAt.value) {
    useAlert('Por favor, selecione uma data/hora.');
    return;
  }

  if (sendMessage.value && !messagesValid.value) {
    useAlert('Cada mensagem precisa ter conteúdo ou um anexo.');
    return;
  }

  isSaving.value = true;
  try {
    const firstMessageContent = messages.value[0]?.content || '';
    const taskReason = !sendMessage.value
      ? description.value
        ? `${firstMessageContent}\n\n${description.value}`
        : firstMessageContent
      : description.value;
    const scheduledMessage = {
      scheduled_at: new Date(scheduledAt.value).toISOString(),
      reason: taskReason,
      sender_id: store.getters.getCurrentUser.id,
      is_task: !sendMessage.value,
    };

    scheduledMessage.messages = messages.value.map(msg => ({
      content: msg.content,
      content_type: msg.content_type || 'text',
      content_attributes: msg.content_attributes || {},
      voice_message: Boolean(msg.voice_message),
      attachment_blob_ids: (msg.attachments || []).map(
        attachment => attachment.signedId
      ),
    }));

    if (selectedLabelId.value) {
      scheduledMessage.label_id = selectedLabelId.value;
    }
    const payload = {
      conversation_id: props.conversationId,
      scheduled_message: scheduledMessage,
    };

    if (props.reminder) {
      await scheduledMessagesApi.update(props.reminder.id, payload);
      useAlert('Agendamento atualizado com sucesso!');
    } else {
      await scheduledMessagesApi.create(payload);
      useAlert('Agendamento criado com sucesso!');
      resetForm();
    }
    hide();
    emit('close');
  } catch (error) {
    const serverError = error?.response?.data?.error;
    const details = error?.response?.data?.errors;
    const message =
      serverError ||
      (details ? details.join(', ') : null) ||
      'Erro ao criar agendamento. Tente novamente.';
    useAlert(message);
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <Popover
    @hide="
      resetForm();
      $emit('close');
    "
  >
    <slot name="trigger" />
    <template #content="{ hide }">
      <div class="w-full md:w-[32rem] p-6 flex flex-col gap-4">
        <div class="flex flex-col gap-2">
          <h3 class="text-base font-medium leading-6 text-n-slate-12">
            {{ reminder ? 'Reagendar Agendamento' : 'Criar Agendamento' }}
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            Agende uma mensagem para este contato.
          </p>
        </div>

        <form class="flex flex-col gap-4" @submit.prevent="onSubmit(hide)">
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              Data e Hora
            </label>
            <input
              v-model="scheduledAt"
              type="datetime-local"
              class="w-full px-3 py-2 border rounded-md border-n-weak bg-n-alpha-2 text-n-slate-12 focus:ring-1 focus:ring-w-500 focus:border-w-500"
              :min="minDatetime"
            />
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              Etiqueta
            </label>
            <Select
              v-model="selectedLabelId"
              :options="labelOptions"
              placeholder="Selecione uma etiqueta"
              class="w-full"
            />
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              Mensagens
            </label>
            <ScheduledMessageSequenceEditor
              v-model="messages"
              :audio-record-format="audioRecordFormat"
              :allowed-file-types="allowedFileTypes"
              :conversation-id="conversationId"
              :uploading="isUploading"
              @upload="uploadAttachment"
            />
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              Justificativa / Observação
            </label>
            <textarea
              v-model="description"
              rows="2"
              class="w-full px-3 py-2 border rounded-lg resize-y border-white/10 bg-white/5 backdrop-blur-md text-white placeholder-white/50 focus:ring-1 focus:ring-w-500 focus:border-w-500"
              placeholder="Ex: Retornar ligação ou motivo do agendamento"
            />
          </div>

          <div class="flex items-center gap-2">
            <input
              id="send-message-checkbox"
              v-model="sendMessage"
              type="checkbox"
              class="w-4 h-4 rounded text-w-500 border-n-slate-3 focus:ring-w-500"
            />
            <label
              for="send-message-checkbox"
              class="text-sm text-n-slate-11 cursor-pointer"
            >
              Enviar esta mensagem para o cliente no horário agendado
            </label>
          </div>

          <div class="flex flex-row justify-end w-full gap-2 mt-2">
            <NextButton
              faded
              slate
              type="reset"
              label="Cancelar"
              @click.prevent="hide"
            />
            <NextButton
              type="submit"
              :label="reminder ? 'Atualizar' : 'Criar Agendamento'"
              :is-loading="isSaving"
              :disabled="isUploading"
            />
          </div>
        </form>
      </div>
    </template>
  </Popover>
</template>

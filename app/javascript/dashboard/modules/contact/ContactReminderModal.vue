<script setup>
import { ref, computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import scheduledMessagesApi from 'dashboard/api/scheduledMessages';

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
  return props.reminder ? toDatetimeLocal(new Date(props.reminder.scheduledAt * 1000)) : toDatetimeLocal(new Date(Date.now() + 3600000));
};

const scheduledAt = ref(getInitialTime());
const note = ref(props.reminder ? props.reminder.messageContent : '');
const sendMessage = ref(props.reminder ? props.reminder.sendMessage : false);
const description = ref(props.reminder ? props.reminder.description : '');
const selectedLabelId = ref(props.reminder ? props.reminder.labelId : '');
const isSaving = ref(false);

const labelOptions = computed(() =>
  (labels.value || []).map(label => ({ value: label.id, label: label.title }))
);

const minDatetime = computed(() => toDatetimeLocal(new Date(Date.now() + 300000)));

const resetForm = () => {
  scheduledAt.value = getInitialTime();
  note.value = props.reminder ? props.reminder.messageContent : '';
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

const onSubmit = async hide => {
  if (!scheduledAt.value) {
    useAlert('Por favor, selecione uma data/hora.');
    return;
  }

  isSaving.value = true;
  try {
    const scheduledMessage = {
      scheduled_at: new Date(scheduledAt.value).toISOString(),
      reason: description.value,
      sender_id: store.getters.getCurrentUser.id,
      messages: [
        {
          content: note.value,
          content_type: 'text',
          content_attributes: {},
          voice_message: false,
          attachment_blob_ids: [],
        },
      ],
    };
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
    const message = serverError || (details ? details.join(', ') : null) || 'Erro ao criar agendamento. Tente novamente.';
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
      <div class="w-full md:w-96 p-6 flex flex-col gap-4">
        <div class="flex flex-col gap-2">
          <h3 class="text-base font-medium leading-6 text-n-slate-12">
            {{
              reminder
                ? 'Reagendar Agendamento'
                : 'Criar Agendamento'
            }}
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
              Nota / Mensagem
            </label>
            <textarea
              v-model="note"
              rows="3"
              class="w-full px-3 py-2 border rounded-lg resize-y border-white/10 bg-white/5 backdrop-blur-md text-white placeholder-white/50 focus:ring-1 focus:ring-w-500 focus:border-w-500"
              placeholder="Digite a mensagem que será enviada"
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
            />
          </div>
        </form>
      </div>
    </template>
  </Popover>
</template>

<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import DatePicker from 'vue-datepicker-next';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const reminderTime = ref(null);
const note = ref('');
const sendMessage = ref(false);
const isCreating = ref(false);

const lang = {
  days: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
  yearFormat: 'YYYY',
  monthFormat: 'MMMM',
};

const disabledDate = date => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return date < today;
};

const disabledTime = date => {
  const now = new Date();
  return date < now;
};

const resetForm = () => {
  reminderTime.value = null;
  note.value = '';
  sendMessage.value = false;
};

const onSubmit = async hide => {
  if (!reminderTime.value) {
    useAlert(t('CONTACT_PANEL.REMINDER.VALIDATION_ERROR'));
    return;
  }

  isCreating.value = true;
  try {
    await store.dispatch('contactReminders/create', {
      contactId: props.contactId,
      contact_reminder: {
        conversation_id: props.conversationId,
        scheduled_at: reminderTime.value.toISOString(),
        message_content: note.value,
        send_message: sendMessage.value,
      },
    });
    useAlert(t('CONTACT_PANEL.REMINDER.SUCCESS'));
    resetForm();
    hide();
    emit('close');
  } catch (error) {
    useAlert(t('CONTACT_PANEL.REMINDER.ERROR'));
  } finally {
    isCreating.value = false;
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
            {{ t('CONTACT_PANEL.REMINDER.TITLE') }}
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CONTACT_PANEL.REMINDER.DESC') }}
          </p>
        </div>

        <form class="flex flex-col gap-4" @submit.prevent="onSubmit(hide)">
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CONTACT_PANEL.REMINDER.DATE_TIME_LABEL') }}
            </label>
            <DatePicker
              v-model:value="reminderTime"
              type="datetime"
              input-class="mx-input"
              :lang="lang"
              :disabled-date="disabledDate"
              :disabled-time="disabledTime"
              :placeholder="t('CONTACT_PANEL.REMINDER.DATE_TIME_PLACEHOLDER')"
              class="w-full"
            />
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CONTACT_PANEL.REMINDER.NOTE_LABEL') }}
            </label>
            <textarea
              v-model="note"
              rows="3"
              class="w-full px-3 py-2 border rounded-md border-n-slate-3 bg-white text-n-slate-12 focus:ring-1 focus:ring-w-500 focus:border-w-500"
              :placeholder="t('CONTACT_PANEL.REMINDER.NOTE_PLACEHOLDER')"
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
              {{ t('CONTACT_PANEL.REMINDER.SEND_CHECKBOX') }}
            </label>
          </div>

          <div class="flex flex-row justify-end w-full gap-2 mt-2">
            <NextButton
              faded
              slate
              type="reset"
              :label="t('CONTACT_PANEL.REMINDER.CANCEL')"
              @click.prevent="hide"
            />
            <NextButton
              type="submit"
              :label="t('CONTACT_PANEL.REMINDER.SAVE')"
              :is-loading="isCreating"
            />
          </div>
        </form>
      </div>
    </template>
  </Popover>
</template>

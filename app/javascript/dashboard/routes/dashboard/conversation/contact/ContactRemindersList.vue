<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactReminderModal from 'dashboard/modules/contact/ContactReminderModal.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const remindersByContact = useMapGetter(
  'contactReminders/getAllRemindersByContactId'
);
const currentChat = useMapGetter('getSelectedChat');

const activeReminders = computed(() => {
  const all = remindersByContact.value(props.contactId) || [];
  return all.filter(r => !r.isCompleted);
});

onMounted(() => {
  store.dispatch('contactReminders/get', { contactId: props.contactId });
});

const formatDate = timestamp => {
  if (!timestamp) return '';
  const date = new Date(timestamp * 1000);
  return date.toLocaleString();
};

const onDelete = async reminderId => {
  /* eslint-disable-next-line no-alert, no-restricted-globals */
  const ok = confirm('Tem certeza que deseja cancelar este agendamento?');
  if (!ok) return;

  try {
    await store.dispatch('contactReminders/delete', {
      contactId: props.contactId,
      reminderId,
    });
    useAlert('Agendamento cancelado com sucesso.');
  } catch (error) {
    useAlert('Erro ao cancelar agendamento.');
  }
};
</script>

<template>
  <div>
    <div
      v-if="activeReminders.length > 0"
      class="flex flex-col gap-2 mt-4 w-full"
    >
      <span class="text-xs font-medium uppercase text-n-slate-11">
        {{ t('CONTACT_PANEL.REMINDER.ACTIVE_REMINDERS') }}
      </span>
      <div class="flex flex-col gap-3">
        <div
          v-for="reminder in activeReminders"
          :key="reminder.id"
          class="p-3 border rounded-lg border-n-slate-3 bg-n-slate-1 flex flex-col gap-1.5 relative group/reminder"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-semibold text-n-slate-12">
              {{ '📅 ' + formatDate(reminder.scheduledAt) }}
            </span>
            <div class="flex items-center gap-1">
              <!-- Edit Button using ContactReminderModal -->
              <ContactReminderModal
                :contact-id="contactId"
                :conversation-id="reminder.conversationId || currentChat.id"
                :reminder="reminder"
              >
                <template #trigger>
                  <Button
                    v-tooltip.top="'Editar'"
                    variant="faded"
                    color="slate"
                    size="xs"
                    icon="i-lucide-pencil"
                    class="opacity-0 group-hover/reminder:opacity-100 transition-opacity"
                  />
                </template>
              </ContactReminderModal>
              <!-- Delete Button -->
              <Button
                v-tooltip.top="'Excluir'"
                variant="faded"
                color="ruby"
                size="xs"
                icon="i-lucide-trash"
                class="opacity-0 group-hover/reminder:opacity-100 transition-opacity"
                @click="onDelete(reminder.id)"
              />
            </div>
          </div>

          <div class="text-xs text-n-slate-11 break-words">
            <span class="font-medium text-n-slate-12">
              {{ t('CONTACT_PANEL.REMINDER.ACTION') + ': ' }}
            </span>
            {{
              reminder.sendMessage
                ? t('CONTACT_PANEL.REMINDER.AUTO_MESSAGE')
                : t('CONTACT_PANEL.REMINDER.INTERNAL_ALERT')
            }}
          </div>

          <div
            v-if="reminder.messageContent"
            class="text-xs text-n-slate-11 break-words"
          >
            <span class="font-medium text-n-slate-12">
              {{ t('CONTACT_PANEL.REMINDER.CONTENT') + ': ' }}
            </span>
            {{ '"' + reminder.messageContent + '"' }}
          </div>

          <div
            v-if="reminder.description"
            class="text-xs text-n-slate-11 break-words italic bg-n-slate-2 p-1.5 rounded"
          >
            <span class="font-medium text-n-slate-12 not-italic">
              {{ t('CONTACT_PANEL.REMINDER.OBS') + ': ' }}
            </span>
            {{ reminder.description }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

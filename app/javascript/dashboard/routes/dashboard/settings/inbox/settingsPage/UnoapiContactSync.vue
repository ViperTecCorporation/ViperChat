<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SwitchControl from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const enabled = computed({
  get: () => props.modelValue,
  set: value => emit('update:modelValue', value),
});

const statusLabels = computed(() => ({
  disabled: t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.DISABLED'),
  waiting_connection: t(
    'INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.WAITING_CONNECTION'
  ),
  scheduled: t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.SCHEDULED'),
  running: t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.RUNNING'),
  completed: t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.COMPLETED'),
  failed: t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.FAILED'),
  paused: t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.PAUSED'),
}));

const statusLabel = computed(() => {
  return (
    statusLabels.value[props.inbox.contact_sync_status] ||
    statusLabels.value.disabled
  );
});

const progress = computed(() => {
  const processed = props.inbox.contact_sync_processed_count || 0;
  const failed = props.inbox.contact_sync_failed_count || 0;
  const total = props.inbox.contact_sync_total_count;
  const value = total ? `${processed}/${total}` : `${processed}`;

  return failed
    ? t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.PROGRESS_WITH_FAILURES', {
        progress: value,
        failed,
      })
    : value;
});
</script>

<template>
  <section>
    <div
      class="mt-6 mb-2 text-sm font-semibold uppercase tracking-wide text-slate-400"
    >
      {{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.SECTION') }}
    </div>

    <div
      class="w-full max-w-3xl rounded-lg border border-slate-200 p-4 dark:border-slate-700"
    >
      <label class="flex items-center gap-2">
        <SwitchControl v-model="enabled" class="shrink-0" />
        <span>{{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.LABEL') }}</span>
      </label>
      <p class="mt-2 text-sm text-slate-500">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.HELP') }}
      </p>
      <dl class="mt-3 grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
        <div>
          <dt class="text-slate-500">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS_LABEL') }}
          </dt>
          <dd class="font-medium text-slate-900 dark:text-slate-100">
            {{ statusLabel }}
          </dd>
        </div>
        <div>
          <dt class="text-slate-500">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.PROGRESS') }}
          </dt>
          <dd class="font-medium text-slate-900 dark:text-slate-100">
            {{ progress }}
          </dd>
        </div>
        <div v-if="inbox.contact_sync_completed_at">
          <dt class="text-slate-500">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.LAST_SYNC') }}
          </dt>
          <dd class="font-medium text-slate-900 dark:text-slate-100">
            {{ inbox.contact_sync_completed_at }}
          </dd>
        </div>
        <div v-if="inbox.contact_sync_next_run_at">
          <dt class="text-slate-500">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.NEXT_SYNC') }}
          </dt>
          <dd class="font-medium text-slate-900 dark:text-slate-100">
            {{ inbox.contact_sync_next_run_at }}
          </dd>
        </div>
      </dl>
      <p
        v-if="inbox.contact_sync_error"
        class="mt-3 rounded-md bg-ruby-50 p-2 text-sm text-ruby-700 dark:bg-ruby-900/30 dark:text-ruby-200"
      >
        {{ inbox.contact_sync_error }}
      </p>
    </div>
  </section>
</template>

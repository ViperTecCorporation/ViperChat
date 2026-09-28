<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import googleClient from 'dashboard/api/channel/googleClient';
import NextButton from 'dashboard/components-next/button/Button.vue';
import HistoryPeriod from './HistoryPeriod.vue';

const props = defineProps({ inboxId: { type: Number, required: true } });
const period = ref('none');
const history = ref({ status: 'not_started' });
const busy = ref(false);
const error = ref(false);
let active = true;
let timer;
const refresh = async () => {
  try {
    const { data } = await googleClient.getHistory(props.inboxId);
    if (active) history.value = data;
  } catch {
    if (active) error.value = true;
  }
};
const change = async stop => {
  busy.value = true;
  error.value = false;
  try {
    const { data } = stop
      ? await googleClient.stopHistory(props.inboxId)
      : await googleClient.startHistory(props.inboxId, period.value);
    if (active) history.value = data;
  } catch {
    error.value = true;
  } finally {
    busy.value = false;
  }
};
onMounted(() => {
  refresh();
  timer = setInterval(() => {
    if (history.value.status === 'running' && !busy.value) refresh();
  }, 15000);
});
onBeforeUnmount(() => {
  active = false;
  clearInterval(timer);
});
</script>

<template>
  <section class="mx-6 mb-6 p-4 border border-n-weak rounded-lg max-w-xl">
    <HistoryPeriod
      v-model="period"
      :disabled="busy || history.status === 'running'"
    />
    <p class="text-sm break-words" role="status">
      {{ $t(`INBOX_MGMT.GMAIL_HISTORY.STATES.${history.status}`) }}
    </p>
    <p v-if="history.day" class="text-sm text-n-slate-11">
      {{
        $t('INBOX_MGMT.GMAIL_HISTORY.PROGRESS', {
          day: history.day,
          count: history.processed || 0,
        })
      }}
    </p>
    <p v-if="error" role="alert" class="text-n-ruby-11">
      {{ $t('INBOX_MGMT.GMAIL_HISTORY.ERROR') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <NextButton
        v-if="history.status !== 'running'"
        type="button"
        :disabled="busy || period === 'none'"
        :label="$t('INBOX_MGMT.GMAIL_HISTORY.START')"
        @click="change(false)"
      />
      <NextButton
        v-else
        type="button"
        :disabled="busy"
        :label="$t('INBOX_MGMT.GMAIL_HISTORY.STOP')"
        @click="change(true)"
      />
      <NextButton
        type="button"
        variant="ghost"
        :label="$t('INBOX_MGMT.GMAIL_HISTORY.REFRESH')"
        @click="refresh"
      />
    </div>
  </section>
</template>

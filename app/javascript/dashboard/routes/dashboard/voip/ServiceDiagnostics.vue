<script setup>
import { ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { VoipAPI } from 'dashboard/api/voip';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  serviceId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const data = ref(null);
const loading = ref(false);
const busy = ref(false);
const error = ref('');
const success = ref(false);
const confirmation = ref(null);
const confirmationDialog = ref(null);
const resetCursor = ref(false);
let contextVersion = 0;
async function requestConfirmation(record) {
  const version = contextVersion;
  confirmation.value = record;
  resetCursor.value = false;
  error.value = '';
  success.value = false;
  await nextTick();
  if (version === contextVersion) confirmationDialog.value?.showModal();
}
function date(value) {
  return value ? new Date(value).toLocaleString() : '—';
}
async function load() {
  const version = contextVersion;
  loading.value = true;
  error.value = '';
  try {
    const response = await new VoipAPI(props.accountId).diagnostics(
      props.serviceId
    );
    if (version === contextVersion) data.value = response.data;
  } catch {
    if (version === contextVersion)
      error.value = t('AGENT_VOIP.DIAGNOSTICS.ERROR');
  } finally {
    if (version === contextVersion) loading.value = false;
  }
}
watch(
  () => [props.accountId, props.serviceId],
  () => {
    contextVersion += 1;
    data.value = null;
    confirmation.value = null;
    confirmationDialog.value?.close();
    success.value = false;
    busy.value = false;
    load();
  },
  { immediate: true }
);
async function confirm() {
  if (!confirmation.value || busy.value) return;
  const version = contextVersion;
  const operation = confirmation.value;
  const api = new VoipAPI(props.accountId);
  const serviceId = props.serviceId;
  busy.value = true;
  error.value = '';
  success.value = false;
  try {
    if (operation.kind === 'history')
      await api.recoverHistory(serviceId, { resetCursor: resetCursor.value });
    else await api.reprocess(serviceId, operation.kind, operation.id);
    if (version !== contextVersion) return;
    confirmation.value = null;
    confirmationDialog.value.close();
    success.value = true;
    await load();
  } catch (failure) {
    if (version === contextVersion) {
      error.value = t(
        failure.response?.status === 409
          ? 'AGENT_VOIP.DIAGNOSTICS.CONFLICT'
          : 'AGENT_VOIP.DIAGNOSTICS.ERROR'
      );
    }
  } finally {
    if (version === contextVersion) busy.value = false;
  }
}
</script>

<template>
  <div class="flex min-w-0 flex-col gap-4">
    <div
      class="flex flex-col items-start justify-between gap-2 sm:flex-row sm:items-center"
    >
      <p class="min-w-0 flex-1 text-sm text-n-slate-11">
        {{ t('AGENT_VOIP.DIAGNOSTICS.HELP') }}
      </p>
      <button
        type="button"
        :disabled="loading || busy"
        class="inline-flex min-h-11 items-center gap-2 rounded-full border border-n-weak px-4 text-sm disabled:opacity-50"
        @click="load"
      >
        <span aria-hidden="true" class="i-lucide-refresh-cw size-4 shrink-0" />
        {{ t('AGENT_VOIP.DIAGNOSTICS.REFRESH') }}
      </button>
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <p v-if="success" role="status" class="text-sm text-n-teal-11">
      {{ t('AGENT_VOIP.DIAGNOSTICS.QUEUED') }}
    </p>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ t('AGENT_VOIP.DIAGNOSTICS.LOADING') }}
    </p>
    <template v-if="data">
      <dl class="grid min-w-0 grid-cols-2 gap-3">
        <div
          v-for="key in [
            'pending_events',
            'failed_events',
            'pending_artifacts',
            'failed_artifacts',
          ]"
          :key="key"
          class="min-w-0 rounded-xl border border-n-weak p-3"
        >
          <dt class="break-words text-xs text-n-slate-11">
            {{ t(`AGENT_VOIP.DIAGNOSTICS.COUNTS.${key}`) }}
          </dt>
          <dd class="mt-1 text-xl font-semibold">{{ data.counts[key] }}</dd>
        </div>
      </dl>
      <section class="min-w-0 rounded-xl border border-n-weak p-3">
        <h3 class="flex items-center gap-2 font-semibold">
          <span aria-hidden="true" class="i-lucide-history size-4 shrink-0" />{{
            t('AGENT_VOIP.DIAGNOSTICS.RECOVERY')
          }}
        </h3>
        <p role="status" class="mt-2 text-sm">
          {{
            t(`AGENT_VOIP.DIAGNOSTICS.RECOVERY_STATE.${data.recovery.state}`)
          }}
        </p>
        <p
          v-if="data.recovery.gap_detected"
          role="alert"
          class="mt-2 text-sm text-n-ruby-11"
        >
          {{ t('AGENT_VOIP.DIAGNOSTICS.GAP_DETECTED') }}
        </p>
        <p v-if="data.recovery.has_more" class="mt-2 text-xs text-n-slate-11">
          {{ t('AGENT_VOIP.DIAGNOSTICS.HAS_MORE') }}
        </p>
        <dl class="mt-3 grid min-w-0 grid-cols-1 gap-3 text-sm sm:grid-cols-2">
          <div
            v-for="key in [
              'last_attempt_at',
              'last_success_at',
              'next_attempt_at',
            ]"
            :key="key"
            class="min-w-0"
          >
            <dt class="text-xs text-n-slate-11">
              {{ t(`AGENT_VOIP.DIAGNOSTICS.DATES.${key}`) }}
            </dt>
            <dd class="break-words">{{ date(data.recovery[key]) }}</dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-11">
              {{ t('AGENT_VOIP.DIAGNOSTICS.CHECKPOINT') }}
            </dt>
            <dd>
              {{
                t(
                  data.recovery.cursor_configured
                    ? 'AGENT_VOIP.DIAGNOSTICS.CHECKPOINT_SAVED'
                    : 'AGENT_VOIP.DIAGNOSTICS.CHECKPOINT_EMPTY'
                )
              }}
            </dd>
          </div>
        </dl>
        <p
          v-if="data.recovery.last_error_code"
          class="mt-2 break-all font-mono text-xs text-n-ruby-11"
        >
          {{ data.recovery.last_error_code }}
        </p>
        <button
          v-if="data.recovery.state !== 'unsupported'"
          type="button"
          :disabled="
            busy ||
            loading ||
            ['pending', 'running'].includes(data.recovery.state)
          "
          class="mt-3 inline-flex min-h-11 items-center gap-2 rounded-full border border-n-weak px-4 text-sm disabled:opacity-50"
          @click="requestConfirmation({ kind: 'history' })"
        >
          <span
            aria-hidden="true"
            class="i-lucide-cloud-download size-4 shrink-0"
          />{{ t('AGENT_VOIP.DIAGNOSTICS.RECOVER') }}
        </button>
      </section>
      <h3 class="font-semibold">{{ t('AGENT_VOIP.DIAGNOSTICS.RECORDS') }}</h3>
      <p v-if="!data.records.length" class="text-sm text-n-slate-11">
        {{ t('AGENT_VOIP.DIAGNOSTICS.EMPTY') }}
      </p>
      <ul class="m-0 flex min-w-0 list-none flex-col gap-3 p-0">
        <li
          v-for="record in data.records"
          :key="`${record.kind}:${record.id}`"
          class="flex min-w-0 flex-col gap-2 rounded-xl border border-n-weak p-3"
        >
          <div
            class="flex min-w-0 flex-wrap items-center justify-between gap-2"
          >
            <p class="break-all text-sm font-medium">
              {{ t(`AGENT_VOIP.DIAGNOSTICS.KIND.${record.kind}`) }} #{{
                record.id
              }}
            </p>
            <span class="break-words text-xs text-n-slate-11">{{
              record.state
            }}</span>
          </div>
          <p class="text-xs text-n-slate-11">
            {{
              t('AGENT_VOIP.DIAGNOSTICS.ATTEMPTS', { count: record.attempts })
            }}
            · {{ date(record.created_at) }}
          </p>
          <p v-if="record.next_attempt_at" class="text-xs text-n-slate-11">
            {{ t('AGENT_VOIP.DIAGNOSTICS.DATES.next_attempt_at') }}:
            {{ date(record.next_attempt_at) }}
          </p>
          <p
            v-if="record.last_error_code"
            class="break-all font-mono text-xs text-n-ruby-11"
          >
            {{ record.last_error_code }}
          </p>
          <button
            v-if="record.reprocessable"
            type="button"
            :disabled="busy || loading"
            class="inline-flex min-h-11 items-center gap-2 self-start rounded-full border border-n-weak px-4 text-sm disabled:opacity-50"
            @click="requestConfirmation(record)"
          >
            <span
              aria-hidden="true"
              class="i-lucide-rotate-cw size-4 shrink-0"
            />{{ t('AGENT_VOIP.DIAGNOSTICS.REPROCESS') }}
          </button>
        </li>
      </ul>
      <p v-if="data.truncated" class="text-xs text-n-slate-11">
        {{ t('AGENT_VOIP.DIAGNOSTICS.TRUNCATED') }}
      </p>
    </template>
    <dialog
      ref="confirmationDialog"
      :aria-label="t('AGENT_VOIP.DIAGNOSTICS.CONFIRM_TITLE')"
      class="m-auto max-h-[calc(100dvh_-_2rem)] w-[calc(100%_-_2rem)] max-w-sm overflow-y-auto rounded-xl border border-n-weak bg-n-surface-1 p-4 text-n-slate-12 backdrop:bg-black/50"
      @close="confirmation = null"
    >
      <div v-if="confirmation" class="flex min-w-0 flex-col gap-3">
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <h3 class="font-semibold">
          {{ t('AGENT_VOIP.DIAGNOSTICS.CONFIRM_TITLE') }}
        </h3>
        <p class="text-sm">
          {{
            t(
              confirmation.kind === 'history'
                ? 'AGENT_VOIP.DIAGNOSTICS.CONFIRM_RECOVERY'
                : 'AGENT_VOIP.DIAGNOSTICS.CONFIRM_REPROCESS'
            )
          }}
        </p>
        <p v-if="confirmation.id" class="break-all text-sm">
          {{ t(`AGENT_VOIP.DIAGNOSTICS.KIND.${confirmation.kind}`) }} #{{
            confirmation.id
          }}
        </p>
        <label
          v-if="confirmation.kind === 'history'"
          class="flex items-start gap-2 text-sm"
        >
          <input
            v-model="resetCursor"
            type="checkbox"
            :disabled="busy"
            class="mt-1 shrink-0"
          />
          <span>{{ t('AGENT_VOIP.DIAGNOSTICS.RESET_CURSOR') }}</span>
        </label>
        <p
          v-if="confirmation.kind === 'history' && resetCursor"
          role="status"
          class="text-sm text-n-ruby-11"
        >
          {{ t('AGENT_VOIP.DIAGNOSTICS.RESET_CURSOR_HELP') }}
        </p>
        <div class="flex flex-wrap justify-end gap-2">
          <button
            type="button"
            :disabled="busy"
            class="min-h-11 rounded-full border border-n-weak px-4 text-sm"
            @click="confirmationDialog.close()"
          >
            {{ t('AGENT_VOIP.CANCEL') }}
          </button>
          <button
            type="button"
            :disabled="busy"
            class="min-h-11 rounded-full bg-n-brand px-4 text-sm text-white disabled:opacity-50"
            @click="confirm"
          >
            {{ t('AGENT_VOIP.DIAGNOSTICS.CONFIRM') }}
          </button>
        </div>
      </div>
    </dialog>
  </div>
</template>

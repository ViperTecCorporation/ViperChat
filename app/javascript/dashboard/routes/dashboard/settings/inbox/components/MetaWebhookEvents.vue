<script setup>
/* global axios */
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import InboxesAPI from 'dashboard/api/inboxes';
import ButtonV4 from 'next/button/Button.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});
const { t, te, locale } = useI18n();
const { isAdmin } = useAdmin();
const route = useRoute();
const summary = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
const isSaving = ref(false);
const saveState = ref('');
const ignoreHistory = ref(true);
const ignoreGroups = ref(false);
const maxAgeDays = ref(7);
let requestId = 0;

const label = (key, values) =>
  t(`INBOX_MGMT.META_WEBHOOK_EVENTS.${key}`, values);
const validDays = computed(() => {
  const days = Number(maxAgeDays.value);
  return Number.isInteger(days) && days >= 1 && days <= 3650;
});
const applySettings = settings => {
  ignoreHistory.value = settings?.ignore_history_messages !== false;
  ignoreGroups.value = settings?.ignore_group_messages === true;
  maxAgeDays.value = settings?.history_max_age_days ?? 7;
};

const fetchEvents = async () => {
  requestId += 1;
  const currentRequest = requestId;
  summary.value = null;
  hasError.value = false;
  saveState.value = '';
  isSaving.value = false;
  applySettings(null);
  isLoading.value = isAdmin.value;
  if (!isAdmin.value) return;
  try {
    const { data } = await axios.get(
      `${InboxesAPI.url}/${props.inboxId}/management_events`
    );
    if (currentRequest !== requestId) return;
    summary.value = data;
    applySettings(data.history_settings);
  } catch {
    if (currentRequest === requestId) hasError.value = true;
  } finally {
    if (currentRequest === requestId) isLoading.value = false;
  }
};

const saveSettings = async () => {
  if (
    !isAdmin.value ||
    !summary.value ||
    isLoading.value ||
    isSaving.value ||
    (!ignoreHistory.value && !validDays.value)
  )
    return;
  const currentRequest = requestId;
  isSaving.value = true;
  saveState.value = '';
  try {
    const { data } = await axios.patch(
      `${InboxesAPI.url}/${props.inboxId}/coexistence_settings`,
      {
        ignore_history_messages: ignoreHistory.value,
        ignore_group_messages: ignoreGroups.value,
        history_max_age_days: validDays.value ? Number(maxAgeDays.value) : 7,
      }
    );
    if (currentRequest !== requestId) return;
    applySettings(data.history_settings);
    saveState.value = 'SAVED';
  } catch {
    if (currentRequest === requestId) saveState.value = 'SAVE_ERROR';
  } finally {
    if (currentRequest === requestId) isSaving.value = false;
  }
};

watch(
  [() => props.inboxId, () => route.params.accountId, isAdmin],
  fetchEvents,
  { immediate: true }
);
onBeforeUnmount(() => {
  requestId += 1;
});

const events = computed(() => (summary.value?.events || []).slice(0, 25));
const safeField = field => /^[a-z][a-z0-9_]*$/.test(field || '');
const supportedFields = computed(() =>
  (summary.value?.supported_fields || []).filter(safeField)
);
const graphVersion = computed(() =>
  /^v\d+\.\d+$/.test(summary.value?.graph_version || '')
    ? summary.value.graph_version
    : label('UNAVAILABLE')
);
const sessionVersion = computed(() =>
  /^\d+$/.test(summary.value?.session_info_version || '')
    ? summary.value.session_info_version
    : label('UNAVAILABLE')
);
const translatedValue = (group, value, fallback) => {
  const key = `INBOX_MGMT.META_WEBHOOK_EVENTS.${group}.${value}`;
  return te(key) ? t(key) : label(fallback);
};
const formatDate = value => {
  if (!value) return label('UNAVAILABLE');
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? label('UNAVAILABLE')
    : date.toLocaleString(locale.value.replace('_', '-'));
};

// Never render raw event payloads, identifiers, messages, contact data or errors.
const safeDetails = details => {
  const values = [];
  [
    'messages_count',
    'contacts_count',
    'history_count',
    'threads_count',
    'kept_messages_count',
    'dropped_messages_count',
    'invalid_messages_count',
    'imported_messages_count',
    'duplicate_messages_count',
    'pending_messages_count',
    'failed_messages_count',
  ].forEach(key => {
    if (Number.isSafeInteger(details?.[key]) && details[key] >= 0) {
      values.push({ key, value: details[key] });
    }
  });
  const limit = details?.max_daily_conversations_per_business;
  if (
    (Number.isSafeInteger(limit) && limit >= 0) ||
    /^TIER_(250|1K|2K|10K|100K|UNLIMITED)$/.test(limit || '')
  ) {
    values.push({ key: 'max_daily_conversations_per_business', value: limit });
  }
  if (['GREEN', 'YELLOW', 'RED', 'UNKNOWN'].includes(details?.quality_rating)) {
    values.push({
      key: 'quality_rating',
      value: label(`QUALITY.${details.quality_rating}`),
    });
  }
  return values;
};
</script>

<template>
  <section
    v-if="isAdmin"
    class="min-w-0 space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:p-5"
    :aria-label="label('TITLE')"
    :aria-busy="isLoading || isSaving"
  >
    <div class="flex min-w-0 flex-wrap items-center justify-between gap-3">
      <h3 class="text-heading-3 text-n-slate-12">{{ label('TITLE') }}</h3>
      <ButtonV4
        type="button"
        size="sm"
        :disabled="isLoading || isSaving"
        @click="fetchEvents"
      >
        {{ label(hasError ? 'RETRY' : 'REFRESH') }}
      </ButtonV4>
    </div>
    <p class="text-body-small text-n-slate-11">
      {{ label('SUBSCRIPTION_NOTICE') }}
    </p>
    <p v-if="isLoading" role="status" class="text-body-small text-n-slate-11">
      {{ label('LOADING') }}
    </p>
    <p v-else-if="hasError" role="alert" class="text-body-small text-n-ruby-11">
      {{ label('ERROR') }}
    </p>
    <template v-else-if="summary">
      <dl class="grid min-w-0 grid-cols-1 gap-2 text-body-small sm:grid-cols-2">
        <div>
          <dt class="text-n-slate-11">{{ label('GRAPH_VERSION') }}</dt>
          <dd class="m-0 text-n-slate-12">{{ graphVersion }}</dd>
        </div>
        <div>
          <dt class="text-n-slate-11">{{ label('SESSION_VERSION') }}</dt>
          <dd class="m-0 text-n-slate-12">{{ sessionVersion }}</dd>
        </div>
      </dl>
      <form
        class="min-w-0 space-y-3 rounded-lg border border-n-weak p-3"
        @submit.prevent="saveSettings"
      >
        <h4 class="text-body-main font-medium text-n-slate-12">
          {{ label('HISTORY_TITLE') }}
        </h4>
        <label class="flex items-start gap-2 text-body-small text-n-slate-12">
          <input
            v-model="ignoreHistory"
            type="checkbox"
            :disabled="isSaving"
            class="mt-1 shrink-0"
          />
          <span class="min-w-0">{{ label('IGNORE_HISTORY') }}</span>
        </label>
        <label
          v-if="!ignoreHistory"
          class="flex min-w-0 flex-col gap-1 text-body-small text-n-slate-12"
        >
          {{ label('MAX_AGE_DAYS') }}
          <input
            v-model="maxAgeDays"
            type="number"
            min="1"
            max="3650"
            step="1"
            required
            :disabled="isSaving"
            :aria-invalid="!validDays"
            class="!mb-0 w-full max-w-full sm:w-40"
          />
        </label>
        <p
          v-if="!ignoreHistory && !validDays"
          role="alert"
          class="text-body-small text-n-ruby-11"
        >
          {{ label('INVALID_DAYS') }}
        </p>
        <p class="text-body-small text-n-slate-11">
          {{ label('CUTOFF_NOTICE') }}
        </p>
        <p class="text-body-small text-n-amber-11">
          {{ label('REVIEW_NOTICE') }}
        </p>
        <label class="flex items-start gap-2 text-body-small text-n-slate-12">
          <input
            v-model="ignoreGroups"
            type="checkbox"
            data-testid="ignore-groups"
            :disabled="isSaving"
            :aria-describedby="`ignore-groups-notice-${inboxId}`"
            class="mt-1 shrink-0"
          />
          <span class="min-w-0">{{ label('IGNORE_GROUPS') }}</span>
        </label>
        <p
          :id="`ignore-groups-notice-${inboxId}`"
          class="text-body-small text-n-slate-11"
        >
          {{ label('IGNORE_GROUPS_NOTICE') }}
        </p>
        <ButtonV4
          type="submit"
          size="sm"
          :is-loading="isSaving"
          :disabled="isSaving || (!ignoreHistory && !validDays)"
        >
          {{ label('SAVE') }}
        </ButtonV4>
        <p
          v-if="saveState"
          :role="saveState === 'SAVE_ERROR' ? 'alert' : 'status'"
          class="text-body-small text-n-slate-11"
        >
          {{ label(saveState) }}
        </p>
      </form>
      <h4 class="text-body-main font-medium text-n-slate-12">
        {{ label('RECENT_EVENTS') }}
      </h4>
      <p v-if="!events.length" class="text-body-small text-n-slate-11">
        {{ label('EMPTY') }}
      </p>
      <ul v-else class="m-0 min-w-0 list-none space-y-2 p-0">
        <li
          v-for="event in events"
          :key="event.id"
          data-testid="management-event"
          class="min-w-0 space-y-1 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-body-small"
        >
          <div
            class="flex min-w-0 flex-col gap-1 sm:flex-row sm:justify-between sm:gap-3"
          >
            <span
              class="min-w-0 font-mono text-n-slate-12 [overflow-wrap:anywhere]"
            >
              {{ safeField(event.field) ? event.field : label('UNAVAILABLE') }}
            </span>
            <span class="text-n-slate-11">{{
              translatedValue('STATES', event.state, 'UNKNOWN_STATE')
            }}</span>
          </div>
          <p class="m-0 text-n-slate-11">
            {{ label('RECEIVED_AT', { date: formatDate(event.received_at) }) }}
          </p>
          <p v-if="event.reason" class="m-0 text-n-slate-11">
            {{ translatedValue('REASONS', event.reason, 'UNKNOWN_REASON') }}
          </p>
          <dl class="space-y-1">
            <div
              v-for="detail in safeDetails(event.details)"
              :key="detail.key"
              class="flex min-w-0 flex-wrap gap-x-2"
            >
              <dt class="text-n-slate-11">
                {{ label(`DETAILS.${detail.key}`) }}
              </dt>
              <dd class="m-0 text-n-slate-12 [overflow-wrap:anywhere]">
                {{ detail.value }}
              </dd>
            </div>
          </dl>
        </li>
      </ul>
      <details class="min-w-0 text-body-small text-n-slate-11">
        <summary class="cursor-pointer">
          {{ label('SUPPORTED_FIELDS') }}
        </summary>
        <ul class="mt-2 min-w-0 space-y-1 pl-4">
          <li
            v-for="field in supportedFields"
            :key="field"
            class="font-mono [overflow-wrap:anywhere]"
          >
            {{ field }}
          </li>
        </ul>
      </details>
    </template>
  </section>
</template>

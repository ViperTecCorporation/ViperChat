<script setup>
import { computed, ref, watch } from 'vue';
import Inboxes from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import WhatsappUnifiedReviews from './WhatsappUnifiedReviews.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const link = ref(null);
const candidates = ref([]);
const partnerInboxId = ref('');
const primaryInboxId = ref('');
const defaultProvider = ref('');
const enabled = ref(false);
const metaInitialMessagesEnabled = ref(false);
const metaInitialMessagesLimit = ref(5);
const preview = ref(null);
const confirmed = ref(false);
const busy = ref(false);
const loaded = ref(false);
const error = ref('');
const saved = ref(false);
const savedPayload = ref('');
const payload = computed(() => ({
  partner_inbox_id: Number(partnerInboxId.value),
  primary_inbox_id: Number(primaryInboxId.value),
  default_provider: defaultProvider.value,
  enabled: enabled.value,
  meta_initial_messages_enabled: metaInitialMessagesEnabled.value,
  meta_initial_messages_limit: metaInitialMessagesLimit.value,
}));
const inboxChoices = computed(() => [
  props.inbox,
  ...candidates.value.filter(
    inbox => inbox.id === Number(partnerInboxId.value)
  ),
]);
const validMetaInitialMessagesLimit = computed(
  () =>
    Number.isInteger(metaInitialMessagesLimit.value) &&
    metaInitialMessagesLimit.value >= 0 &&
    metaInitialMessagesLimit.value <= 1000
);
const valid = computed(
  () =>
    partnerInboxId.value &&
    primaryInboxId.value &&
    defaultProvider.value &&
    validMetaInitialMessagesLimit.value
);
const metaInitialMessagesId = computed(
  () => `whatsapp-meta-initial-messages-${props.inbox.id}`
);
const hasConflicts = computed(() => Boolean(preview.value?.conflicts?.length));
const locked = computed(() => Boolean(link.value?.activated_at));
const hasChanges = computed(
  () => loaded.value && JSON.stringify(payload.value) !== savedPayload.value
);
const settingsOnlyChange = computed(
  () =>
    hasChanges.value &&
    locked.value &&
    enabled.value === link.value.enabled &&
    Number(primaryInboxId.value) === link.value.primary_inbox_id &&
    Number(partnerInboxId.value) ===
      [link.value.primary_inbox_id, link.value.secondary_inbox_id].find(
        id => id !== props.inbox.id
      )
);
const canSave = computed(
  () =>
    valid.value &&
    !busy.value &&
    (settingsOnlyChange.value ||
      (preview.value &&
        !(enabled.value && hasConflicts.value) &&
        confirmed.value))
);
const noCandidates = computed(
  () => loaded.value && !locked.value && candidates.value.length === 0
);
const noCandidatesId = computed(
  () => `whatsapp-partner-empty-${props.inbox.id}`
);

function applyResponse(data) {
  link.value = data.link;
  candidates.value = data.candidates || [];
  const current = data.link;
  partnerInboxId.value = current
    ? [current.primary_inbox_id, current.secondary_inbox_id].find(
        id => id !== props.inbox.id
      )
    : '';
  primaryInboxId.value = current?.primary_inbox_id || '';
  defaultProvider.value = current?.default_provider || '';
  enabled.value = current?.enabled || false;
  metaInitialMessagesEnabled.value =
    current?.meta_initial_messages_enabled ?? false;
  metaInitialMessagesLimit.value = current?.meta_initial_messages_limit ?? 5;
  preview.value = null;
  confirmed.value = false;
  savedPayload.value = JSON.stringify(payload.value);
}

async function run(action, propagate = false) {
  busy.value = true;
  error.value = '';
  saved.value = false;
  try {
    await action();
  } catch (exception) {
    error.value = exception.response?.data?.error || exception.message;
    if (exception.response?.data?.preview) {
      preview.value = exception.response.data.preview;
      confirmed.value = false;
    }
    if (propagate) throw exception;
  } finally {
    busy.value = false;
  }
}

watch(payload, () => {
  preview.value = null;
  confirmed.value = false;
});
watch(
  () => props.inbox.id,
  () => {
    loaded.value = false;
    run(async () => {
      const { data } = await Inboxes.getWhatsappLink(props.inbox.id);
      applyResponse(data);
      loaded.value = true;
    });
  },
  { immediate: true }
);

function inspect() {
  if (!valid.value) return undefined;
  return run(async () => {
    preview.value = null;
    confirmed.value = false;
    const { data } = await Inboxes.previewWhatsappLink(
      props.inbox.id,
      payload.value
    );
    preview.value = data.preview;
  });
}
async function persist() {
  const { data } = await Inboxes.updateWhatsappLink(props.inbox.id, {
    ...payload.value,
    ...(preview.value?.confirmation
      ? { confirmation: preview.value.confirmation }
      : {}),
  });
  applyResponse(data);
  saved.value = true;
}
function save() {
  if (!valid.value) return undefined;
  return run(persist);
}
async function savePendingChanges() {
  if (!hasChanges.value) return;
  if (!canSave.value) {
    const exception = new Error('whatsapp_link_review_required');
    exception.code = 'whatsapp_link_review_required';
    throw exception;
  }
  await run(persist, true);
}
defineExpose({ savePendingChanges });
function remove() {
  return run(async () => {
    await Inboxes.deleteWhatsappLink(props.inbox.id);
    const { data } = await Inboxes.getWhatsappLink(props.inbox.id);
    applyResponse(data);
  });
}
</script>

<template>
  <section
    class="w-full min-w-0 py-4"
    :aria-label="$t('WHATSAPP_UNIFIED.TITLE')"
    :aria-busy="busy"
  >
    <h3 class="text-heading-3 text-n-slate-12">
      {{ $t('WHATSAPP_UNIFIED.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">{{ $t('WHATSAPP_UNIFIED.HELP') }}</p>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11 break-words">
      {{ error }}
    </p>
    <p v-if="saved && !hasChanges" role="status" class="text-sm text-n-teal-11">
      {{ $t('WHATSAPP_UNIFIED.SAVED') }}
    </p>
    <fieldset v-if="loaded" :disabled="busy" class="min-w-0 w-full">
      <label class="flex items-center gap-2 py-3 text-sm">
        <input v-model="enabled" type="checkbox" />
        {{ $t('WHATSAPP_UNIFIED.ENABLED') }}
      </label>
      <SettingsFieldSection :label="$t('WHATSAPP_UNIFIED.PARTNER')">
        <select
          v-model="partnerInboxId"
          :disabled="locked || noCandidates"
          class="w-full min-w-0 !m-0"
          :aria-label="$t('WHATSAPP_UNIFIED.PARTNER')"
          :aria-describedby="noCandidates ? noCandidatesId : undefined"
        >
          <option disabled value="">
            {{
              noCandidates
                ? $t('WHATSAPP_UNIFIED.NO_CANDIDATES')
                : $t('WHATSAPP_UNIFIED.CHOOSE')
            }}
          </option>
          <option
            v-for="candidate in candidates"
            :key="candidate.id"
            :value="candidate.id"
          >
            {{
              $t('WHATSAPP_UNIFIED.CANDIDATE', {
                name: candidate.name,
                provider: candidate.provider,
              })
            }}
          </option>
        </select>
        <p
          v-if="noCandidates"
          :id="noCandidatesId"
          role="status"
          class="mt-2 text-sm text-n-amber-11 break-words"
        >
          {{ $t('WHATSAPP_UNIFIED.NO_CANDIDATES_HELP') }}
        </p>
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="$t('WHATSAPP_UNIFIED.PRIMARY')"
        :help-text="$t('WHATSAPP_UNIFIED.PRIMARY_HELP')"
      >
        <select
          v-model="primaryInboxId"
          :disabled="locked || !partnerInboxId"
          class="w-full min-w-0 !m-0"
          :aria-label="$t('WHATSAPP_UNIFIED.PRIMARY')"
        >
          <option disabled value="">{{ $t('WHATSAPP_UNIFIED.CHOOSE') }}</option>
          <option
            v-for="choice in inboxChoices"
            :key="choice.id"
            :value="choice.id"
          >
            {{ choice.name }}
          </option>
        </select>
      </SettingsFieldSection>
      <SettingsFieldSection :label="$t('WHATSAPP_UNIFIED.DEFAULT')">
        <select
          v-model="defaultProvider"
          class="w-full min-w-0 !m-0"
          :aria-label="$t('WHATSAPP_UNIFIED.DEFAULT')"
        >
          <option disabled value="">{{ $t('WHATSAPP_UNIFIED.CHOOSE') }}</option>
          <option value="unoapi">
            {{ $t('WHATSAPP_UNIFIED.VIPERCONNECT') }}
          </option>
          <option value="whatsapp_cloud">
            {{ $t('WHATSAPP_UNIFIED.META') }}
          </option>
        </select>
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="$t('WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.TITLE')"
      >
        <div class="flex min-w-0 flex-col gap-2">
          <label class="flex min-w-0 items-start gap-2 py-2 text-sm">
            <input
              v-model="metaInitialMessagesEnabled"
              type="checkbox"
              class="mt-1 shrink-0"
              :aria-describedby="`${metaInitialMessagesId}-help`"
            />
            <span class="min-w-0 break-words">
              {{ $t('WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.ENABLED') }}
            </span>
          </label>
          <p
            :id="`${metaInitialMessagesId}-help`"
            class="text-sm text-n-slate-11 break-words"
          >
            {{ $t('WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.HELP') }}
          </p>
          <label :for="metaInitialMessagesId" class="text-sm">
            {{ $t('WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.LIMIT') }}
          </label>
          <input
            :id="metaInitialMessagesId"
            v-model.number="metaInitialMessagesLimit"
            type="number"
            min="0"
            max="1000"
            step="1"
            class="w-full min-w-0 !m-0"
            :aria-invalid="!validMetaInitialMessagesLimit"
            :aria-describedby="`${metaInitialMessagesId}-limit-help`"
          />
          <p
            :id="`${metaInitialMessagesId}-limit-help`"
            class="text-sm break-words"
            :class="
              validMetaInitialMessagesLimit
                ? 'text-n-slate-11'
                : 'text-n-ruby-11'
            "
            :role="!validMetaInitialMessagesLimit ? 'alert' : undefined"
          >
            {{ $t('WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.LIMIT_HELP') }}
          </p>
        </div>
      </SettingsFieldSection>
      <p v-if="locked" class="text-sm text-n-slate-11">
        {{ $t('WHATSAPP_UNIFIED.LOCKED') }}
      </p>
      <p v-if="link?.activated_at" class="text-sm text-n-slate-11 break-words">
        {{ $t('WHATSAPP_UNIFIED.CUTOFF_VALUE', { date: link.activated_at }) }}
      </p>
      <NextButton
        :label="$t('WHATSAPP_UNIFIED.PREVIEW')"
        :disabled="!valid || busy"
        variant="outline"
        @click="inspect"
      />
      <div v-if="preview" class="mt-4 min-w-0 text-sm" role="status">
        <p v-if="hasConflicts">{{ $t('WHATSAPP_UNIFIED.CONFLICTS') }}</p>
        <p v-else>{{ $t('WHATSAPP_UNIFIED.NO_CONFLICTS') }}</p>
        <p v-if="preview.active_conversations_count !== undefined">
          {{
            $t('WHATSAPP_UNIFIED.ACTIVE_COUNT', {
              count: preview.active_conversations_count,
            })
          }}
        </p>
        <pre
          v-if="hasConflicts"
          class="whitespace-pre-wrap break-words max-h-64 overflow-auto"
          >{{ JSON.stringify(preview.conflicts, null, 2) }}</pre
        >
        <pre
          v-if="preview.diagnostics"
          class="whitespace-pre-wrap break-words max-h-64 overflow-auto"
          >{{ JSON.stringify(preview.diagnostics, null, 2) }}</pre
        >
        <p v-if="preview.cutoff" class="break-words">
          {{ $t('WHATSAPP_UNIFIED.CUTOFF_VALUE', { date: preview.cutoff }) }}
        </p>
      </div>
      <label class="flex items-start gap-2 py-4 text-sm">
        <input v-model="confirmed" type="checkbox" class="mt-1 shrink-0" />
        <span>{{ $t('WHATSAPP_UNIFIED.CONFIRM') }}</span>
      </label>
      <div class="flex flex-col sm:flex-row flex-wrap gap-2">
        <NextButton
          :label="$t('WHATSAPP_UNIFIED.SAVE')"
          :disabled="!canSave"
          @click="save"
        />
        <NextButton
          v-if="link"
          :label="$t('WHATSAPP_UNIFIED.REMOVE')"
          :disabled="!confirmed || busy"
          color="ruby"
          variant="outline"
          @click="remove"
        />
      </div>
    </fieldset>
    <WhatsappUnifiedReviews
      v-if="loaded && link?.id"
      :key="`${inbox.id}-${link.id}`"
      :inbox-id="inbox.id"
      :link-enabled="link.enabled"
    />
  </section>
</template>

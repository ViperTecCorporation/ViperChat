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
const preview = ref(null);
const confirmed = ref(false);
const busy = ref(false);
const loaded = ref(false);
const error = ref('');
const payload = computed(() => ({
  partner_inbox_id: Number(partnerInboxId.value),
  primary_inbox_id: Number(primaryInboxId.value),
  default_provider: defaultProvider.value,
  enabled: enabled.value,
}));
const inboxChoices = computed(() => [
  props.inbox,
  ...candidates.value.filter(
    inbox => inbox.id === Number(partnerInboxId.value)
  ),
]);
const valid = computed(
  () => partnerInboxId.value && primaryInboxId.value && defaultProvider.value
);
const hasConflicts = computed(() => Boolean(preview.value?.conflicts?.length));
const locked = computed(() => Boolean(link.value?.activated_at));
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
  preview.value = null;
  confirmed.value = false;
}

async function run(action) {
  busy.value = true;
  error.value = '';
  try {
    await action();
  } catch (exception) {
    error.value = exception.response?.data?.error || exception.message;
    if (exception.response?.data?.preview) {
      preview.value = exception.response.data.preview;
      confirmed.value = false;
    }
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
function save() {
  return run(async () => {
    const { data } = await Inboxes.updateWhatsappLink(props.inbox.id, {
      ...payload.value,
      ...(preview.value?.confirmation
        ? { confirmation: preview.value.confirmation }
        : {}),
    });
    applyResponse(data);
  });
}
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
          :disabled="
            !valid ||
            !preview ||
            (enabled && hasConflicts) ||
            !confirmed ||
            busy
          "
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

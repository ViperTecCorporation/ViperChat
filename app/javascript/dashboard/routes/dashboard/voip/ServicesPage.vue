<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { VoipAPI } from 'dashboard/api/voip';
import AgentVoipCard from 'dashboard/components/voip/AgentVoipCard.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import ServiceIntegrationFields from './ServiceIntegrationFields.vue';
import ServiceDiagnostics from './ServiceDiagnostics.vue';

const { t } = useI18n();
const { accountId } = useAccount();
const api = computed(() => new VoipAPI(accountId.value));
const rows = ref([]);
const agents = ref([]);
const memberId = ref('');
const dialog = ref(null);
const editing = ref(null);
const form = ref({});
const allowedUsers = ref([]);
const diagnosticsService = ref(null);
const diagnosticsDialog = ref(null);
async function openDiagnostics(row) {
  diagnosticsService.value = row;
  await nextTick();
  diagnosticsDialog.value.showModal();
}
const configuredExtensions = computed(() =>
  rows.value.flatMap(row =>
    (row.bindings || []).map(binding => ({
      ...binding,
      serviceName: row.name,
    }))
  )
);
const selectedAgentNames = computed(() =>
  allowedUsers.value.map(
    id =>
      agents.value.find(agent => agent.user_id === id)?.name ||
      t('AGENT_VOIP.UNAVAILABLE_AGENT', { id })
  )
);
const agentMenuItems = computed(() =>
  agents.value
    .filter(agent => !allowedUsers.value.includes(agent.user_id))
    .map(agent => ({
      label: agent.name,
      value: agent.user_id,
      action: 'select',
      thumbnail: { name: agent.name, src: agent.thumbnail || '' },
    }))
);
function addAllowedAgent({ value }) {
  if (!allowedUsers.value.includes(value)) allowedUsers.value.push(value);
}
function removeAllowedAgent(index) {
  allowedUsers.value.splice(index, 1);
}
const error = ref('');
const busy = ref(false);
let contextVersion = 0;
const textFields = [
  ['name', 'NAME'],
  ['wss_url', 'WSS'],
  ['sip_domain', 'DOMAIN'],
  ['stun_url', 'STUN'],
  ['turn_url', 'TURN'],
  ['turn_username', 'TURN_USER'],
];
async function load() {
  const version = contextVersion;
  const result = await api.value.services();
  if (version === contextVersion) rows.value = result.data;
}
function clearSecrets() {
  form.value.turn_password = '';
  form.value.history_api_token = '';
}
function open(row) {
  editing.value = row?.id || null;
  form.value = row
    ? {
        ...row,
        turn_password: '',
        history_api_token: '',
        history_company_id: row.history_company_id || '',
        integration_provider: row.integration_provider || 'none',
        clear_history_api_token: false,
      }
    : {
        name: '',
        wss_url: '',
        sip_domain: '',
        enabled: true,
        allow_self_configuration: true,
        transfer_enabled: false,
        registration_expires: 300,
        turn_password: '',
        integration_provider: 'none',
        webhook_source_instance_id: '',
        history_api_token: '',
        history_company_id: '',
        clear_history_api_token: false,
      };
  allowedUsers.value = [...(row?.allowed_user_ids || [])];
  error.value = '';
  dialog.value.showModal();
}
async function save() {
  const version = contextVersion;
  busy.value = true;
  error.value = '';
  try {
    const fields = [
      ...textFields.map(([field]) => field),
      'turn_password',
      'registration_expires',
      'enabled',
      'allow_self_configuration',
      'transfer_enabled',
      'integration_provider',
      'webhook_source_instance_id',
    ];
    if (form.value.integration_provider === 'viperconnect') {
      fields.push(
        'history_api_url',
        'history_api_token',
        'history_company_id',
        'clear_history_api_token'
      );
    }
    await api.value.saveService(editing.value, {
      ...Object.fromEntries(fields.map(field => [field, form.value[field]])),
      allowed_user_ids: [...allowedUsers.value],
    });
    if (version !== contextVersion) return;
    clearSecrets();
    dialog.value.close();
    await load();
  } catch (failure) {
    if (version === contextVersion) {
      const attributes = failure.response?.data?.attributes || [];
      if (attributes.includes('wss_url')) {
        error.value = t('AGENT_VOIP.WSS_REQUIRED');
      } else {
        const fields = [
          ...textFields,
          ...[
            ['webhook_source_instance_id', 'WEBHOOK_SOURCE'],
            ['history_api_url', 'HISTORY_URL'],
            ['history_api_token', 'HISTORY_TOKEN'],
            ['history_company_id', 'HISTORY_COMPANY'],
          ],
        ]
          .filter(([field]) => attributes.includes(field))
          .map(([, label]) => t(`AGENT_VOIP.${label}`));
        error.value = fields.length
          ? t('AGENT_VOIP.INVALID_FIELDS', { fields: fields.join(', ') })
          : t('AGENT_VOIP.ERROR');
      }
    }
  } finally {
    if (version === contextVersion) busy.value = false;
  }
}
async function disable(row) {
  const version = contextVersion;
  try {
    await api.value.disableService(row.id);
    if (version === contextVersion) await load();
  } catch {
    if (version === contextVersion) error.value = t('AGENT_VOIP.ERROR');
  }
}
watch(
  accountId,
  async () => {
    contextVersion += 1;
    const version = contextVersion;
    dialog.value?.close();
    diagnosticsDialog.value?.close();
    diagnosticsService.value = null;
    rows.value = [];
    agents.value = [];
    memberId.value = '';
    editing.value = null;
    form.value = {};
    allowedUsers.value = [];
    error.value = '';
    busy.value = false;
    const currentApi = api.value;
    try {
      const [services, members] = await Promise.all([
        currentApi.services(),
        currentApi.agents(),
      ]);
      if (version !== contextVersion) return;
      rows.value = services.data;
      agents.value = members.data;
    } catch {
      if (version === contextVersion) error.value = t('AGENT_VOIP.ERROR');
    }
  },
  { immediate: true, flush: 'sync' }
);
</script>

<template>
  <section
    class="h-full min-w-0 flex-1 overflow-y-auto bg-n-surface-1 p-4 text-n-slate-12 md:p-8"
  >
    <header
      class="mb-6 flex flex-wrap items-center justify-between gap-3 pl-8 md:pl-0"
    >
      <div>
        <h1 class="text-xl font-semibold">
          {{ t('AGENT_VOIP.SERVICES') }}
        </h1>
        <p class="mt-2 max-w-2xl text-sm text-n-slate-11">
          {{ t('AGENT_VOIP.SERVICE_HELP') }}
        </p>
      </div>
      <button
        type="button"
        class="min-h-11 rounded-lg bg-n-brand px-4 text-white"
        @click="open()"
      >
        {{ t('AGENT_VOIP.ADD_SERVICE') }}
      </button>
    </header>
    <p v-if="error" role="alert" class="my-3 text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <p v-if="!rows.length" class="my-4 text-n-slate-11">
      {{ t('AGENT_VOIP.NO_SERVICES') }}
    </p>
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
      <article
        v-for="row in rows"
        :key="row.id"
        class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak p-4"
      >
        <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
          <h2 class="break-words font-semibold">
            {{ row.name }}
          </h2>
          <span class="text-sm text-n-slate-11">
            {{
              row.enabled
                ? t('AGENT_VOIP.ACTIVE')
                : t('AGENT_VOIP.REGISTRATION.disconnected')
            }}
          </span>
        </div>
        <p class="break-all text-sm text-n-slate-11">
          {{ row.wss_url }}
        </p>
        <p class="break-all text-sm">
          {{ row.sip_domain }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            class="min-h-11 rounded-lg border border-n-weak px-4"
            @click="open(row)"
          >
            {{ t('AGENT_VOIP.EDIT') }}
          </button>
          <button
            v-if="row.enabled"
            type="button"
            class="min-h-11 rounded-lg border border-n-weak px-4"
            @click="disable(row)"
          >
            {{ t('AGENT_VOIP.DISABLE') }}
          </button>
          <button
            v-if="
              row.integration_provider && row.integration_provider !== 'none'
            "
            type="button"
            class="inline-flex min-h-11 items-center gap-2 rounded-lg border border-n-weak px-4"
            @click="openDiagnostics(row)"
          >
            <span
              aria-hidden="true"
              class="i-lucide-activity size-4 shrink-0"
            />
            {{ t('AGENT_VOIP.DIAGNOSTICS.TITLE') }}
          </button>
        </div>
      </article>
    </div>
    <section class="mt-8 flex min-w-0 flex-col gap-3">
      <h2 class="text-lg font-semibold">
        {{ t('AGENT_VOIP.CONFIGURED_EXTENSIONS') }}
      </h2>
      <p v-if="!configuredExtensions.length" class="text-sm text-n-slate-11">
        {{ t('AGENT_VOIP.NO_EXTENSIONS') }}
      </p>
      <ul class="m-0 grid list-none grid-cols-1 gap-3 p-0 lg:grid-cols-2">
        <li
          v-for="binding in configuredExtensions"
          :key="binding.id"
          class="flex min-w-0 items-center gap-3 rounded-xl border border-n-weak p-3"
        >
          <span
            class="i-lucide-phone shrink-0 text-xl text-n-slate-11"
            aria-hidden="true"
          />
          <div class="min-w-0 flex-1">
            <p class="m-0 break-words font-medium">{{ binding.agent_name }}</p>
            <p class="m-0 break-words text-sm text-n-slate-11">
              {{ binding.serviceName }} · {{ binding.extension }}
            </p>
            <span v-if="binding.active" class="text-xs text-n-teal-11">
              {{ t('AGENT_VOIP.DEFAULT_EXTENSION') }}
            </span>
          </div>
        </li>
      </ul>
    </section>
    <section class="mt-8 flex flex-col gap-4">
      <label class="flex max-w-lg flex-col gap-2 text-sm">
        {{ t('AGENT_VOIP.PROFILE') }}
        <select
          v-model="memberId"
          class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
        >
          <option value="">—</option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">
            {{ agent.name }}
          </option>
        </select>
      </label>
      <AgentVoipCard
        v-if="memberId"
        :key="memberId"
        :account-user-id="Number(memberId)"
      />
    </section>
    <dialog
      ref="diagnosticsDialog"
      class="m-auto max-h-[calc(100dvh_-_2rem_-_env(safe-area-inset-top)_-_env(safe-area-inset-bottom))] w-[calc(100%_-_2rem)] max-w-2xl overflow-hidden rounded-2xl border border-n-weak bg-n-surface-1 p-0 text-n-slate-12 backdrop:bg-black/50 [&[open]]:flex [&[open]]:flex-col"
      @close="diagnosticsService = null"
    >
      <header
        class="flex shrink-0 items-center justify-between gap-2 border-b border-n-weak p-4"
      >
        <h2 class="min-w-0 break-words font-semibold">
          {{ t('AGENT_VOIP.DIAGNOSTICS.TITLE') }} ·
          {{ diagnosticsService?.name }}
        </h2>
        <button
          type="button"
          :aria-label="t('AGENT_VOIP.CLOSE')"
          class="flex size-11 shrink-0 items-center justify-center rounded-full hover:bg-n-alpha-1"
          @click="diagnosticsDialog.close()"
        >
          <span aria-hidden="true" class="i-lucide-x size-5" />
        </button>
      </header>
      <div class="min-h-0 overflow-y-auto p-4">
        <ServiceDiagnostics
          v-if="diagnosticsService"
          :key="`${accountId}:${diagnosticsService.id}`"
          :account-id="accountId"
          :service-id="diagnosticsService.id"
        />
      </div>
    </dialog>
    <dialog
      ref="dialog"
      class="m-auto w-[calc(100%-2rem)] max-w-2xl rounded-2xl border border-n-weak bg-n-surface-1 p-0 text-n-slate-12 backdrop:bg-black/50"
      @close="clearSecrets"
    >
      <form
        class="flex max-h-[85dvh] flex-col gap-4 overflow-y-auto p-5"
        @submit.prevent="save"
      >
        <h2 class="text-lg font-semibold">
          {{ t('AGENT_VOIP.SERVICES') }}
        </h2>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label
            v-for="[field, label] in textFields"
            :key="field"
            class="flex min-w-0 flex-col gap-1 text-sm"
          >
            {{ t(`AGENT_VOIP.${label}`) }}
            <input
              v-model="form[field]"
              :required="['name', 'wss_url', 'sip_domain'].includes(field)"
              class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
            />
          </label>
          <label class="flex min-w-0 flex-col gap-1 text-sm">
            {{ t('AGENT_VOIP.TURN_PASSWORD') }}
            <input
              v-model="form.turn_password"
              type="password"
              autocomplete="new-password"
              class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
              :placeholder="editing ? t('AGENT_VOIP.SECRET_SAVED') : ''"
            />
          </label>
          <label class="flex min-w-0 flex-col gap-1 text-sm">
            {{ t('AGENT_VOIP.EXPIRES') }}
            <input
              v-model.number="form.registration_expires"
              type="number"
              min="60"
              max="3600"
              required
              class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
            />
          </label>
        </div>
        <ServiceIntegrationFields v-model="form" />
        <div class="flex min-w-0 flex-col gap-2 text-sm">
          <label>{{ t('AGENT_VOIP.ALLOWED_USERS') }}</label>
          <div class="min-w-0 rounded-xl border border-n-weak p-2">
            <TagInput
              :model-value="selectedAgentNames"
              :placeholder="t('AGENT_VOIP.PICK_AGENTS')"
              :menu-items="agentMenuItems"
              :auto-open-dropdown="false"
              :disabled="busy"
              show-dropdown
              skip-label-dedup
              @add="addAllowedAgent"
              @remove="removeAllowedAgent"
            />
          </div>
          <p class="text-xs text-n-slate-11">
            {{ t('AGENT_VOIP.ALLOWED_USERS_HELP') }}
          </p>
        </div>
        <label
          v-for="[field, label] in [
            ['enabled', 'ENABLED'],
            ['allow_self_configuration', 'SELF_CONFIG'],
            ['transfer_enabled', 'REFER'],
          ]"
          :key="field"
          class="flex items-center gap-2 text-sm"
        >
          <input v-model="form[field]" type="checkbox" />
          {{ t(`AGENT_VOIP.${label}`) }}
        </label>
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <footer class="flex flex-wrap gap-2">
          <button
            type="submit"
            :disabled="busy"
            class="min-h-11 rounded-lg bg-n-brand px-4 text-white disabled:opacity-50"
          >
            {{ t('AGENT_VOIP.SAVE') }}
          </button>
          <button
            type="button"
            class="min-h-11 rounded-lg border border-n-weak px-4"
            @click="dialog.close()"
          >
            {{ t('AGENT_VOIP.CANCEL') }}
          </button>
        </footer>
      </form>
    </dialog>
  </section>
</template>

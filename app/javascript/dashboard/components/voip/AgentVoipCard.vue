<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';
import { VoipAPI } from 'dashboard/api/voip';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';

const props = defineProps({
  accountUserId: { type: Number, default: null },
  compact: { type: Boolean, default: false },
});
const { t } = useI18n();
const { accountId } = useAccount();
const phone = useAgentVoipStore();
const store = useStore();
const dialog = ref(null);
const profile = ref({ services: [], bindings: [] });
const serviceId = ref('');
const form = ref({
  extension: '',
  auth_username: '',
  password: '',
  clear_password: false,
});
const busy = ref(false);
const error = ref('');
const success = ref(false);
let contextVersion = 0;
const api = computed(() => new VoipAPI(accountId.value));
const binding = computed(() =>
  profile.value.bindings.find(
    row => row.voip_service_id === Number(serviceId.value)
  )
);
const service = computed(() =>
  profile.value.services.find(row => row.id === Number(serviceId.value))
);
const canConfigure = computed(
  () =>
    props.accountUserId ||
    store.getters.getCurrentRole === 'administrator' ||
    service.value?.allow_self_configuration
);

async function load() {
  const version = contextVersion;
  const result = await api.value.profile(props.accountUserId);
  if (version !== contextVersion) return false;
  profile.value = result.data;
  return true;
}
function resetForm() {
  error.value = '';
  success.value = false;
  form.value = {
    extension: binding.value?.extension || '',
    auth_username: binding.value?.auth_username || '',
    password: '',
    clear_password: false,
  };
}
watch(serviceId, resetForm);
async function open() {
  const version = contextVersion;
  try {
    if (!(await load())) return;
    if (!service.value)
      serviceId.value =
        profile.value.bindings.find(row => row.active)?.voip_service_id || '';
    resetForm();
    dialog.value.showModal();
  } catch {
    if (version === contextVersion) error.value = t('AGENT_VOIP.ERROR');
  }
}
async function perform(action) {
  const version = contextVersion;
  error.value = '';
  busy.value = true;
  try {
    await action(() => version === contextVersion);
  } catch {
    if (version === contextVersion) error.value = t('AGENT_VOIP.ERROR');
  } finally {
    if (version === contextVersion) busy.value = false;
  }
}
async function save() {
  if (!service.value || !canConfigure.value || busy.value || phone.call) return;
  await perform(async isCurrent => {
    await api.value.saveBinding(
      Number(serviceId.value),
      {
        ...form.value,
        auth_username: form.value.auth_username || form.value.extension,
      },
      props.accountUserId
    );
    if (!isCurrent()) return;
    form.value.password = '';
    form.value.clear_password = false;
    if (!(await load())) return;
    if (!props.accountUserId) await phone.refreshConfiguration();
  });
}
async function activate() {
  await perform(async isCurrent => {
    if (props.accountUserId)
      await api.value.activate(binding.value.id, props.accountUserId);
    else await phone.activate(binding.value.id);
    if (isCurrent()) await load();
  });
}
async function test() {
  success.value = false;
  await perform(async isCurrent => {
    await phone.testBinding(binding.value.id);
    if (isCurrent()) success.value = true;
  });
}
async function deactivate() {
  await perform(async isCurrent => {
    if (props.accountUserId)
      await api.value.activate(null, props.accountUserId);
    else await phone.activate(null);
    if (isCurrent()) await load();
  });
}
watch(
  [accountId, () => props.accountUserId],
  () => {
    contextVersion += 1;
    dialog.value?.close();
    profile.value = { services: [], bindings: [] };
    serviceId.value = '';
    busy.value = false;
    resetForm();
    load().catch(() => {});
  },
  { immediate: true, flush: 'sync' }
);
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-3"
    :class="compact ? '' : 'rounded-xl border border-n-weak p-4'"
  >
    <h3 v-if="!compact" class="text-base font-semibold">
      {{ t('AGENT_VOIP.PROFILE') }}
    </h3>
    <p v-if="!compact" class="text-sm text-n-slate-11">
      {{ t('AGENT_VOIP.ONE_SERVICE') }}
    </p>
    <p v-if="!accountUserId && !compact" class="text-sm">
      {{ phone.activeBinding?.service_name }}
      {{ phone.activeBinding?.extension }}
    </p>
    <button
      class="min-h-11 self-start rounded-lg bg-n-brand px-4 py-2 text-white"
      type="button"
      @click="open"
    >
      {{ t('AGENT_VOIP.SETTINGS') }}
    </button>
    <p
      v-if="error && !dialog?.open"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <dialog
      ref="dialog"
      class="m-auto w-[calc(100%-2rem)] max-w-lg rounded-2xl border border-n-weak bg-n-surface-1 p-0 text-n-slate-12 backdrop:bg-black/50"
      @close="form.password = ''"
    >
      <form
        class="flex max-h-[85dvh] flex-col gap-4 overflow-y-auto p-5"
        @submit.prevent="save"
      >
        <h2 class="text-lg font-semibold">
          {{ t('AGENT_VOIP.SETTINGS') }}
        </h2>
        <p v-if="!profile.services.length" class="text-sm text-n-slate-11">
          {{ t('AGENT_VOIP.NO_SERVICES') }}
        </p>
        <label class="flex min-w-0 flex-col gap-1 text-sm">
          {{ t('AGENT_VOIP.SERVICE') }}
          <select
            v-model="serviceId"
            class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
            :disabled="busy || !!phone.call"
          >
            <option value="">—</option>
            <option
              v-for="row in profile.services"
              :key="row.id"
              :value="row.id"
            >
              {{ row.name }}
            </option>
          </select>
        </label>
        <template v-if="serviceId">
          <label class="flex flex-col gap-1 text-sm">
            {{ t('AGENT_VOIP.EXTENSION') }}
            <input
              v-model="form.extension"
              required
              maxlength="64"
              autocomplete="off"
              class="rounded-lg border border-n-weak bg-n-surface-2 p-2"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            {{ t('AGENT_VOIP.USERNAME') }}
            <input
              v-model="form.auth_username"
              maxlength="64"
              autocomplete="off"
              class="rounded-lg border border-n-weak bg-n-surface-2 p-2"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            {{ t('AGENT_VOIP.PASSWORD') }}
            <input
              v-model="form.password"
              type="password"
              autocomplete="new-password"
              class="rounded-lg border border-n-weak bg-n-surface-2 p-2"
              :placeholder="
                binding?.credential_configured
                  ? t('AGENT_VOIP.SECRET_SAVED')
                  : ''
              "
            />
          </label>
          <label class="flex items-center gap-2 text-sm">
            <input v-model="form.clear_password" type="checkbox" />
            {{ t('AGENT_VOIP.CLEAR_SECRET') }}
          </label>
        </template>
        <p v-if="phone.call" class="text-sm text-n-amber-11">
          {{ t('AGENT_VOIP.BUSY_HELP') }}
        </p>
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <p v-if="success" role="status" class="text-sm text-n-teal-11">
          {{ t('AGENT_VOIP.TEST_OK') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            type="submit"
            :disabled="busy || !serviceId || !!phone.call || !canConfigure"
            class="rounded-lg bg-n-brand px-4 py-2 text-white disabled:opacity-50"
          >
            {{ t('AGENT_VOIP.SAVE') }}
          </button>
          <button
            v-if="binding?.credential_configured && !accountUserId"
            type="button"
            :disabled="busy || !!phone.call"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
            @click="test"
          >
            {{ t('AGENT_VOIP.TEST') }}
          </button>
          <button
            v-if="binding?.credential_configured"
            type="button"
            :disabled="busy || !!phone.call"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
            @click="activate"
          >
            {{ t('AGENT_VOIP.ACTIVATE') }}
          </button>
          <button
            v-if="binding?.active"
            type="button"
            :disabled="busy || !!phone.call"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
            @click="deactivate"
          >
            {{ t('AGENT_VOIP.DEACTIVATE') }}
          </button>
          <button
            type="button"
            class="rounded-lg border border-n-weak px-3 py-2"
            @click="dialog.close()"
          >
            {{ t('AGENT_VOIP.CLOSE') }}
          </button>
        </div>
      </form>
    </dialog>
  </section>
</template>

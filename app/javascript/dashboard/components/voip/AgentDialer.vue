<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';
import { VoipAPI } from 'dashboard/api/voip';

const { t } = useI18n();
const { accountId } = useAccount();
const phone = useAgentVoipStore();
const dialog = ref(null);
const kind = ref('manual');
const address = ref('');
const serviceId = ref('');
const search = ref('');
const page = ref(1);
const items = ref([]);
const total = ref(0);
const loading = ref(false);
const busy = ref(false);
const error = ref('');
let requestVersion = 0;
let contextVersion = 0;
let dialingVersion = null;
const tabs = [
  { id: 'contacts', label: 'CONTACTS', icon: 'i-lucide-contact-round' },
  { id: 'extensions', label: 'EXTENSIONS', icon: 'i-lucide-users-round' },
  { id: 'manual', label: 'MANUAL_DIAL', icon: 'i-lucide-grid-3x3' },
];
const services = computed(() =>
  phone.services.filter(service =>
    phone.bindings.some(
      binding =>
        binding.voip_service_id === service.id && binding.credential_configured
    )
  )
);
const selectedBinding = computed(() =>
  phone.bindings.find(
    binding => binding.voip_service_id === Number(serviceId.value)
  )
);
const serviceMatches = computed(
  () => phone.activeService?.id === Number(serviceId.value)
);
const normalizedAddress = computed(() => {
  const value = address.value.trim();
  return /^[+\d\s().-]+$/.test(value) ? value.replace(/[\s().-]/g, '') : value;
});
const canDial = computed(
  () =>
    !busy.value &&
    !phone.call &&
    phone.connected &&
    serviceMatches.value &&
    /^[a-zA-Z0-9+*#._-]{1,128}$/.test(normalizedAddress.value)
);

async function loadDirectory() {
  requestVersion += 1;
  const version = requestVersion;
  items.value = [];
  total.value = 0;
  if (!phone.dialer.open || kind.value === 'manual' || !serviceId.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  error.value = '';
  try {
    const { data } = await new VoipAPI(accountId.value).directory({
      service_id: Number(serviceId.value),
      kind: kind.value,
      search: search.value,
      page: page.value,
    });
    if (version !== requestVersion) return;
    items.value = data.items;
    total.value = data.total;
  } catch {
    if (version === requestVersion) error.value = t('AGENT_VOIP.ERROR');
  } finally {
    if (version === requestVersion) loading.value = false;
  }
}
function close() {
  phone.closeDialer();
}
function select(entry) {
  address.value = entry.address;
}
async function perform(action) {
  const version = contextVersion;
  busy.value = true;
  error.value = '';
  try {
    await action();
  } catch {
    if (version === contextVersion) error.value = t('AGENT_VOIP.ERROR');
  } finally {
    if (version === contextVersion) busy.value = false;
  }
}
async function activate() {
  if (!selectedBinding.value || phone.call || busy.value) return;
  await perform(() => phone.activate(selectedBinding.value.id));
}
async function dial() {
  if (!canDial.value) return;
  const version = contextVersion;
  dialingVersion = version;
  try {
    await perform(async () => {
      await phone.dial(normalizedAddress.value);
      if (version === contextVersion) close();
    });
  } finally {
    if (dialingVersion === version) dialingVersion = null;
  }
}
watch(
  () => phone.call?.client_call_id,
  id => {
    if (id && phone.dialer.open && dialingVersion === contextVersion) close();
  }
);
watch([kind, search, serviceId], () => {
  page.value = 1;
  loadDirectory();
});
watch(page, loadDirectory);
watch(
  () => phone.activeService?.id,
  id => {
    if (phone.dialer.open && !serviceId.value && id) serviceId.value = id;
  }
);
watch(accountId, close, { flush: 'sync' });
watch(
  () => phone.dialer.open,
  async open => {
    contextVersion += 1;
    dialingVersion = null;
    requestVersion += 1;
    busy.value = false;
    error.value = '';
    items.value = [];
    total.value = 0;
    if (!open) {
      dialog.value?.close();
      address.value = '';
      search.value = '';
      return;
    }
    kind.value = ['contacts', 'extensions', 'manual'].includes(
      phone.dialer.kind
    )
      ? phone.dialer.kind
      : 'manual';
    address.value = phone.dialer.address;
    serviceId.value = phone.dialer.serviceId || '';
    search.value = '';
    page.value = 1;
    await nextTick();
    if (!phone.dialer.open) return;
    dialog.value?.showModal();
    loadDirectory();
  },
  { flush: 'post', immediate: true }
);
</script>

<template>
  <Teleport to="body">
    <dialog
      ref="dialog"
      class="m-auto max-h-[calc(100dvh_-_2rem_-_env(safe-area-inset-top)_-_env(safe-area-inset-bottom))] w-[calc(100%_-_2rem)] max-w-lg overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-n-slate-12 shadow-xl backdrop:bg-black/50 sm:p-6"
      :aria-label="t('AGENT_VOIP.NEW_CALL')"
      @cancel.prevent="close"
      @close="close"
    >
      <header class="mb-4 flex items-center justify-between gap-3">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <span class="i-lucide-phone-call size-5" aria-hidden="true" />
          {{ t('AGENT_VOIP.NEW_CALL') }}
        </h2>
        <button
          type="button"
          class="flex size-11 shrink-0 items-center justify-center rounded-full hover:bg-n-alpha-2"
          :aria-label="t('AGENT_VOIP.CLOSE')"
          @click="close"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </header>
      <label class="flex flex-col gap-1 text-sm">
        {{ t('AGENT_VOIP.SERVICE') }}
        <select
          v-model="serviceId"
          :disabled="busy || !!phone.call"
          class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
        >
          <option value="" disabled>{{ t('AGENT_VOIP.SERVICE') }}</option>
          <option
            v-for="service in services"
            :key="service.id"
            :value="service.id"
          >
            {{ service.name }}
          </option>
        </select>
      </label>
      <p v-if="!services.length" class="mt-2 text-sm text-n-slate-11">
        {{ t('AGENT_VOIP.NO_BINDING') }}
      </p>
      <button
        v-if="selectedBinding && !serviceMatches"
        type="button"
        :disabled="busy || !!phone.call"
        class="mt-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm disabled:opacity-50"
        @click="activate"
      >
        {{ t('AGENT_VOIP.ACTIVATE') }}
      </button>
      <div
        class="my-4 grid grid-cols-3 gap-1"
        role="tablist"
        :aria-label="t('AGENT_VOIP.DESTINATION')"
      >
        <button
          v-for="tab in tabs"
          :key="tab.id"
          type="button"
          role="tab"
          :aria-selected="kind === tab.id"
          class="flex min-w-0 flex-col items-center gap-1 rounded-lg px-1 py-2 text-xs sm:flex-row sm:justify-center"
          :class="
            kind === tab.id
              ? 'bg-n-brand/10 text-n-brand'
              : 'hover:bg-n-alpha-2'
          "
          @click="kind = tab.id"
        >
          <span :class="tab.icon" class="size-5" aria-hidden="true" />
          {{ t(`AGENT_VOIP.${tab.label}`) }}
        </button>
      </div>
      <section v-if="kind !== 'manual'" class="mb-4">
        <label class="relative block">
          <span
            class="i-lucide-search pointer-events-none absolute left-3 top-3 size-4 text-n-slate-10"
            aria-hidden="true"
          />
          <input
            v-model="search"
            type="search"
            :aria-label="t('AGENT_VOIP.SEARCH')"
            :placeholder="t('AGENT_VOIP.SEARCH')"
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-2 py-2 !pl-9 !pr-3 text-base"
          />
        </label>
        <p v-if="loading" role="status" class="py-3 text-sm">
          {{ t('AGENT_VOIP.LOADING') }}
        </p>
        <p v-else-if="!items.length" class="py-3 text-sm text-n-slate-11">
          {{ t('AGENT_VOIP.DIRECTORY_EMPTY') }}
        </p>
        <ul v-else class="mt-2 max-h-52 space-y-1 overflow-y-auto">
          <li v-for="entry in items" :key="`${entry.kind}:${entry.id}`">
            <button
              type="button"
              class="flex w-full min-w-0 items-center gap-3 rounded-lg p-2 text-left hover:bg-n-alpha-2"
              :aria-pressed="address === entry.address"
              @click="select(entry)"
            >
              <img
                v-if="entry.avatar_url"
                :src="entry.avatar_url"
                alt=""
                class="size-9 shrink-0 rounded-full object-cover"
              />
              <span
                v-else
                class="flex size-9 shrink-0 items-center justify-center rounded-full bg-n-alpha-2"
              >
                <span class="i-lucide-user-round size-5" aria-hidden="true" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium">{{
                  entry.name
                }}</span>
                <span class="block truncate text-xs text-n-slate-11">{{
                  entry.address
                }}</span>
              </span>
              <span
                v-if="address === entry.address"
                class="i-lucide-check size-5 shrink-0 text-n-brand"
                aria-hidden="true"
              />
            </button>
          </li>
        </ul>
        <nav
          v-if="total > 15"
          class="mt-2 flex justify-end gap-2"
          :aria-label="t('AGENT_VOIP.PAGES')"
        >
          <button
            type="button"
            :disabled="page <= 1 || loading"
            :aria-label="t('AGENT_VOIP.PREVIOUS')"
            class="flex size-11 items-center justify-center rounded-full disabled:opacity-40"
            @click="page -= 1"
          >
            <span class="i-lucide-chevron-left size-5" aria-hidden="true" />
          </button>
          <div class="self-center text-sm">
            {{ page }} / {{ Math.ceil(total / 15) }}
          </div>
          <button
            type="button"
            :disabled="page * 15 >= total || loading"
            :aria-label="t('AGENT_VOIP.NEXT')"
            class="flex size-11 items-center justify-center rounded-full disabled:opacity-40"
            @click="page += 1"
          >
            <span class="i-lucide-chevron-right size-5" aria-hidden="true" />
          </button>
        </nav>
      </section>
      <form class="space-y-3" @submit.prevent="dial">
        <label class="flex flex-col gap-1 text-sm">
          {{ t('AGENT_VOIP.DESTINATION') }}
          <input
            v-model="address"
            autocomplete="off"
            inputmode="tel"
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-base"
          />
        </label>
        <div
          v-if="kind === 'manual'"
          class="mx-auto grid max-w-60 grid-cols-3 gap-1"
        >
          <button
            v-for="digit in '123456789*0#'"
            :key="digit"
            type="button"
            class="flex min-h-11 items-center justify-center rounded-full text-lg hover:bg-n-alpha-2"
            @click="address += digit"
          >
            {{ digit }}
          </button>
        </div>
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <p v-if="phone.call" class="text-sm text-n-slate-11">
          {{ t('AGENT_VOIP.BUSY_HELP') }}
        </p>
        <button
          type="submit"
          :disabled="!canDial"
          class="flex min-h-11 w-full items-center justify-center gap-2 rounded-full bg-n-brand px-4 py-2 font-medium text-white hover:enabled:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:opacity-40"
        >
          <span class="i-lucide-phone size-5" aria-hidden="true" />{{
            t('AGENT_VOIP.CALL')
          }}
        </button>
      </form>
    </dialog>
  </Teleport>
</template>

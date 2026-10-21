<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useDebounceFn, useIntervalFn } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { VoipAPI } from 'dashboard/api/voip';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';
import AgentVoipCard from 'dashboard/components/voip/AgentVoipCard.vue';
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const { t } = useI18n();
const { accountId, accountScopedRoute } = useAccount();
const route = useRoute();
const router = useRouter();
const phone = useAgentVoipStore();
const store = useStore();
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const api = computed(() => new VoipAPI(accountId.value));
const items = ref([]);
const favorites = ref([]);
const detail = ref(null);
const search = ref('');
const state = ref('');
const direction = ref('');
const serviceId = ref('');
const agentId = ref('');
const agents = ref([]);
const dateFrom = ref('');
const dateUntil = ref('');
const filtersOpen = ref(false);
const filtersDialog = ref(null);
const favoriteRemovalDialog = ref(null);
const favoriteToRemove = ref(null);
const removingFavorite = ref(false);
const favoriteRemovalError = ref('');
const activeFilters = computed(
  () =>
    [
      state.value,
      direction.value,
      serviceId.value,
      agentId.value,
      dateFrom.value,
      dateUntil.value,
    ].filter(Boolean).length
);
const favoritePage = ref(1);
const favoritePages = computed(() =>
  Math.max(1, Math.ceil(favorites.value.length / 3))
);
const visibleFavorites = computed(() =>
  favorites.value.slice((favoritePage.value - 1) * 3, favoritePage.value * 3)
);
watch(favoritePages, count => {
  favoritePage.value = Math.min(favoritePage.value, count);
});
const page = ref(1);
const total = ref(0);
const pages = computed(() => Math.max(1, Math.ceil(total.value / 5)));
const error = ref('');
const loading = ref(false);
const favoriteName = ref('');
const list = ref(null);
let listScroll = 0;
let requestVersion = 0;
let detailRequestVersion = 0;

function date(value) {
  return value ? new Date(value).toLocaleString() : '—';
}
function callIcon(row) {
  if (row.state === 'missed') return 'i-lucide-phone-missed';
  if (['failed', 'rejected'].includes(row.state)) return 'i-lucide-phone-off';
  if (row.state === 'awaiting_confirmation') return 'i-lucide-clock';
  return row.direction === 'incoming'
    ? 'i-lucide-phone-incoming'
    : 'i-lucide-phone-outgoing';
}
function displayName(row) {
  return (
    row.remote_identity?.name ||
    row.remote_name ||
    row.name ||
    row.remote_address ||
    row.address ||
    ''
  );
}
function duration(value) {
  return value == null
    ? '—'
    : `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
}
async function load() {
  requestVersion += 1;
  const version = requestVersion;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await api.value.calls({
      page: page.value,
      search: search.value,
      state: state.value,
      direction: direction.value,
      service_id: serviceId.value,
      agent_id: agentId.value,
      from: dateFrom.value
        ? new Date(`${dateFrom.value}T00:00:00`).toISOString()
        : undefined,
      until: dateUntil.value
        ? new Date(`${dateUntil.value}T23:59:59`).toISOString()
        : undefined,
    });
    if (version !== requestVersion) return;
    items.value = data.items;
    total.value = data.total;
  } catch {
    error.value = t('AGENT_VOIP.ERROR');
  } finally {
    if (version === requestVersion) loading.value = false;
  }
}
const reload = useDebounceFn(() => {
  page.value = 1;
  load();
}, 250);
watch(
  [search, state, direction, serviceId, agentId, dateFrom, dateUntil],
  reload
);
watch(() => phone.historyVersion, reload);
async function loadDetail(id) {
  detailRequestVersion += 1;
  const version = detailRequestVersion;
  if (String(detail.value?.id) !== String(id)) detail.value = null;
  if (!id) {
    await nextTick();
    if (list.value) list.value.scrollTop = listScroll;
    return;
  }
  try {
    const { data } = await api.value.call(id);
    if (version === detailRequestVersion) detail.value = data;
  } catch {
    error.value = t('AGENT_VOIP.ERROR');
  }
}
function select(row) {
  listScroll = list.value?.scrollTop || 0;
  router.push(accountScopedRoute('agent_voip_calls', { callId: row.id }));
}
async function changePage(next) {
  if (loading.value || next < 1 || next > pages.value) return;
  page.value = next;
  await load();
}
async function loadFavorites() {
  const original = api.value;
  const { data } = await original.favorites();
  if (original.accountId === Number(accountId.value)) favorites.value = data;
}
async function loadAgents() {
  if (!isAdmin.value) return;
  const original = api.value;
  try {
    const { data } = await original.agents();
    if (original.accountId === Number(accountId.value)) agents.value = data;
  } catch {
    error.value = t('AGENT_VOIP.ERROR');
  }
}
watch(accountId, () => {
  requestVersion += 1;
  detailRequestVersion += 1;
  items.value = [];
  favorites.value = [];
  agents.value = [];
  detail.value = null;
  page.value = 1;
  total.value = 0;
  serviceId.value = '';
  agentId.value = '';
  listScroll = 0;
  filtersOpen.value = false;
  filtersDialog.value?.close();
  favoriteRemovalDialog.value?.close();
  favoriteToRemove.value = null;
  removingFavorite.value = false;
  favoriteRemovalError.value = '';
  favoritePage.value = 1;
  load();
  loadFavorites().catch(() => {});
  loadAgents();
});
watch([accountId, () => route.params.callId], ([, id]) => loadDetail(id), {
  immediate: true,
});
async function favorite() {
  try {
    await api.value.favorite(detail.value.service_id, {
      address: detail.value.remote_address,
      name:
        favoriteName.value ||
        displayName(detail.value) ||
        detail.value.remote_address,
    });
    await loadFavorites();
  } catch {
    error.value = t('AGENT_VOIP.ERROR');
  }
}
function requestRemoveFavorite(row) {
  favoriteToRemove.value = row;
  favoriteRemovalError.value = '';
  favoriteRemovalDialog.value.showModal();
}
async function removeFavorite() {
  if (!favoriteToRemove.value || removingFavorite.value) return;
  const original = api.value;
  removingFavorite.value = true;
  try {
    await original.removeFavorite(favoriteToRemove.value.id);
    if (original.accountId !== Number(accountId.value)) return;
    await loadFavorites();
    favoriteRemovalDialog.value?.close();
  } catch {
    if (original.accountId === Number(accountId.value))
      favoriteRemovalError.value = t('AGENT_VOIP.ERROR');
  } finally {
    if (original.accountId === Number(accountId.value))
      removingFavorite.value = false;
  }
}
function openDialer(address = '', requiredServiceId = null) {
  phone.openDialer({ address, serviceId: requiredServiceId });
}
onMounted(async () => {
  await load();
  loadFavorites().catch(() => {});
  loadAgents();
});
useIntervalFn(() => {
  if (detail.value) loadDetail(detail.value.id);
}, 20000);
</script>

<template>
  <div
    class="flex h-full min-h-0 w-full min-w-0 flex-col bg-n-surface-1 text-n-slate-12"
  >
    <header
      class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3 md:px-5 md:py-4"
    >
      <div class="min-w-0 flex-1">
        <h1 class="text-xl font-semibold">
          {{ t('AGENT_VOIP.TITLE') }}
        </h1>
        <p
          role="status"
          class="truncate text-xs text-n-slate-11 md:text-sm"
          :title="`${t(`AGENT_VOIP.REGISTRATION.${phone.registration}`)} · ${phone.activeBinding?.service_name || ''} ${phone.activeBinding?.extension || ''}`"
        >
          {{ t(`AGENT_VOIP.REGISTRATION.${phone.registration}`) }} ·
          {{ phone.activeBinding?.service_name }}
          {{ phone.activeBinding?.extension }}
        </p>
      </div>
    </header>
    <p v-if="error" role="alert" class="px-4 py-2 text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <div class="flex min-h-0 flex-1 overflow-hidden">
      <section
        ref="list"
        :aria-label="t('AGENT_VOIP.RECENT')"
        :class="route.params.callId ? 'hidden md:block' : 'block'"
        class="min-h-0 w-full shrink-0 overflow-y-auto border-r border-n-weak p-4 md:w-80 lg:w-96"
      >
        <h2
          v-if="favorites.length"
          class="mb-2 flex items-center gap-2 font-semibold"
        >
          <span
            aria-hidden="true"
            class="i-lucide-star size-4 text-n-slate-11"
          />
          {{ t('AGENT_VOIP.FAVORITES') }}
        </h2>
        <div class="grid grid-cols-3 gap-2">
          <div
            v-for="row in visibleFavorites"
            :key="row.id"
            class="relative flex min-w-0 flex-col items-center rounded-xl bg-n-alpha-1 px-1 py-2"
          >
            <button
              type="button"
              :title="displayName(row)"
              class="flex w-full min-w-0 flex-col items-center gap-1 rounded-lg text-center"
              @click="openDialer(row.address, row.voip_service_id)"
            >
              <Avatar
                :name="displayName(row)"
                :src="row.remote_identity?.avatar_url || ''"
                :size="40"
                rounded-full
              />
              <span class="block w-full truncate text-xs font-medium">{{
                displayName(row)
              }}</span>
            </button>
            <button
              type="button"
              :aria-label="t('AGENT_VOIP.REMOVE_FAVORITE')"
              :title="t('AGENT_VOIP.REMOVE_FAVORITE')"
              class="absolute -right-2 -top-2 flex size-11 items-center justify-center rounded-full text-n-slate-10 hover:text-n-ruby-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="requestRemoveFavorite(row)"
            >
              <span
                aria-hidden="true"
                class="flex size-6 items-center justify-center rounded-full border border-n-weak bg-n-solid-2 shadow-sm"
                ><span class="i-lucide-pin-off block size-4 text-n-slate-11"
              /></span>
            </button>
          </div>
        </div>
        <nav
          v-if="favoritePages > 1"
          :aria-label="t('AGENT_VOIP.FAVORITES')"
          class="flex items-center justify-end gap-2 text-xs text-n-slate-11"
        >
          <button
            type="button"
            :disabled="favoritePage === 1"
            :aria-label="t('AGENT_VOIP.PREVIOUS')"
            class="flex size-11 items-center justify-center rounded-full hover:bg-n-alpha-1 disabled:opacity-40"
            @click="favoritePage -= 1"
          >
            <span aria-hidden="true" class="i-lucide-chevron-left size-5" />
          </button>
          <span>{{ favoritePage }} / {{ favoritePages }}</span>
          <button
            type="button"
            :disabled="favoritePage === favoritePages"
            :aria-label="t('AGENT_VOIP.NEXT')"
            class="flex size-11 items-center justify-center rounded-full hover:bg-n-alpha-1 disabled:opacity-40"
            @click="favoritePage += 1"
          >
            <span aria-hidden="true" class="i-lucide-chevron-right size-5" />
          </button>
        </nav>
        <div class="mt-4 flex flex-col gap-2">
          <label class="relative block">
            <span
              aria-hidden="true"
              class="i-lucide-search pointer-events-none absolute left-4 top-3 size-5 text-n-slate-11"
            />
            <input
              v-model="search"
              type="search"
              :aria-label="t('AGENT_VOIP.SEARCH')"
              :placeholder="t('AGENT_VOIP.SEARCH')"
              class="min-h-11 w-full rounded-full border border-n-weak bg-n-surface-2 !pl-11 !pr-4"
            />
          </label>
        </div>
        <div class="mb-2 mt-5 flex items-center justify-between gap-2">
          <h2 class="flex items-center gap-2 font-semibold">
            <span
              aria-hidden="true"
              class="i-lucide-history size-4 text-n-slate-11"
            />
            {{ t('AGENT_VOIP.RECENT') }}
          </h2>
          <div class="flex items-center gap-2">
            <button
              type="button"
              :aria-label="t('AGENT_VOIP.FILTERS')"
              :title="t('AGENT_VOIP.FILTERS')"
              :aria-expanded="filtersOpen"
              aria-controls="voip-call-filters"
              aria-haspopup="dialog"
              class="relative flex size-11 shrink-0 items-center justify-center rounded-full border border-n-weak text-n-slate-11"
              @click="
                filtersOpen = true;
                filtersDialog.showModal();
              "
            >
              <span
                aria-hidden="true"
                class="i-lucide-list-filter size-5"
              /><span
                v-if="activeFilters"
                class="absolute -right-1 -top-1 flex size-5 items-center justify-center rounded-full bg-n-brand text-xs text-white"
                >{{ activeFilters }}</span
              ></button
            ><button
              type="button"
              :aria-label="t('AGENT_VOIP.NEW_CALL')"
              :title="t('AGENT_VOIP.NEW_CALL')"
              :disabled="!phone.connected || !!phone.call"
              class="inline-flex size-11 shrink-0 items-center justify-center gap-2 rounded-full bg-n-brand text-white disabled:opacity-50"
              @click="openDialer()"
            >
              <span
                aria-hidden="true"
                class="i-lucide-phone-call size-5 shrink-0"
              />
            </button>
          </div>
        </div>
        <p
          v-if="!items.length && !loading"
          class="my-4 text-sm text-n-slate-11"
        >
          {{ t('AGENT_VOIP.EMPTY') }}
        </p>
        <button
          v-for="row in items"
          :key="row.id"
          type="button"
          class="mb-1 flex w-full min-w-0 items-center gap-3 rounded-xl p-3 text-left hover:bg-n-alpha-1"
          :class="{ 'bg-n-alpha-2': String(row.id) === route.params.callId }"
          @click="select(row)"
        >
          <Avatar
            :name="displayName(row)"
            :src="row.remote_identity?.avatar_url || ''"
            :size="40"
            rounded-full
          />
          <span class="min-w-0 flex-1">
            <span class="block truncate font-medium">
              {{ displayName(row) }}
            </span>
            <span
              class="flex items-center gap-1 text-xs"
              :class="
                row.state === 'missed' ? 'text-red-600' : 'text-n-slate-11'
              "
            >
              <span
                aria-hidden="true"
                :class="callIcon(row)"
                class="size-4 shrink-0"
              />
              <span class="truncate"
                >{{ t(`AGENT_VOIP.DIRECTION.${row.direction}`) }} ·
                {{ t(`AGENT_VOIP.STATE.${row.state}`) }}
              </span>
            </span>
            <span class="block truncate text-xs text-n-slate-11">
              {{ row.service_name }} · {{ date(row.started_at) }}
            </span>
          </span>
        </button>
        <nav
          v-if="pages > 1"
          :aria-label="t('AGENT_VOIP.RECENT')"
          class="my-3 flex items-center justify-center gap-3 text-sm text-n-slate-11"
        >
          <button
            type="button"
            :disabled="loading || page === 1"
            :aria-label="t('AGENT_VOIP.PREVIOUS')"
            class="flex size-11 items-center justify-center rounded-full border border-n-weak disabled:opacity-40"
            @click="changePage(page - 1)"
          >
            <span aria-hidden="true" class="i-lucide-chevron-left size-5" />
          </button>
          <span>{{ page }} / {{ pages }}</span>
          <button
            type="button"
            :disabled="loading || page === pages"
            :aria-label="t('AGENT_VOIP.NEXT')"
            class="flex size-11 items-center justify-center rounded-full border border-n-weak disabled:opacity-40"
            @click="changePage(page + 1)"
          >
            <span aria-hidden="true" class="i-lucide-chevron-right size-5" />
          </button>
        </nav>
        <div class="my-3 md:hidden">
          <AgentVoipCard compact />
        </div>
      </section>
      <section
        :class="route.params.callId ? 'flex' : 'hidden md:flex'"
        class="min-w-0 flex-1 flex-col gap-5 overflow-y-auto p-4 md:p-6"
      >
        <template v-if="detail">
          <header class="flex items-center gap-2">
            <BackButton
              :back-url="accountScopedRoute('agent_voip_calls')"
              :accessible-label="t('AGENT_VOIP.BACK')"
              icon-only
              class="min-h-11 min-w-11 shrink-0"
            />
            <h2 class="text-lg font-semibold">
              {{ t('AGENT_VOIP.DETAIL') }}
            </h2>
          </header>
          <article
            class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak p-4"
          >
            <div class="flex items-center gap-3">
              <Avatar
                :name="displayName(detail)"
                :src="detail.remote_identity?.avatar_url || ''"
                :size="48"
                rounded-full
              />
              <h3 class="min-w-0 break-words text-xl font-semibold">
                {{ displayName(detail) }}
              </h3>
            </div>
            <p class="break-all">
              {{ detail.remote_address }}
            </p>
            <p class="text-sm text-n-slate-11">
              {{ detail.service_name }} · {{ t('AGENT_VOIP.EXTENSION') }}
              {{ detail.extension }}
            </p>
            <p class="flex items-center gap-2">
              <span
                aria-hidden="true"
                :class="callIcon(detail)"
                class="size-5 shrink-0"
              />
              {{ t(`AGENT_VOIP.DIRECTION.${detail.direction}`) }} ·
              {{ t(`AGENT_VOIP.STATE.${detail.state}`) }}
            </p>
            <dl class="grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
              <div
                v-for="field in ['started_at', 'answered_at', 'ended_at']"
                :key="field"
              >
                <dt class="flex items-center gap-2 text-n-slate-11">
                  <span
                    aria-hidden="true"
                    class="i-lucide-calendar-days size-4 shrink-0"
                  />
                  {{
                    t(
                      `AGENT_VOIP.${{ started_at: 'STARTED', answered_at: 'ANSWERED', ended_at: 'ENDED' }[field]}`
                    )
                  }}
                </dt>
                <dd>
                  {{ date(detail[field]) }}
                </dd>
              </div>
              <div>
                <dt class="flex items-center gap-2 text-n-slate-11">
                  <span
                    aria-hidden="true"
                    class="i-lucide-timer size-4 shrink-0"
                  />
                  {{ t('AGENT_VOIP.DURATION') }}
                </dt>
                <dd>
                  {{ duration(detail.duration) }}
                </dd>
              </div>
            </dl>
            <details
              v-if="detail.sip_code || detail.end_reason"
              class="text-sm"
            >
              <summary>
                {{ t('AGENT_VOIP.REASON') }}
              </summary>
              <p class="break-all">
                {{ detail.sip_code }} {{ detail.end_reason }}
              </p>
            </details>
            <button
              type="button"
              :disabled="
                !phone.connected ||
                !!phone.call ||
                phone.activeBinding?.voip_service_id !== detail.service_id
              "
              class="inline-flex min-h-11 items-center gap-2 self-start rounded-full bg-n-brand px-4 text-white disabled:opacity-50"
              @click="openDialer(detail.remote_address, detail.service_id)"
            >
              <span aria-hidden="true" class="i-lucide-phone-outgoing size-5" />
              {{ t('AGENT_VOIP.CALL') }}
            </button>
            <form class="flex flex-wrap gap-2" @submit.prevent="favorite">
              <input
                v-model="favoriteName"
                :placeholder="t('AGENT_VOIP.NAME')"
                :aria-label="t('AGENT_VOIP.NAME')"
                class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-surface-2 p-2"
              />
              <button
                type="submit"
                class="inline-flex min-h-11 items-center gap-2 rounded-lg border border-n-weak px-3"
              >
                <span aria-hidden="true" class="i-lucide-star size-5" />
                {{ t('AGENT_VOIP.ADD_FAVORITE') }}
              </button>
            </form>
          </article>
        </template>
        <template v-else-if="!route.params.callId">
          <div class="my-auto flex flex-col gap-5">
            <span
              aria-hidden="true"
              class="mx-auto flex size-24 items-center justify-center rounded-full bg-n-alpha-2 text-n-brand"
              ><span class="i-lucide-phone size-12"
            /></span>
            <AgentVoipCard />
            <button
              v-if="phone.activeBinding && !phone.connected"
              type="button"
              class="inline-flex min-h-11 items-center gap-2 self-start rounded-full border border-n-weak px-4"
              @click="phone.connect().catch(() => {})"
            >
              <span aria-hidden="true" class="i-lucide-plug size-5" />
              {{ t('AGENT_VOIP.CONNECT') }}
            </button>
            <p class="text-sm text-n-slate-11">
              {{ t('AGENT_VOIP.ONE_SERVICE') }}
            </p>
          </div>
        </template>
      </section>
    </div>
    <dialog
      id="voip-call-filters"
      ref="filtersDialog"
      :aria-label="t('AGENT_VOIP.FILTERS')"
      class="m-auto max-h-[calc(100dvh_-_2rem_-_env(safe-area-inset-top)_-_env(safe-area-inset-bottom))] w-[calc(100%_-_2rem)] max-w-sm overflow-hidden rounded-2xl border border-n-weak bg-n-surface-1 p-0 text-n-slate-12 backdrop:bg-black/50 [&[open]]:flex [&[open]]:flex-col"
      @close="filtersOpen = false"
    >
      <header class="flex shrink-0 items-center justify-between gap-2 p-4 pb-3">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          <span aria-hidden="true" class="i-lucide-list-filter size-5" />{{
            t('AGENT_VOIP.FILTERS')
          }}
        </h2>
        <button
          type="button"
          :aria-label="t('AGENT_VOIP.CLOSE')"
          class="flex size-11 shrink-0 items-center justify-center rounded-full hover:bg-n-alpha-2"
          @click="filtersDialog.close()"
        >
          <span aria-hidden="true" class="i-lucide-x size-5" />
        </button>
      </header>
      <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pb-4">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label class="flex min-w-0 flex-col gap-1 text-xs text-n-slate-11"
            >{{ t('AGENT_VOIP.FILTER_STATE') }}
            <select
              v-model="state"
              :aria-label="t('AGENT_VOIP.FILTER_STATE')"
              class="!mb-0 min-h-11 w-full min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2 text-sm text-n-slate-12"
            >
              <option value="">
                {{ t('AGENT_VOIP.ALL') }}
              </option>
              <option
                v-for="value in [
                  'missed',
                  'unanswered',
                  'ended',
                  'failed',
                  'awaiting_confirmation',
                ]"
                :key="value"
                :value="value"
              >
                {{ t(`AGENT_VOIP.STATE.${value}`) }}
              </option>
            </select>
          </label>
          <label class="flex min-w-0 flex-col gap-1 text-xs text-n-slate-11"
            >{{ t('AGENT_VOIP.FILTER_DIRECTION') }}
            <select
              v-model="direction"
              :aria-label="t('AGENT_VOIP.FILTER_DIRECTION')"
              class="!mb-0 min-h-11 w-full min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2 text-sm text-n-slate-12"
            >
              <option value="">
                {{ t('AGENT_VOIP.ALL') }}
              </option>
              <option value="incoming">
                {{ t('AGENT_VOIP.DIRECTION.incoming') }}
              </option>
              <option value="outgoing">
                {{ t('AGENT_VOIP.DIRECTION.outgoing') }}
              </option>
            </select>
          </label>
        </div>
        <label class="flex items-center gap-2 text-xs text-n-slate-11">
          <span aria-hidden="true" class="i-lucide-network size-4 shrink-0" />
          {{ t('AGENT_VOIP.SERVICE') }}
        </label>
        <select
          v-model="serviceId"
          :aria-label="t('AGENT_VOIP.SERVICE')"
          class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
        >
          <option value="">
            {{ t('AGENT_VOIP.ALL') }}
          </option>
          <option
            v-for="service in phone.services"
            :key="service.id"
            :value="service.id"
          >
            {{ service.name }}
          </option>
        </select>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label class="flex min-w-0 flex-col gap-1 text-xs text-n-slate-11"
            >{{ t('AGENT_VOIP.STARTED') }}
            <input
              v-model="dateFrom"
              type="date"
              :aria-label="t('AGENT_VOIP.STARTED')"
              class="!mb-0 min-h-11 w-full min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2 text-sm text-n-slate-12"
            />
          </label>
          <label class="flex min-w-0 flex-col gap-1 text-xs text-n-slate-11"
            >{{ t('AGENT_VOIP.ENDED') }}
            <input
              v-model="dateUntil"
              type="date"
              :aria-label="t('AGENT_VOIP.ENDED')"
              class="!mb-0 min-h-11 w-full min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2 text-sm text-n-slate-12"
            />
          </label>
        </div>
        <label
          v-if="isAdmin"
          class="flex items-center gap-2 text-xs text-n-slate-11"
        >
          <span
            aria-hidden="true"
            class="i-lucide-user-round size-4 shrink-0"
          />
          {{ t('AGENT_VOIP.AGENT') }}
        </label>
        <select
          v-if="isAdmin"
          v-model="agentId"
          :aria-label="t('AGENT_VOIP.AGENT')"
          class="min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2"
        >
          <option value="">{{ t('AGENT_VOIP.ALL') }}</option>
          <option
            v-for="agent in agents"
            :key="agent.id"
            :value="agent.user_id"
          >
            {{ agent.name }}
          </option>
        </select>
      </div>
      <footer class="shrink-0 border-t border-n-weak p-4">
        <button
          type="button"
          class="min-h-11 w-full rounded-full bg-n-brand px-4 text-white"
          @click="filtersDialog.close()"
        >
          {{ t('AGENT_VOIP.CLOSE') }}
        </button>
      </footer>
    </dialog>
    <dialog
      ref="favoriteRemovalDialog"
      :aria-label="t('AGENT_VOIP.REMOVE_FAVORITE')"
      class="m-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] max-w-sm overflow-y-auto rounded-2xl border border-n-weak bg-n-surface-1 p-5 text-n-slate-12 backdrop:bg-black/50"
      @close="favoriteToRemove = null"
    >
      <h2 class="flex items-center gap-2 text-lg font-semibold">
        <span aria-hidden="true" class="i-lucide-pin-off size-5" />{{
          t('AGENT_VOIP.REMOVE_FAVORITE')
        }}
      </h2>
      <p class="mt-4 break-words text-sm">
        {{
          t('AGENT_VOIP.CONFIRM_REMOVE_FAVORITE', {
            name: favoriteToRemove ? displayName(favoriteToRemove) : '',
          })
        }}
      </p>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ t('AGENT_VOIP.FAVORITE_REMOVAL_HELP') }}
      </p>
      <p
        v-if="favoriteRemovalError"
        role="alert"
        class="mt-3 text-sm text-n-ruby-11"
      >
        {{ favoriteRemovalError }}
      </p>
      <div class="mt-5 flex flex-wrap justify-end gap-2">
        <button
          type="button"
          :disabled="removingFavorite"
          class="min-h-11 rounded-full border border-n-weak px-4"
          @click="favoriteRemovalDialog.close()"
        >
          {{ t('AGENT_VOIP.CANCEL') }}
        </button>
        <button
          type="button"
          :disabled="removingFavorite"
          class="inline-flex min-h-11 items-center justify-center gap-2 rounded-full bg-n-brand px-4 text-white disabled:opacity-50"
          @click="removeFavorite"
        >
          <span aria-hidden="true" class="i-lucide-pin-off size-4" />{{
            t('AGENT_VOIP.REMOVE_FAVORITE')
          }}
        </button>
      </div>
    </dialog>
  </div>
</template>

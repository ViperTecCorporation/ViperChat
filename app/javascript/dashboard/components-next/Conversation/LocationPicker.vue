<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { createPendingMessage } from 'dashboard/helper/commons';
import {
  currentLocation,
  locationMessagePayload,
} from 'dashboard/helper/locationSharing';

const props = defineProps({ conversationId: { type: Number, required: true } });
const emit = defineEmits(['close']);
const { t } = useI18n();
const store = useStore();
const label = key => t(`CONVERSATION.LOCATION_PICKER.${key}`);
const mapElement = ref(null);
const mapUrl = new URL(
  '/location-map',
  window.chatwootConfig?.hostURL || window.location.origin
);
const query = ref('');
const name = ref('');
const address = ref('');
const point = ref(null);
const results = ref([]);
const accuracy = ref(null);
const busy = ref(false);
const sending = ref(false);
const ready = ref(false);
const error = ref('');
let active = true;
let revision = 0;
let timeout;
let autoLocationRequested = false;
const locating = ref(false);
const canSend = computed(() => point.value && !busy.value && !sending.value);

const selectPoint = (position, formattedAddress = '', placeName = '') => {
  revision += 1;
  point.value = { latitude: position.latitude, longitude: position.longitude };
  address.value = formattedAddress;
  name.value = placeName;
  accuracy.value = null;
  results.value = [];
};

const command = data =>
  mapElement.value?.contentWindow?.postMessage(
    { source: 'viper-location-picker', ...data },
    mapUrl.origin
  );
const chooseResult = result => {
  command({ type: 'select', ...result });
};
const locate = async () => {
  if (!ready.value || busy.value) return;
  busy.value = true;
  locating.value = true;
  error.value = '';
  const requestRevision = revision;
  try {
    const { coords } = await currentLocation();
    if (!active || requestRevision !== revision) return;
    selectPoint(coords);
    command({
      type: 'select',
      latitude: coords.latitude,
      longitude: coords.longitude,
    });
    accuracy.value = Math.round(coords.accuracy);
  } catch {
    if (active && requestRevision === revision)
      error.value = label('GPS_ERROR');
  } finally {
    locating.value = false;
    busy.value = false;
  }
};
const receive = event => {
  if (
    event.origin !== mapUrl.origin ||
    event.source !== mapElement.value?.contentWindow ||
    event.data?.source !== 'viper-location-map' ||
    sending.value
  )
    return;
  clearTimeout(timeout);
  const data = event.data;
  if (data.type === 'ready') {
    ready.value = true;
    command({ type: 'hello' });
    if (!autoLocationRequested) {
      autoLocationRequested = true;
      locate();
    }
  } else if (data.type === 'point') {
    const samePoint =
      point.value?.latitude === data.point.latitude &&
      point.value?.longitude === data.point.longitude;
    const previousAccuracy = accuracy.value;
    selectPoint(data.point, data.address, data.name);
    if (samePoint) accuracy.value = previousAccuracy;
    busy.value = false;
  } else if (data.type === 'results') {
    results.value = data.results;
    busy.value = false;
    if (!data.results.length) error.value = label('NO_RESULTS');
  } else if (data.type === 'error') {
    busy.value = false;
    const code = ['SEARCH_ERROR', 'NOT_CONFIGURED'].includes(data.code)
      ? data.code
      : 'MAP_ERROR';
    if (code !== 'SEARCH_ERROR') ready.value = false;
    error.value = label(code);
  }
};
onMounted(() => {
  window.addEventListener('message', receive);
  timeout = setTimeout(() => {
    error.value = label('MAP_ERROR');
  }, 25000);
});

const search = () => {
  if (!ready.value || busy.value || !query.value.trim()) return;
  busy.value = true;
  error.value = '';
  results.value = [];
  command({ type: 'search', query: query.value.trim() });
  timeout = setTimeout(() => {
    busy.value = false;
    error.value = label('SEARCH_ERROR');
  }, 15000);
};

const send = async () => {
  if (!canSend.value) return;
  sending.value = true;
  const pending = createPendingMessage(
    locationMessagePayload(props.conversationId, {
      ...point.value,
      name: name.value.trim(),
      address: address.value.trim(),
    })
  );
  try {
    await store.dispatch('sendMessageWithData', pending);
  } catch {
    // The existing failed-message bubble owns retry; do not offer a second creation here.
  } finally {
    emit('close');
  }
};

onBeforeUnmount(() => {
  active = false;
  clearTimeout(timeout);
  window.removeEventListener('message', receive);
});
</script>

<template>
  <Teleport to="body">
    <Modal
      show
      :close-on-backdrop-click="false"
      :show-close-button="false"
      size="!w-[calc(100%-1rem)] !max-w-2xl"
      @close="emit('close')"
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="location-picker-title"
        class="flex max-h-[90dvh] flex-col overflow-hidden rounded-xl bg-n-solid-1 text-n-slate-12"
      >
        <header
          class="flex shrink-0 items-start justify-between gap-4 border-b border-n-weak p-4 sm:px-6"
        >
          <div class="min-w-0">
            <h2 id="location-picker-title" class="m-0 text-lg font-semibold">
              {{ label('TITLE') }}
            </h2>
            <p class="mb-0 mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ label('HELP') }}
            </p>
          </div>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            class="shrink-0 !size-10"
            :aria-label="label('CANCEL')"
            @click="emit('close')"
          />
        </header>
        <div class="min-h-0 overflow-y-auto px-4 pb-4 sm:px-6">
          <div class="flex gap-2 my-3">
            <input
              v-model="query"
              type="search"
              class="min-w-0 flex-1 !mb-0 !h-11 !rounded-lg !border !border-n-weak !bg-n-alpha-1 !px-3 !text-sm"
              :placeholder="label('SEARCH')"
              :aria-label="label('SEARCH')"
              :disabled="!ready || sending"
              @keydown.enter.prevent="search"
            />
            <Button
              icon="i-lucide-search"
              class="!size-11 shrink-0"
              :aria-label="label('SEARCH')"
              :disabled="!ready || busy || sending"
              @click="search"
            />
          </div>
          <ul
            v-if="results.length"
            class="max-h-44 overflow-y-auto list-none rounded-lg border border-n-weak p-0"
          >
            <li v-for="result in results" :key="result.id">
              <button
                type="button"
                class="w-full p-3 text-left text-sm break-words hover:bg-n-alpha-2"
                @click="chooseResult(result)"
              >
                <span class="block font-medium">{{ result.name }}</span>
                <span class="block text-n-slate-11">{{ result.address }}</span>
              </button>
            </li>
          </ul>
          <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
            {{ error }}
          </p>
          <iframe
            ref="mapElement"
            :src="mapUrl.href"
            :title="label('MAP')"
            referrerpolicy="strict-origin-when-cross-origin"
            :aria-label="label('MAP')"
            class="h-[32dvh] min-h-48 w-full rounded-xl border border-n-weak bg-n-alpha-2 sm:h-[36dvh]"
          />
          <Button
            class="my-3 !min-h-11 w-full sm:w-auto"
            variant="outline"
            icon="i-lucide-locate"
            :label="label(locating ? 'LOCATING' : 'CURRENT')"
            :disabled="!ready || busy || sending"
            :is-loading="locating"
            @click="locate"
          />
          <div
            v-if="point"
            class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3 sm:p-4"
          >
            <p class="m-0 text-xs break-words text-n-slate-11">
              {{
                [point.latitude.toFixed(6), point.longitude.toFixed(6)].join(
                  ', '
                )
              }}
              <span v-if="accuracy">{{
                t('CONVERSATION.LOCATION_PICKER.ACCURACY', { meters: accuracy })
              }}</span>
            </p>
            <label class="!mb-0 flex flex-col gap-1.5 text-sm">
              <span>{{ label('NAME') }}</span>
              <input
                v-model="name"
                type="text"
                maxlength="256"
                :disabled="sending"
                class="w-full !mb-0 !h-11 !rounded-lg !border !border-n-weak !bg-n-solid-1 !px-3 !text-sm"
              />
            </label>
            <label class="!mb-0 flex flex-col gap-1.5 text-sm">
              <span>{{ label('ADDRESS') }}</span>
              <input
                v-model="address"
                type="text"
                maxlength="512"
                :disabled="sending"
                class="w-full !mb-0 !h-11 !rounded-lg !border !border-n-weak !bg-n-solid-1 !px-3 !text-sm"
              />
            </label>
          </div>
        </div>
        <footer
          class="flex shrink-0 justify-end gap-2 border-t border-n-weak p-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:px-6"
        >
          <Button
            :label="label('CANCEL')"
            class="!min-h-11"
            variant="ghost"
            color="slate"
            @click="emit('close')"
          />
          <Button
            :label="label('SEND')"
            class="!min-h-11"
            :disabled="!canSend"
            :is-loading="sending"
            @click="send"
          />
        </footer>
      </section>
    </Modal>
  </Teleport>
</template>

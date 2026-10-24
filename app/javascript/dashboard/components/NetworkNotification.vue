<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { frontendCache } from 'dashboard/helper/CacheHelper/frontendCache';

const { t } = useI18n();
const store = useStore();
const offline = ref(!navigator.onLine);
const socketPending = ref(false);
const visible = ref(false);
let timer;
const cached = computed(() =>
  store?.state.conversations?.allConversations.some(
    chat => chat.isCachedSnapshot || chat.hasCachedMessages
  )
);
const pending = computed(
  () =>
    offline.value ||
    socketPending.value ||
    cached.value ||
    frontendCache.state.validatingSession
);
const text = computed(() => {
  if (offline.value)
    return t(
      cached.value
        ? 'NETWORK.NOTIFICATION.SAVED_OFFLINE'
        : 'NETWORK.NOTIFICATION.OFFLINE'
    );
  return t(
    socketPending.value
      ? 'NETWORK.NOTIFICATION.RECONNECTING'
      : 'NETWORK.NOTIFICATION.UPDATING'
  );
});
watch(
  [pending, offline],
  () => {
    clearTimeout(timer);
    if (!pending.value) visible.value = false;
    else if (offline.value) visible.value = true;
    else
      timer = setTimeout(() => {
        visible.value = pending.value;
      }, 1200);
  },
  { immediate: true }
);
useEventListener('offline', () => {
  offline.value = true;
});
useEventListener('online', () => {
  offline.value = false;
});
useEmitter(BUS_EVENTS.WEBSOCKET_DISCONNECT, () => {
  socketPending.value = true;
});
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT, () => {
  socketPending.value = true;
});
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, () => {
  socketPending.value = false;
});
onBeforeUnmount(() => clearTimeout(timer));
</script>

<template>
  <aside
    v-if="visible"
    role="status"
    aria-live="polite"
    class="pointer-events-none fixed right-3 bottom-[calc(env(safe-area-inset-bottom)+0.125rem)] z-40 flex max-w-[calc(100vw-1.5rem)] items-center gap-1 rounded bg-n-solid-2/80 px-1.5 text-[10px] leading-4 text-n-slate-10"
  >
    <span
      aria-hidden="true"
      class="size-2.5 shrink-0"
      :class="
        offline
          ? 'i-lucide-cloud-off'
          : 'i-lucide-loader-circle animate-spin motion-reduce:animate-none'
      "
    />
    <span>{{ text }}</span>
  </aside>
</template>

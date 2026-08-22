<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { App } from '@capacitor/app';
import { useRouter } from 'vue-router';
import {
  enableNativePush,
  initializeNativePush,
} from '../platform/nativePushService';
import { openNativeNotificationSettings } from '../platform/nativeAppSettingsService';

const router = useRouter();
const installation = window.viperNativeInstallation;
const permission = ref('prompt');
const settingsChannelId = ref();
const isRegistering = ref(false);
const isAvailable = Boolean(installation?.features?.nativePush);
const copy = {
  description: 'Receba avisos de novas conversas.',
  enabling: 'Ativando…',
  enable: 'Ativar notificações',
  settings: 'Abrir configurações',
};
let appStateListener;

const refreshPermission = async () => {
  if (!isAvailable) return;
  const result = await initializeNativePush({ installation, router });
  permission.value = result.receive;
  settingsChannelId.value = result.channelId;
};

onMounted(async () => {
  if (!isAvailable) return;
  let result = await initializeNativePush({ installation, router });
  if (result.receive === 'prompt') {
    result = await enableNativePush({ installation, router });
  }
  permission.value = result.receive;
  settingsChannelId.value = result.channelId;
  appStateListener = await App.addListener('appStateChange', state => {
    if (state.isActive) refreshPermission();
  });
});

onBeforeUnmount(() => appStateListener?.remove());

const enable = async () => {
  isRegistering.value = true;
  try {
    if (permission.value === 'denied') {
      await openNativeNotificationSettings({
        channelId: settingsChannelId.value,
      });
      return;
    }
    const result = await enableNativePush({ installation, router });
    permission.value = result.receive;
    settingsChannelId.value = result.channelId;
  } finally {
    isRegistering.value = false;
  }
};
</script>

<template>
  <aside
    v-if="isAvailable && permission !== 'granted'"
    class="fixed inset-x-3 top-[calc(0.75rem+env(safe-area-inset-top))] z-[1000] mx-auto flex max-w-md items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3 shadow-xl"
  >
    <p class="text-sm text-n-slate-12">{{ copy.description }}</p>
    <button
      :disabled="isRegistering"
      class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:opacity-60"
      @click="enable"
    >
      {{
        isRegistering
          ? copy.enabling
          : permission === 'denied'
            ? copy.settings
            : copy.enable
      }}
    </button>
  </aside>
</template>

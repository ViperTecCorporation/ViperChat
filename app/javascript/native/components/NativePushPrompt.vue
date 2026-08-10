<script setup>
import { onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import {
  enableNativePush,
  initializeNativePush,
} from '../platform/nativePushService';

const router = useRouter();
const installation = window.viperNativeInstallation;
const permission = ref('prompt');
const isRegistering = ref(false);
const isAvailable = Boolean(installation?.features?.nativePush);

onMounted(async () => {
  if (!isAvailable) return;
  const result = await initializeNativePush({ installation, router });
  permission.value = result.receive;
});

const enable = async () => {
  isRegistering.value = true;
  try {
    const result = await enableNativePush({ installation, router });
    permission.value = result.receive;
  } finally {
    isRegistering.value = false;
  }
};
</script>

<template>
  <aside
    v-if="isAvailable && !['granted', 'denied'].includes(permission)"
    class="fixed inset-x-3 top-3 z-[1000] mx-auto flex max-w-md items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3 shadow-xl"
  >
    <p class="text-sm text-n-slate-12">Receba avisos de novas conversas.</p>
    <button
      :disabled="isRegistering"
      class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:opacity-60"
      @click="enable"
    >
      {{ isRegistering ? 'Ativando…' : 'Ativar notificações' }}
    </button>
  </aside>
</template>

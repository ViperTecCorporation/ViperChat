<script setup>
defineProps({ failed: { type: Boolean, default: false } });
defineEmits(['retry']);
const copy = {
  loading: 'Abrindo…',
  failed:
    'Não foi possível conectar ao servidor. Confira sua conexão e tente novamente.',
  retained: 'Tente novamente sem apagar os dados do aplicativo.',
  retry: 'Tentar novamente',
};
</script>

<template>
  <div
    :class="
      failed
        ? 'fixed inset-0 z-[10000] flex items-center justify-center bg-n-background p-6 text-n-slate-12'
        : 'pointer-events-none fixed right-3 top-3 z-[10000] rounded-full bg-n-solid-2 px-3 py-1 text-xs text-n-slate-11'
    "
  >
    <section class="w-full max-w-sm text-center" aria-live="polite">
      <p :class="failed ? 'text-base' : 'text-xs'">
        {{ failed ? copy.failed : copy.loading }}
      </p>
      <template v-if="failed">
        <p class="mt-3 text-sm text-n-slate-11">{{ copy.retained }}</p>
        <button
          type="button"
          class="mt-5 rounded-lg bg-n-brand px-4 py-3 text-white"
          @click="$emit('retry')"
        >
          {{ copy.retry }}
        </button>
      </template>
    </section>
  </div>
</template>

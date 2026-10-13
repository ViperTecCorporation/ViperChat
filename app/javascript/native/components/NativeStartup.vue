<script setup>
defineProps({ failed: { type: Boolean, default: false } });
defineEmits(['retry']);
const copy = {
  loading: 'Conectando ao servidor…',
  failed:
    'Não foi possível conectar ao servidor. Confira sua conexão e tente novamente.',
  retained: 'Tente novamente sem apagar os dados do aplicativo.',
  retry: 'Tentar novamente',
};
</script>

<template>
  <div
    class="fixed inset-0 z-[10000] flex items-center justify-center bg-n-background p-6 text-n-slate-12"
  >
    <section class="w-full max-w-sm text-center" aria-live="polite">
      <p class="text-base">{{ failed ? copy.failed : copy.loading }}</p>
      <progress v-if="!failed" class="mt-4 w-full" :aria-label="copy.loading" />
      <template v-else>
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

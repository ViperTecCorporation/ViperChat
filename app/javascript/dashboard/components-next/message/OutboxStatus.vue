<script setup>
import { offlineOutbox } from 'dashboard/helper/CacheHelper/offlineOutbox';

defineProps({ queue: { type: Object, required: true } });
</script>

<template>
  <span
    role="status"
    class="flex max-w-full flex-wrap items-center gap-2 text-xs"
  >
    <span>{{ $t(`NETWORK.OUTBOX.${queue.state.toUpperCase()}`) }}</span>
    <button
      v-if="queue.state !== 'sending'"
      type="button"
      class="rounded px-2 py-1 underline hover:bg-n-alpha-2"
      @click="offlineOutbox.cancel(queue.id)"
    >
      {{ $t('NETWORK.OUTBOX.CANCEL') }}
    </button>
  </span>
</template>

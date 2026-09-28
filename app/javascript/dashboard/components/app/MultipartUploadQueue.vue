<script setup>
import { onBeforeUnmount } from 'vue';
import { multipartUploads } from 'dashboard/helper/multipartUpload';

onBeforeUnmount(() => [...multipartUploads].forEach(upload => upload.cancel()));
</script>

<template>
  <section
    v-if="multipartUploads.length"
    class="fixed bottom-[max(1rem,env(safe-area-inset-bottom))] inset-x-4 z-50 max-h-[min(16rem,50dvh)] overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-lg sm:left-auto sm:w-80"
    aria-live="polite"
  >
    <div
      v-for="upload in multipartUploads"
      :key="upload.id"
      class="flex gap-3 items-center py-2"
    >
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm text-n-slate-12">{{ upload.name }}</p>
        <p class="text-xs text-n-slate-11">
          {{ $t(`MULTIPART_UPLOAD.${upload.phase}`) }} · {{ upload.percent }}%
        </p>
        <progress
          class="w-full h-2 overflow-hidden rounded [&::-webkit-progress-bar]:bg-n-slate-5 [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
          :value="upload.percent"
          :aria-label="upload.name"
          max="100"
        />
      </div>
      <button
        type="button"
        class="shrink-0 rounded p-2 text-n-slate-12"
        @click="upload.cancel()"
      >
        {{
          $t(
            ['FAILED', 'CANCELLED'].includes(upload.phase)
              ? 'MULTIPART_UPLOAD.CLOSE'
              : 'MULTIPART_UPLOAD.CANCEL'
          )
        }}
      </button>
    </div>
  </section>
</template>

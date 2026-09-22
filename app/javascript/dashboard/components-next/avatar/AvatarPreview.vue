<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  src: { type: String, default: '' },
  name: { type: String, default: '' },
});
const { t } = useI18n();
const dialog = ref(null);
const failed = ref(false);
const open = () => {
  if (!props.src) return;
  failed.value = false;
  dialog.value?.open();
};
watch(
  () => props.src,
  () => dialog.value?.close()
);
</script>

<template>
  <div class="shrink-0" @click.stop @keydown.stop>
    <button
      type="button"
      class="block !p-0 rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :class="{ 'cursor-zoom-in': src }"
      :disabled="!src"
      :aria-label="name"
      aria-haspopup="dialog"
      @click="open"
    >
      <slot />
    </button>
    <Dialog
      ref="dialog"
      :title="name"
      :aria-label="name"
      :show-confirm-button="false"
      :cancel-button-label="t('GENERAL.CLOSE')"
      dialog-class="!w-[calc(100%-2rem)] max-h-[90dvh]"
      overflow-y-auto
    >
      <img
        v-if="!failed"
        :src="src"
        :alt="name"
        class="block w-full max-h-[60dvh] object-contain rounded-lg"
        @error="failed = true"
      />
      <p v-else class="text-n-slate-11" role="status">
        {{ t('CHAT_LIST.NO_CONTENT') }}
      </p>
    </Dialog>
  </div>
</template>

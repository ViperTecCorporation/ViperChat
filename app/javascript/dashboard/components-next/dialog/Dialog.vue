<script setup>
import { ref, computed, useAttrs, defineOptions } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value => ['3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(value),
  },
  dialogClass: {
    type: [String, Array, Object],
    default: '',
  },
  contentClass: {
    type: [String, Array, Object],
    default: '',
  },
  mobileConstrained: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['confirm', 'close']);

defineOptions({ inheritAttrs: false });

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpen = ref(false);
const attrs = useAttrs();

const maxWidthClass = computed(() => {
  const classesMap = {
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

const open = () => {
  isOpen.value = true;
  dialogRef.value?.showModal();
};

const close = () => {
  isOpen.value = false;
  if (dialogRef.value?.open) {
    dialogRef.value.close();
  }
};

const handleNativeClose = () => {
  isOpen.value = false;
  emit('close');
};

// Only close on click-outside if this dialog is the topmost one.
// If another dialog (e.g. ProseMirror prompt) is open on top, ignore.
const handleClickOutside = () => {
  const dialogs = document.querySelectorAll('dialog[open]');
  if (dialogs[dialogs.length - 1] === dialogRef.value) close();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      class="w-full transition-all duration-300 ease-in-out shadow-xl rounded-xl"
      :class="[
        maxWidthClass,
        dialogClass,
        { 'dialog-mobile-constrained': mobileConstrained },
        overflowYAuto ? 'overflow-y-auto' : 'overflow-visible',
      ]"
      v-bind="attrs"
      @close="handleNativeClose"
    >
      <form
        ref="dialogContentRef"
        v-on-click-outside="handleClickOutside"
        class="flex flex-col w-full h-auto gap-6 p-6 overflow-visible text-start align-middle transition-all duration-300 ease-in-out transform bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl"
        :class="contentClass"
        @submit.prevent="confirm"
        @click.stop
      >
        <div v-if="title || description" class="flex flex-col gap-2">
          <h3 class="text-base font-medium leading-6 text-n-slate-12">
            {{ title }}
          </h3>
          <slot name="description">
            <p v-if="description" class="mb-0 text-sm text-n-slate-11">
              {{ description }}
            </p>
          </slot>
        </div>
        <slot v-if="isOpen" />
        <!-- Dialog content will be injected here -->
        <slot name="footer">
          <div
            v-if="showCancelButton || showConfirmButton"
            class="flex items-center justify-between w-full gap-3"
          >
            <Button
              v-if="showCancelButton"
              variant="faded"
              color="slate"
              :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
              class="w-full"
              type="button"
              @click="close"
            />
            <Button
              v-if="showConfirmButton"
              :color="type === 'edit' ? 'blue' : 'ruby'"
              :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
              class="w-full"
              :is-loading="isLoading"
              :disabled="disableConfirmButton || isLoading"
              type="submit"
            />
          </div>
        </slot>
      </form>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}

@media (max-width: 639px) {
  dialog.dialog-mobile-constrained {
    width: calc(100% - 1rem);
    height: calc(100dvh - 1rem);
    max-height: calc(100dvh - 1rem);
    margin: 0.5rem auto;
    overflow: hidden !important;
    overscroll-behavior: contain;
  }

  dialog.dialog-mobile-constrained > form {
    width: 100%;
    height: 100%;
    min-height: 0;
    max-height: 100%;
    overflow: hidden !important;
  }
}

.dialog-position-top {
  margin-top: clamp(2rem, 5vh, 5rem);
  margin-bottom: auto;
}
</style>

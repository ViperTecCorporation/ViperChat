<script>
import Modal from '../../Modal.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    Modal,
    NextButton,
  },
  props: {
    title: {
      type: String,
      default: 'This is a title',
    },
    description: {
      type: String,
      default: 'This is your description',
    },
    confirmLabel: {
      type: String,
      default: 'Yes',
    },
    cancelLabel: {
      type: String,
      default: 'No',
    },
    confirmOnEnter: {
      type: Boolean,
      default: false,
    },
  },
  data: () => ({
    show: false,
    resolvePromise: undefined,
    rejectPromise: undefined,
  }),

  mounted() {
    window.addEventListener('keydown', this.handleKeyDown);
  },

  beforeUnmount() {
    window.removeEventListener('keydown', this.handleKeyDown);
  },

  methods: {
    showConfirmation() {
      this.show = true;
      return new Promise((resolve, reject) => {
        this.resolvePromise = resolve;
        this.rejectPromise = reject;
      });
    },
    confirm() {
      this.resolvePromise(true);
      this.show = false;
    },

    cancel() {
      this.resolvePromise(false);
      this.show = false;
    },
    handleKeyDown(event) {
      if (
        !this.show ||
        !this.confirmOnEnter ||
        event.key !== 'Enter' ||
        event.isComposing ||
        event.repeat
      ) {
        return;
      }

      event.preventDefault();
      this.confirm();
    },
  },
};
</script>

<template>
  <Modal v-model:show="show" :on-close="cancel">
    <div class="h-auto overflow-auto flex flex-col">
      <woot-modal-header :header-title="title" :header-content="description" />
      <slot />
      <div class="flex flex-row justify-end gap-2 py-4 px-6 w-full">
        <NextButton faded type="reset" :label="cancelLabel" @click="cancel" />
        <NextButton type="submit" :label="confirmLabel" @click="confirm" />
      </div>
    </div>
  </Modal>
</template>

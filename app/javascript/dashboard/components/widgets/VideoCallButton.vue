<script>
import { mapGetters } from 'vuex';
import DyteAPI from 'dashboard/api/integrations/dyte';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  props: {
    conversationId: {
      type: Number,
      default: 0,
    },
    menuItem: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['actionComplete'],
  data() {
    return { isLoading: false };
  },
  computed: {
    ...mapGetters({ appIntegrations: 'integrations/getAppIntegrations' }),
    isVideoIntegrationEnabled() {
      return this.appIntegrations.find(
        integration => integration.id === 'dyte' && !!integration.hooks.length
      );
    },
  },
  mounted() {
    if (!this.appIntegrations.length) {
      this.$store.dispatch('integrations/get');
    }
  },
  methods: {
    createErrorMessage(error) {
      const responseError = error?.response?.data?.error;
      if (typeof responseError === 'string') return responseError;

      return (
        responseError?.error?.message ||
        responseError?.message ||
        this.$t('INTEGRATION_SETTINGS.DYTE.CREATE_ERROR')
      );
    },
    async onClick() {
      this.isLoading = true;
      try {
        await DyteAPI.createAMeeting(this.conversationId);
      } catch (error) {
        useAlert(this.createErrorMessage(error));
      } finally {
        this.isLoading = false;
        this.$emit('actionComplete');
      }
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <button
    v-if="isVideoIntegrationEnabled && menuItem"
    type="button"
    class="flex h-9 w-full items-center gap-3 rounded-lg border-0 px-3 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2 disabled:pointer-events-none disabled:opacity-50"
    :disabled="isLoading"
    @click="onClick"
  >
    <span class="i-ph-video-camera size-4" />
    {{ $t('INTEGRATION_SETTINGS.DYTE.START_VIDEO_CALL_HELP_TEXT') }}
  </button>
  <NextButton
    v-else-if="isVideoIntegrationEnabled"
    v-tooltip.top-end="
      $t('INTEGRATION_SETTINGS.DYTE.START_VIDEO_CALL_HELP_TEXT')
    "
    icon="i-ph-video-camera"
    slate
    faded
    sm
    @click="onClick"
  />
</template>

<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const PERMISSION_KEY = 'cw_voice_media_permission_granted';

const store = useStore();
const { t } = useI18n();

const showModal = ref(false);
const isRequesting = ref(false);
const errorMessage = ref('');
const hasChecked = ref(false);

const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const hasCustomVoiceInbox = computed(() =>
  inboxes.value.some(
    inbox => inbox.channel_type === INBOX_TYPES.VOICE && inbox.provider === 'custom'
  )
);

const getStoredPermission = () => {
  try {
    return localStorage.getItem(PERMISSION_KEY) === 'true';
  } catch {
    return false;
  }
};

const storePermission = () => {
  try {
    localStorage.setItem(PERMISSION_KEY, 'true');
  } catch {
    // Ignore storage errors.
  }
};

const checkPermissions = async () => {
  if (!navigator.permissions?.query) return false;

  try {
    const mic = await navigator.permissions.query({ name: 'microphone' });
    const cam = await navigator.permissions.query({ name: 'camera' });
    const micGranted = mic?.state === 'granted';
    const camGranted = cam?.state === 'granted';

    if (micGranted && camGranted) {
      storePermission();
      return true;
    }
  } catch {
    // Ignore permission query errors.
  }

  return false;
};

const stopTracks = stream => {
  stream?.getTracks?.().forEach(track => track.stop());
};

const requestMediaAccess = async () => {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error('getUserMedia not available');
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: true,
    });
    stopTracks(stream);
    return;
  } catch (error) {
    const fallbackStream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: false,
    });
    stopTracks(fallbackStream);
  }
};

const handleRequestAccess = async () => {
  if (isRequesting.value) return;
  isRequesting.value = true;
  errorMessage.value = '';

  try {
    await requestMediaAccess();
    storePermission();
    showModal.value = false;
  } catch {
    errorMessage.value = t('WEBPHONE.PERMISSIONS.ERROR');
  } finally {
    isRequesting.value = false;
  }
};

const closeModal = () => {
  showModal.value = false;
};

watch(
  hasCustomVoiceInbox,
  async hasVoice => {
    if (!hasVoice) return;
    if (hasChecked.value || getStoredPermission()) return;
    hasChecked.value = true;

    const granted = await checkPermissions();
    if (!granted) showModal.value = true;
  },
  { immediate: true }
);
</script>

<template>
  <woot-modal v-model:show="showModal" :on-close="closeModal">
    <div class="flex flex-col gap-4 p-6 w-full max-w-md">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('WEBPHONE.PERMISSIONS.TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11">
        {{ t('WEBPHONE.PERMISSIONS.DESCRIPTION') }}
      </p>
      <p v-if="errorMessage" class="text-sm text-n-ruby-9">
        {{ errorMessage }}
      </p>
      <div class="flex justify-end gap-2">
        <NextButton
          faded
          slate
          :label="t('WEBPHONE.PERMISSIONS.NOT_NOW')"
          @click="closeModal"
        />
        <NextButton
          :label="t('WEBPHONE.PERMISSIONS.ALLOW')"
          :is-loading="isRequesting"
          @click="handleRequestAccess"
        />
      </div>
    </div>
  </woot-modal>
</template>

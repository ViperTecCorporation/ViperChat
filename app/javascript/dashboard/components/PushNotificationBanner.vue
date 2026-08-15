<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { requestPushPermissions } from 'dashboard/helper/pushHelper';
import SessionStorage from 'shared/helpers/sessionStorage';

const props = defineProps({
  accountId: {
    type: [Number, String],
    default: '',
  },
});

const { t } = useI18n();
const permission = ref('granted');
const hasPushSubscription = ref(true);
const isCheckingPushState = ref(true);
const isDismissed = ref(false);
const isActivating = ref(false);

const dismissalKey = computed(
  () => `push-notification-banner-dismissed-${props.accountId || 'global'}`
);

const isPushSupported = computed(
  () =>
    typeof window !== 'undefined' &&
    'Notification' in window &&
    'serviceWorker' in window.navigator &&
    'PushManager' in window &&
    Boolean(window.chatwootConfig?.vapidPublicKey)
);

const shouldShow = computed(
  () =>
    isPushSupported.value &&
    !isCheckingPushState.value &&
    (permission.value !== 'granted' || !hasPushSubscription.value) &&
    !isDismissed.value
);

const syncPushState = async () => {
  if (!isPushSupported.value) {
    isCheckingPushState.value = false;
    return;
  }

  permission.value = window.Notification.permission;
  if (permission.value !== 'granted') {
    hasPushSubscription.value = false;
    isCheckingPushState.value = false;
    return;
  }

  try {
    const registration = await window.navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    hasPushSubscription.value = Boolean(subscription);
  } catch {
    hasPushSubscription.value = false;
  } finally {
    isCheckingPushState.value = false;
  }
};

const dismiss = () => {
  isDismissed.value = true;
  SessionStorage.set(dismissalKey.value, true);
};

const activate = async () => {
  if (permission.value === 'denied') {
    useAlert(t('CHAT_LIST.PUSH_NOTIFICATIONS.BLOCKED'));
    return;
  }

  isActivating.value = true;
  const updatedPermission =
    permission.value === 'granted'
      ? 'granted'
      : await window.Notification.requestPermission();
  permission.value = updatedPermission;

  if (updatedPermission !== 'granted') {
    isActivating.value = false;
    return;
  }

  requestPushPermissions({
    onSuccess: () => {
      isActivating.value = false;
      hasPushSubscription.value = true;
    },
    onError: () => {
      isActivating.value = false;
    },
  });
};

onMounted(() => {
  isDismissed.value = Boolean(SessionStorage.get(dismissalKey.value));
  syncPushState();
  window.addEventListener('focus', syncPushState);
});

onUnmounted(() => window.removeEventListener('focus', syncPushState));
</script>

<template>
  <div class="contents">
    <div
      v-if="shouldShow"
      role="status"
      aria-live="polite"
      class="mx-2 mt-2 mb-1 flex min-h-16 items-center gap-3 rounded-2xl border border-n-brand/20 bg-n-brand/10 px-3 py-2.5 text-n-slate-12 dark:bg-n-brand/15"
    >
      <span
        class="i-lucide-bell-off size-7 flex-shrink-0 text-n-brand"
        aria-hidden="true"
      />
      <div class="min-w-0 flex-1 text-sm leading-5">
        <p class="m-0 font-medium">
          {{ $t('CHAT_LIST.PUSH_NOTIFICATIONS.DISABLED') }}
        </p>
        <button
          type="button"
          class="font-semibold text-n-brand hover:underline disabled:cursor-wait disabled:opacity-60"
          :disabled="isActivating"
          @click="activate"
        >
          {{ $t('CHAT_LIST.PUSH_NOTIFICATIONS.ACTIVATE') }}
        </button>
      </div>
      <button
        type="button"
        class="grid size-8 flex-shrink-0 place-items-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-brand/10 hover:text-n-brand"
        :aria-label="$t('CHAT_LIST.PUSH_NOTIFICATIONS.CLOSE')"
        @click="dismiss"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
      </button>
    </div>
  </div>
</template>

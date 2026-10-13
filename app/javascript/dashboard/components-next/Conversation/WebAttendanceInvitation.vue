<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useWebAttendance } from 'dashboard/composables/useWebAttendance';
import api from 'dashboard/api/webAttendance';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { webAttendanceLimits } from 'dashboard/helper/webAttendance';

const show = defineModel('show', { type: Boolean, default: false });
const chat = useMapGetter('getSelectedChat');
const accountId = useMapGetter('getCurrentAccountId');
const getInbox = useMapGetter('inboxes/getInbox');
const { t } = useI18n();
const inbox = computed(() => getInbox.value(chat.value.inbox_id));
const { attendance, refresh } = useWebAttendance(
  accountId,
  () => chat.value.id
);
const content = ref('');
const busy = ref(false);
const loadError = ref(false);
const loading = ref(false);
const requestId = ref(crypto.randomUUID());
const latest = computed(() => attendance.value?.invitations?.[0]);
const pending = computed(() =>
  ['progress', 'pending', 'queued', 'sending'].includes(latest.value?.status)
);
const provider = computed(
  () => attendance.value?.provider || inbox.value?.provider
);
const buttonText = computed(
  () =>
    attendance.value?.button_text ||
    inbox.value?.web_attendance_button_text ||
    (provider.value === 'whatsapp_cloud'
      ? t('WEB_ATTENDANCE.DEFAULT_BUTTON_CLOUD')
      : t('WEB_ATTENDANCE.DEFAULT_BUTTON'))
);
const limits = computed(() => ({
  invitation:
    attendance.value?.invitation_max_length ??
    webAttendanceLimits(provider.value).invitation,
  button:
    attendance.value?.button_max_length ??
    webAttendanceLimits(provider.value).button,
}));
const canInvite = computed(() => attendance.value?.can_invite === true);
const validLengths = computed(
  () =>
    content.value.trim().length <= limits.value.invitation &&
    buttonText.value.length <= limits.value.button
);
const canSend = computed(
  () =>
    !busy.value &&
    !loading.value &&
    !pending.value &&
    !loadError.value &&
    attendance.value?.enabled &&
    canInvite.value &&
    chat.value.status !== 'resolved' &&
    content.value.trim() &&
    validLengths.value
);

async function load() {
  loadError.value = false;
  loading.value = true;
  try {
    await refresh();
  } catch {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
}

watch(show, value => {
  if (!value) return;
  content.value =
    inbox.value?.web_attendance_invitation_message?.trim() ||
    t('WEB_ATTENDANCE.DEFAULT_CONTENT');
  requestId.value = crypto.randomUUID();
  load();
});
watch(
  () => chat.value.id,
  () => {
    show.value = false;
  }
);

async function run(action, successMessage) {
  if (busy.value) return;
  busy.value = true;
  try {
    await action();
    useAlert(successMessage);
    await load();
  } catch {
    useAlert(t('WEB_ATTENDANCE.ERROR'));
  } finally {
    busy.value = false;
  }
}

async function send() {
  if (!canSend.value) return;
  await run(async () => {
    await api.create(chat.value.id, {
      content: content.value.trim(),
      request_id: requestId.value,
    });
    requestId.value = crypto.randomUUID();
  }, t('WEB_ATTENDANCE.SENT'));
}

async function fallback() {
  if (!canInvite.value || loading.value || loadError.value) return;
  await run(
    () => api.fallback(chat.value.id, latest.value.id),
    t('WEB_ATTENDANCE.FALLBACK_SENT')
  );
}
</script>

<template>
  <Modal
    v-model:show="show"
    size="!w-[calc(100%-1rem)] !max-w-xl"
    :on-close="() => (show = false)"
  >
    <div
      class="flex flex-col gap-4 p-5 w-full min-w-0 max-h-[80dvh] overflow-y-auto"
    >
      <h2 class="m-0 text-lg text-n-slate-12">
        {{ t('WEB_ATTENDANCE.INVITE') }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('WEB_ATTENDANCE.PRIVACY') }}
      </p>
      <p
        v-if="provider === 'whatsapp_cloud'"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('WEB_ATTENDANCE.CLOUD_HELP') }}
      </p>
      <p
        v-if="attendance && !loading && !loadError && !canInvite"
        role="status"
        class="m-0 text-sm text-n-amber-11"
      >
        {{ t('WEB_ATTENDANCE.INVITE_UNAVAILABLE') }}
      </p>
      <p v-if="!validLengths" role="status" class="m-0 text-sm text-n-amber-11">
        {{ t('WEB_ATTENDANCE.LIMIT_ERROR', limits) }}
      </p>
      <div v-if="loadError" class="flex flex-wrap items-center gap-2">
        <span>{{ t('WEB_ATTENDANCE.LOAD_ERROR') }}</span>
        <Button
          :label="t('WEB_ATTENDANCE.RETRY')"
          variant="ghost"
          @click="load"
        />
      </div>
      <label class="text-sm text-n-slate-12">
        {{ t('WEB_ATTENDANCE.CONTENT') }}
        <textarea
          v-model="content"
          rows="3"
          :maxlength="limits.invitation"
          class="w-full min-w-0 mt-2"
          :disabled="busy"
        />
      </label>
      <div class="rounded-xl border border-n-weak p-3 min-w-0">
        <p class="text-xs text-n-slate-11">{{ t('WEB_ATTENDANCE.PREVIEW') }}</p>
        <p class="whitespace-pre-wrap break-words text-n-slate-12">
          {{ content }}
        </p>
        <span
          class="block text-center border-t border-n-weak pt-3 text-n-brand break-words"
        >
          {{ buttonText || t('WEB_ATTENDANCE.DEFAULT_BUTTON') }}
        </span>
      </div>
      <p v-if="pending" role="status" class="m-0 text-sm text-n-slate-11">
        {{ t('WEB_ATTENDANCE.PENDING') }}
      </p>
      <div
        v-if="latest?.failed"
        class="rounded-lg bg-n-amber-2 p-3 break-words"
      >
        <p class="m-0 text-sm">
          {{ t('WEB_ATTENDANCE.FAILED') }} {{ latest.error }}
        </p>
        <Button
          class="mt-2"
          :label="t('WEB_ATTENDANCE.FALLBACK')"
          :disabled="busy || loading || loadError || !canInvite"
          @click="fallback"
        />
      </div>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          v-if="attendance?.active"
          color="ruby"
          variant="ghost"
          :label="t('WEB_ATTENDANCE.REVOKE')"
          :disabled="busy"
          @click="run(() => api.revoke(chat.id), t('WEB_ATTENDANCE.REVOKED'))"
        />
        <Button
          :label="t('WEB_ATTENDANCE.CLOSE')"
          variant="ghost"
          @click="show = false"
        />
        <Button
          :label="t('WEB_ATTENDANCE.SEND')"
          :disabled="!canSend"
          :is-loading="busy"
          @click="send"
        />
      </div>
    </div>
  </Modal>
</template>

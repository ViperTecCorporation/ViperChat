<script setup>
import { computed, ref, watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntervalFn, useEventListener, useMediaQuery } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';
import { useFloatingWebphone } from 'dashboard/composables/useFloatingWebphone';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const { accountId } = useAccount();
const phone = useAgentVoipStore();
const { t } = useI18n();
const now = ref(Date.now());
const devices = ref([]);
const keypad = ref(false);
const audioMenu = ref(false);
const transferMenu = ref(false);
const transferTo = ref('');
const actionBusy = ref(false);
const panel = ref(null);
const isDesktop = useMediaQuery('(min-width: 768px)');
const { startDrag, moveDrag, stopDrag, moveByKeyboard } = useFloatingWebphone(
  panel,
  isDesktop
);
const incoming = computed(
  () => phone.call?.direction === 'incoming' && phone.call?.state === 'ringing'
);
const remoteName = computed(
  () =>
    phone.call?.remote_identity?.name ||
    phone.call?.remote_name ||
    phone.call?.remote_address ||
    ''
);
const remoteAvatar = computed(
  () => phone.call?.remote_identity?.avatar_url || ''
);
const endLabel = computed(() =>
  t(incoming.value ? 'AGENT_VOIP.REJECT' : 'AGENT_VOIP.END')
);
const outputSupported = 'setSinkId' in HTMLMediaElement.prototype;
const duration = computed(() => {
  const seconds = Math.max(
    0,
    Math.floor((now.value - (phone.call?.answeredAt || now.value)) / 1000)
  );
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
});
useIntervalFn(() => {
  now.value = Date.now();
}, 1000);
watch(
  accountId,
  id => {
    if (id)
      phone.prepare(id).catch(() => {
        phone.error = 'configuration_unavailable';
      });
  },
  { immediate: true }
);
onUnmounted(() => phone.stop());
useIntervalFn(() => phone.refreshConfiguration(), 30000);
useEventListener(window, 'beforeunload', event => {
  if (!phone.call && !phone.historyPending) return;
  event.preventDefault();
  event.returnValue = '';
});
async function action(callback) {
  if (actionBusy.value) return;
  actionBusy.value = true;
  phone.error = '';
  try {
    await callback();
  } catch {
    if (!phone.error) phone.error = 'action_failed';
  } finally {
    actionBusy.value = false;
  }
}
async function listDevices() {
  await action(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: false,
    });
    stream.getTracks().forEach(track => track.stop());
    devices.value = await navigator.mediaDevices.enumerateDevices();
  });
}
</script>

<template>
  <Teleport to="body">
    <aside
      v-if="
        phone.call ||
        phone.historyPending ||
        phone.error === 'microphone_denied'
      "
      ref="panel"
      :aria-label="t('AGENT_VOIP.TITLE')"
      class="fixed border border-n-weak bg-n-solid-2 text-n-slate-12 shadow-xl md:bottom-4 md:right-4 md:z-50 md:max-h-[85dvh] md:w-[calc(100%-2rem)] md:max-w-sm md:overflow-y-auto md:rounded-3xl md:p-5"
      :class="
        phone.expanded && phone.call
          ? 'inset-0 z-50 flex h-dvh w-full flex-col overflow-y-auto px-5 pb-[max(env(safe-area-inset-bottom),1.25rem)] pt-[max(env(safe-area-inset-top),1rem)] md:inset-auto md:h-auto'
          : 'bottom-[max(env(safe-area-inset-bottom),1rem)] left-20 right-4 z-30 max-h-[50dvh] overflow-y-auto rounded-2xl p-3 md:left-auto'
      "
    >
      <template v-if="phone.call">
        <header
          class="flex min-w-0 shrink-0 items-center justify-between gap-2"
        >
          <button
            v-if="isDesktop"
            type="button"
            :aria-label="t('AGENT_VOIP.MOVE_WINDOW')"
            class="flex min-h-11 min-w-0 flex-1 cursor-grab touch-none select-none items-center gap-2 rounded-lg text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand active:cursor-grabbing"
            @pointerdown="startDrag"
            @pointermove="moveDrag"
            @pointerup="stopDrag"
            @pointercancel="stopDrag"
            @lostpointercapture="stopDrag"
            @keydown="moveByKeyboard"
          >
            <Avatar
              :name="remoteName"
              :src="remoteAvatar"
              :size="40"
              rounded-full
            />
            <span class="min-w-0">
              <span class="block truncate font-semibold">
                {{ remoteName }}
              </span>
              <span class="block truncate text-xs text-n-slate-11">
                {{ phone.activeBinding?.service_name }} ·
                {{ phone.activeBinding?.extension }}
              </span>
            </span>
          </button>
          <div v-else class="flex min-w-0 flex-1 items-center gap-3">
            <span
              v-if="!phone.expanded"
              class="i-lucide-phone block size-5 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            <span class="min-w-0">
              <span class="block truncate font-semibold">
                {{ remoteName }}
              </span>
              <span class="block truncate text-xs text-n-slate-11">
                {{ phone.activeBinding?.service_name }} ·
                {{ phone.activeBinding?.extension }}
              </span>
            </span>
          </div>
          <button
            v-if="!phone.expanded"
            type="button"
            :disabled="actionBusy"
            :aria-label="endLabel"
            :title="endLabel"
            class="flex size-11 shrink-0 items-center justify-center rounded-full bg-red-700 text-white disabled:opacity-50"
            @click="action(() => phone.hangup())"
          >
            <span class="i-lucide-phone-off block size-5" aria-hidden="true" />
          </button>
          <button
            type="button"
            class="flex size-11 shrink-0 items-center justify-center rounded-full hover:bg-n-alpha-2"
            :aria-label="
              t(phone.expanded ? 'AGENT_VOIP.COMPACT' : 'AGENT_VOIP.EXPAND')
            "
            :title="
              t(phone.expanded ? 'AGENT_VOIP.COMPACT' : 'AGENT_VOIP.EXPAND')
            "
            @click="phone.expanded = !phone.expanded"
          >
            <span
              :class="
                phone.expanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'
              "
              class="block size-5"
            />
          </button>
        </header>
        <div v-if="phone.expanded" class="mx-auto mb-5 mt-8 shrink-0 md:mt-6">
          <Avatar
            :name="remoteName"
            :src="remoteAvatar"
            :size="96"
            rounded-full
          />
        </div>
        <p
          v-if="phone.expanded"
          class="break-words text-center text-2xl font-semibold"
        >
          {{ remoteName }}
        </p>
        <p
          v-if="phone.expanded && remoteName !== phone.call.remote_address"
          class="mt-1 text-center text-xs text-n-slate-11"
        >
          {{ phone.call.remote_address }}
        </p>
        <p
          role="status"
          :class="
            phone.expanded
              ? 'mt-2 text-center text-sm text-n-slate-11'
              : 'mt-1 truncate text-xs text-n-slate-11'
          "
        >
          {{ t(`AGENT_VOIP.STATE.${phone.call.state}`) }}
          <span v-if="phone.call.answeredAt">· {{ duration }} </span>
        </p>
        <div
          v-if="phone.expanded"
          class="mt-auto flex shrink-0 flex-wrap items-start justify-center gap-x-5 gap-y-4 pb-3 pt-8 md:mt-0"
        >
          <div v-if="incoming" class="flex w-20 flex-col items-center gap-2">
            <button
              :disabled="actionBusy"
              type="button"
              :aria-label="t('AGENT_VOIP.ANSWER')"
              :title="t('AGENT_VOIP.ANSWER')"
              class="flex size-14 items-center justify-center rounded-full bg-green-700 text-white disabled:opacity-50"
              @click="action(() => phone.answer())"
            >
              <span class="i-lucide-phone block size-6" aria-hidden="true" />
            </button>
            <span class="text-center text-xs">{{
              t('AGENT_VOIP.ANSWER')
            }}</span>
          </div>
          <div
            v-if="phone.call.state === 'active'"
            class="flex w-20 flex-col items-center gap-2"
          >
            <button
              type="button"
              :aria-pressed="phone.muted"
              :aria-label="
                t(phone.muted ? 'AGENT_VOIP.UNMUTE' : 'AGENT_VOIP.MUTE')
              "
              :title="t(phone.muted ? 'AGENT_VOIP.UNMUTE' : 'AGENT_VOIP.MUTE')"
              class="flex size-14 items-center justify-center rounded-full border border-n-weak"
              :class="
                phone.muted ? 'bg-n-slate-12 text-n-solid-2' : 'bg-n-alpha-2'
              "
              @click="phone.toggleMute()"
            >
              <span
                :class="phone.muted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
                class="block size-6"
                aria-hidden="true"
              />
            </button>
            <span class="text-center text-xs">{{
              t(phone.muted ? 'AGENT_VOIP.UNMUTE' : 'AGENT_VOIP.MUTE')
            }}</span>
          </div>
          <div class="flex w-20 flex-col items-center gap-2">
            <button
              type="button"
              :disabled="actionBusy"
              :aria-label="endLabel"
              :title="endLabel"
              class="flex size-14 items-center justify-center rounded-full bg-red-700 text-white disabled:opacity-50"
              @click="action(() => phone.hangup())"
            >
              <span
                class="i-lucide-phone-off block size-6"
                aria-hidden="true"
              />
            </button>
            <span class="text-center text-xs">{{ endLabel }}</span>
          </div>
        </div>
        <template v-if="phone.expanded">
          <div
            class="flex shrink-0 flex-wrap items-start justify-center gap-x-5 gap-y-4 pb-4 pt-3"
          >
            <div class="flex w-20 flex-col items-center gap-2">
              <button
                type="button"
                :aria-label="t('AGENT_VOIP.KEYPAD')"
                :title="t('AGENT_VOIP.KEYPAD')"
                :aria-expanded="keypad"
                class="flex size-14 items-center justify-center rounded-full bg-n-alpha-2"
                @click="keypad = !keypad"
              >
                <span class="i-lucide-grip block size-6" aria-hidden="true" />
              </button>
              <span class="text-center text-xs">{{
                t('AGENT_VOIP.KEYPAD')
              }}</span>
            </div>
            <div class="flex w-20 flex-col items-center gap-2">
              <button
                type="button"
                :aria-label="t('AGENT_VOIP.AUDIO')"
                :title="t('AGENT_VOIP.AUDIO')"
                :aria-expanded="audioMenu"
                class="flex size-14 items-center justify-center rounded-full bg-n-alpha-2"
                @click="audioMenu = !audioMenu"
              >
                <span
                  class="i-lucide-headphones block size-6"
                  aria-hidden="true"
                />
              </button>
              <span class="text-center text-xs">{{
                t('AGENT_VOIP.AUDIO')
              }}</span>
            </div>
            <div
              v-if="
                phone.activeService?.transfer_enabled &&
                phone.call.state === 'active'
              "
              class="flex w-20 flex-col items-center gap-2"
            >
              <button
                type="button"
                :aria-label="t('AGENT_VOIP.TRANSFER')"
                :title="t('AGENT_VOIP.TRANSFER')"
                :aria-expanded="transferMenu"
                class="flex size-14 items-center justify-center rounded-full bg-n-alpha-2"
                @click="transferMenu = !transferMenu"
              >
                <span
                  class="i-lucide-phone-forwarded block size-6"
                  aria-hidden="true"
                />
              </button>
              <span class="text-center text-xs">{{
                t('AGENT_VOIP.TRANSFER')
              }}</span>
            </div>
          </div>
          <div v-if="keypad" class="mt-3 grid grid-cols-3 gap-2">
            <button
              v-for="digit in '123456789*0#'"
              :key="digit"
              :disabled="phone.call.state !== 'active'"
              type="button"
              class="mx-auto flex size-14 items-center justify-center rounded-full bg-n-alpha-2 text-xl disabled:opacity-50"
              @click="action(() => phone.dtmf(digit))"
            >
              {{ digit }}
            </button>
          </div>
          <div v-if="audioMenu" class="mt-3 flex flex-col gap-3">
            <button
              type="button"
              class="flex min-h-11 items-center justify-center gap-2 rounded-lg border border-n-weak p-2 text-sm"
              @click="listDevices"
            >
              <span
                class="i-lucide-mic block size-5 shrink-0"
                aria-hidden="true"
              />
              {{ t('AGENT_VOIP.PERMISSION') }}
            </button>
            <label class="flex min-w-0 flex-col gap-1 text-sm">
              {{ t('AGENT_VOIP.MICROPHONE') }}
              <select
                class="max-w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
                @change="action(() => phone.microphone($event.target.value))"
              >
                <option value="">
                  {{ t('AGENT_VOIP.DEFAULT_DEVICE') }}
                </option>
                <option
                  v-for="device in devices.filter(
                    row => row.kind === 'audioinput'
                  )"
                  :key="device.deviceId"
                  :value="device.deviceId"
                >
                  {{ device.label || device.deviceId }}
                </option>
              </select>
            </label>
            <label
              v-if="outputSupported"
              class="flex min-w-0 flex-col gap-1 text-sm"
            >
              {{ t('AGENT_VOIP.SPEAKER') }}
              <select
                class="max-w-full rounded-lg border border-n-weak bg-n-surface-2 p-2"
                @change="action(() => phone.speaker($event.target.value))"
              >
                <option value="">
                  {{ t('AGENT_VOIP.DEFAULT_DEVICE') }}
                </option>
                <option
                  v-for="device in devices.filter(
                    row => row.kind === 'audiooutput'
                  )"
                  :key="device.deviceId"
                  :value="device.deviceId"
                >
                  {{ device.label || device.deviceId }}
                </option>
              </select>
            </label>
            <p v-else class="text-sm text-n-slate-11">
              {{ t('AGENT_VOIP.OUTPUT_LIMIT') }}
            </p>
          </div>
          <form
            v-if="
              phone.activeService?.transfer_enabled &&
              phone.call.state === 'active' &&
              transferMenu
            "
            class="mt-3 flex min-w-0 gap-2"
            @submit.prevent="action(() => phone.transfer(transferTo))"
          >
            <input
              v-model="transferTo"
              :aria-label="t('AGENT_VOIP.EXTENSION')"
              class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-surface-2 p-2"
              required
            />
            <button
              type="submit"
              :disabled="actionBusy"
              :aria-label="t('AGENT_VOIP.TRANSFER')"
              :title="t('AGENT_VOIP.TRANSFER')"
              class="flex size-11 shrink-0 items-center justify-center rounded-full bg-n-alpha-2 disabled:opacity-50"
            >
              <span
                class="i-lucide-phone-forwarded block size-5"
                aria-hidden="true"
              />
            </button>
          </form>
          <p v-if="phone.transferState" role="status" class="mt-2 text-sm">
            {{
              t('AGENT_VOIP.TRANSFER_STATUS', { status: phone.transferState })
            }}
          </p>
        </template>
        <button
          v-if="phone.error === 'audio_blocked'"
          type="button"
          class="mt-3 flex min-h-11 items-center justify-center gap-2 rounded-lg border border-n-weak px-3"
          @click="phone.resumeAudio()"
        >
          <span
            class="i-lucide-volume-2 block size-5 shrink-0"
            aria-hidden="true"
          />
          {{ t('AGENT_VOIP.PLAY_AUDIO') }}
        </button>
        <p
          v-else-if="phone.error && phone.error !== 'microphone_denied'"
          role="alert"
          class="mt-2 text-sm text-n-ruby-11"
        >
          {{ t('AGENT_VOIP.ERROR') }}
        </p>
      </template>
      <div
        v-if="phone.error === 'microphone_denied'"
        role="alert"
        class="mt-2 flex min-w-0 items-start gap-2 text-sm"
      >
        <span
          class="i-lucide-mic-off mt-1 block size-5 shrink-0 text-n-ruby-11"
          aria-hidden="true"
        />
        <div class="min-w-0 flex-1 break-words">
          <p class="font-semibold text-n-ruby-11">
            {{ t('AGENT_VOIP.MICROPHONE_DENIED') }}
          </p>
          <p class="mt-1 text-n-slate-11">
            {{ t('AGENT_VOIP.MICROPHONE_DENIED_HELP') }}
          </p>
        </div>
        <button
          type="button"
          :aria-label="t('AGENT_VOIP.CLOSE')"
          class="flex size-11 shrink-0 items-center justify-center rounded-full hover:bg-n-alpha-2"
          @click="phone.error = ''"
        >
          <span class="i-lucide-x block size-5" aria-hidden="true" />
        </button>
      </div>
      <p
        v-if="phone.historyPending"
        role="status"
        class="mt-2 text-sm text-n-amber-11"
      >
        {{ t('AGENT_VOIP.HISTORY_PENDING') }}
      </p>
    </aside>
  </Teleport>
</template>

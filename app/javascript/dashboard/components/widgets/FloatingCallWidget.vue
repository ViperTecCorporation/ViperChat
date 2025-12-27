<script setup>
import { watch, ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCallSession } from 'dashboard/composables/useCallSession';
import WindowVisibilityHelper from 'dashboard/helper/AudioAlerts/WindowVisibilityHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const router = useRouter();
const store = useStore();
const { t } = useI18n();

const {
  activeCall,
  incomingCalls,
  hasActiveCall,
  isJoining,
  joinCall,
  endCall: endCallSession,
  rejectIncomingCall,
  dismissCall,
  formattedCallDuration,
  transferCall,
} = useCallSession();

const showTransferModal = ref(false);
const transferQuery = ref('');
const selectedAgent = ref(null);
const isTransferring = ref(false);

const getCallInfo = call => {
  const conversation = store.getters.getConversationById(call?.conversationId);
  const inboxId = call?.inboxId || conversation?.inbox_id;
  const inbox = store.getters['inboxes/getInboxById'](inboxId);
  const sender = conversation?.meta?.sender;
  return {
    conversation,
    inbox,
    contactName: sender?.name || sender?.phone_number || 'Unknown caller',
    inboxName: inbox?.name || 'Customer support',
    avatar: sender?.avatar || sender?.thumbnail,
  };
};

const activeCallContext = computed(() => {
  const call = activeCall.value;
  if (!call) return null;
  const conversation = getCallInfo(call).conversation;
  const inboxId = call.inboxId || conversation?.inbox_id;
  return {
    call,
    conversationId: call.conversationId,
    inboxId,
  };
});

const canTransfer = computed(() => {
  const inboxId = activeCallContext.value?.inboxId;
  if (!inboxId) return false;
  const inbox = store.getters['inboxes/getInboxById'](inboxId);
  return inbox?.provider === 'custom';
});

const assignableAgents = computed(() => {
  const inboxId = activeCallContext.value?.inboxId;
  if (!inboxId) return [];
  return store.getters['inboxAssignableAgents/getAssignableAgents'](`${inboxId}`);
});

const filteredAgents = computed(() => {
  const query = transferQuery.value.toLowerCase();
  const currentUserId = store.getters.getCurrentUserID;
  return assignableAgents.value.filter(agent => {
    if (agent.id === currentUserId) return false;
    if (!query) return true;
    return agent.name.toLowerCase().includes(query);
  });
});

const openTransferModal = async () => {
  if (!canTransfer.value) return;
  const inboxId = activeCallContext.value?.inboxId;
  if (!inboxId) return;
  await store.dispatch('inboxAssignableAgents/fetch', [inboxId]);
  selectedAgent.value = null;
  transferQuery.value = '';
  showTransferModal.value = true;
};

const closeTransferModal = () => {
  showTransferModal.value = false;
  selectedAgent.value = null;
};

const handleTransfer = async () => {
  const ctx = activeCallContext.value;
  if (!ctx?.inboxId || !selectedAgent.value?.id) return;

  isTransferring.value = true;
  try {
    await transferCall({
      conversationId: ctx.conversationId,
      inboxId: ctx.inboxId,
      targetAgentId: selectedAgent.value.id,
      callSid: ctx.call.callSid,
    });
    await store.dispatch('assignAgent', {
      conversationId: ctx.conversationId,
      agentId: selectedAgent.value.id,
    });
    useAlert(t('CONVERSATION.VOICE_WIDGET.TRANSFER_SUCCESS'));
    closeTransferModal();
  } catch (error) {
    useAlert(t('CONVERSATION.VOICE_WIDGET.TRANSFER_ERROR'));
  } finally {
    isTransferring.value = false;
  }
};

const handleEndCall = async () => {
  const call = activeCall.value;
  if (!call) return;

  const inboxId = call.inboxId || getCallInfo(call).conversation?.inbox_id;
  if (!inboxId) return;

  await endCallSession({
    conversationId: call.conversationId,
    inboxId,
  });
};

const handleJoinCall = async call => {
  const { conversation } = getCallInfo(call);
  if (!call || !conversation || isJoining.value) return;

  // End current active call before joining new one
  if (hasActiveCall.value) {
    await handleEndCall();
  }

  const result = await joinCall({
    conversationId: call.conversationId,
    inboxId: call.inboxId || conversation.inbox_id,
    callSid: call.callSid,
  });

  if (result) {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: call.conversationId },
    });
  }
};

// Auto-join outbound calls when window is visible
watch(
  () => incomingCalls.value[0],
  call => {
    if (
      call?.callDirection === 'outbound' &&
      !hasActiveCall.value &&
      WindowVisibilityHelper.isWindowVisible()
    ) {
      handleJoinCall(call);
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="incomingCalls.length || hasActiveCall"
    class="fixed ltr:right-4 rtl:left-4 bottom-4 z-50 flex flex-col gap-2 w-72"
  >
    <!-- Incoming Calls (shown above active call) -->
    <div
      v-for="call in hasActiveCall ? incomingCalls : []"
      :key="call.callSid"
      class="flex items-center gap-3 p-4 bg-n-solid-2 rounded-xl shadow-xl outline outline-1 outline-n-strong"
    >
      <div class="animate-pulse ring-2 ring-n-teal-9 rounded-full inline-flex">
        <Avatar
          :src="getCallInfo(call).avatar"
          :name="getCallInfo(call).contactName"
          :size="40"
          rounded-full
        />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-n-slate-12 truncate mb-0">
          {{ getCallInfo(call).contactName }}
        </p>
        <p class="text-xs text-n-slate-11 truncate">
          {{ getCallInfo(call).inboxName }}
        </p>
      </div>
      <div class="flex shrink-0 gap-2">
        <button
          class="flex justify-center items-center w-10 h-10 bg-n-ruby-9 hover:bg-n-ruby-10 rounded-full transition-colors"
          @click="dismissCall(call.callSid)"
        >
          <i class="text-lg text-white i-ph-phone-x-bold" />
        </button>
        <button
          class="flex justify-center items-center w-10 h-10 bg-n-teal-9 hover:bg-n-teal-10 rounded-full transition-colors"
          @click="handleJoinCall(call)"
        >
          <i class="text-lg text-white i-ph-phone-bold" />
        </button>
      </div>
    </div>

    <!-- Main Call Widget -->
    <div
      v-if="hasActiveCall || incomingCalls.length"
      class="flex items-center gap-3 p-4 bg-n-solid-2 rounded-xl shadow-xl outline outline-1 outline-n-strong"
    >
      <div
        class="ring-2 ring-n-teal-9 rounded-full inline-flex"
        :class="{ 'animate-pulse': !hasActiveCall }"
      >
        <Avatar
          :src="getCallInfo(activeCall || incomingCalls[0]).avatar"
          :name="getCallInfo(activeCall || incomingCalls[0]).contactName"
          :size="40"
          rounded-full
        />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-n-slate-12 truncate mb-0">
          {{ getCallInfo(activeCall || incomingCalls[0]).contactName }}
        </p>
        <p v-if="hasActiveCall" class="font-mono text-sm text-n-teal-9">
          {{ formattedCallDuration }}
        </p>
        <p v-else class="text-xs text-n-slate-11">
          {{
            incomingCalls[0]?.callDirection === 'outbound'
              ? $t('CONVERSATION.VOICE_WIDGET.OUTGOING_CALL')
              : $t('CONVERSATION.VOICE_WIDGET.INCOMING_CALL')
          }}
        </p>
      </div>
      <div class="flex shrink-0 gap-2">
        <button
          v-if="hasActiveCall && canTransfer"
          class="flex justify-center items-center w-10 h-10 bg-n-slate-9 hover:bg-n-slate-10 rounded-full transition-colors"
          @click="openTransferModal"
        >
          <i class="text-lg text-white i-lucide-phone-forwarded" />
        </button>
        <button
          class="flex justify-center items-center w-10 h-10 bg-n-ruby-9 hover:bg-n-ruby-10 rounded-full transition-colors"
          @click="
            hasActiveCall
              ? handleEndCall()
              : rejectIncomingCall(incomingCalls[0]?.callSid)
          "
        >
          <i class="text-lg text-white i-ph-phone-x-bold" />
        </button>
        <button
          v-if="!hasActiveCall"
          class="flex justify-center items-center w-10 h-10 bg-n-teal-9 hover:bg-n-teal-10 rounded-full transition-colors"
          @click="handleJoinCall(incomingCalls[0])"
        >
          <i class="text-lg text-white i-ph-phone-bold" />
        </button>
      </div>
    </div>

    <woot-modal v-model:show="showTransferModal" :on-close="closeTransferModal">
      <div class="flex flex-col gap-4 p-6 w-full max-w-md">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ $t('CONVERSATION.VOICE_WIDGET.TRANSFER_TITLE') }}
        </h3>
        <input
          v-model="transferQuery"
          type="search"
          class="w-full px-3 py-2 rounded-md border border-n-strong bg-transparent text-sm"
          :placeholder="$t('CONVERSATION.VOICE_WIDGET.TRANSFER_SEARCH_PLACEHOLDER')"
        />
        <div class="max-h-64 overflow-y-auto flex flex-col gap-2">
          <button
            v-for="agent in filteredAgents"
            :key="agent.id"
            class="flex items-center gap-2 px-3 py-2 rounded-md hover:bg-n-slate-3 text-left"
            @click="selectedAgent = agent"
          >
            <Avatar
              :name="agent.name"
              :src="agent.thumbnail"
              :size="28"
              rounded-full
            />
            <span class="text-sm text-n-slate-12">
              {{ agent.name }}
            </span>
          </button>
        </div>
        <div class="flex justify-end gap-2">
          <NextButton
            faded
            slate
            :label="$t('CONVERSATION.VOICE_WIDGET.TRANSFER_CANCEL')"
            @click="closeTransferModal"
          />
          <NextButton
            :label="$t('CONVERSATION.VOICE_WIDGET.TRANSFER_CONFIRM')"
            :disabled="!selectedAgent"
            :is-loading="isTransferring"
            @click="handleTransfer"
          />
        </div>
      </div>
    </woot-modal>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import conversationApi from 'dashboard/api/inbox/conversation';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Modal from 'dashboard/components/Modal.vue';
import ConfirmationModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  isSessionAdmin: {
    type: Boolean,
    default: false,
  },
  announcement: {
    type: Boolean,
    default: false,
  },
  locked: {
    type: Boolean,
    default: false,
  },
  joinApprovalMode: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['permissionsUpdated', 'groupLeft']);
const show = defineModel('show', { type: Boolean, default: false });

const { t } = useI18n();
const onlyAdminsCanSend = ref(false);
const onlyAdminsCanEdit = ref(false);
const approveNewParticipants = ref(false);
const isSaving = ref(false);
const isLeaving = ref(false);
const isVerifyingLeave = ref(false);
const leaveStateUnverified = ref(false);
const leaveConfirmation = ref(null);

const resetState = () => {
  onlyAdminsCanSend.value = props.announcement;
  onlyAdminsCanEdit.value = props.locked;
  approveNewParticipants.value = props.joinApprovalMode === 'approval_required';
};

const close = () => {
  show.value = false;
};

const savePermissions = async () => {
  if (!props.isSessionAdmin || isSaving.value) return;

  isSaving.value = true;
  try {
    const { data } = await conversationApi.updateGroup({
      conversationId: props.conversationId,
      announcement: onlyAdminsCanSend.value,
      locked: onlyAdminsCanEdit.value,
      join_approval_mode: approveNewParticipants.value
        ? 'approval_required'
        : 'open',
    });
    emit('permissionsUpdated', data);
    close();
    useAlert(t('CONVERSATION.GROUP.PERMISSIONS_SAVED'));
  } catch (error) {
    resetState();
    useAlert(
      error.response?.data?.error ||
        error.message ||
        t('CONVERSATION.GROUP.PERMISSIONS_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const isTimeoutError = error =>
  ['ECONNABORTED', 'ETIMEDOUT'].includes(error.code) ||
  [408, 504, 524].includes(error.response?.status);

const sessionWasRemoved = data =>
  Boolean(data?.additional_attributes?.group_session_removed_at);

const completeLeave = data => {
  leaveStateUnverified.value = false;
  emit('groupLeft', data);
  close();
  useAlert(t('CONVERSATION.GROUP.LEAVE_SUCCESS'));
};

const verifyLeaveState = async () => {
  if (isVerifyingLeave.value) return;

  isVerifyingLeave.value = true;
  try {
    const { data } = await conversationApi.syncGroup(props.conversationId);
    if (sessionWasRemoved(data)) {
      completeLeave(data);
      return;
    }

    leaveStateUnverified.value = false;
    useAlert(t('CONVERSATION.GROUP.LEAVE_TIMEOUT_STILL_MEMBER'));
  } catch {
    leaveStateUnverified.value = true;
    useAlert(t('CONVERSATION.GROUP.LEAVE_STATUS_UNKNOWN'));
  } finally {
    isVerifyingLeave.value = false;
  }
};

const leaveGroup = async () => {
  if (
    isLeaving.value ||
    isSaving.value ||
    isVerifyingLeave.value ||
    leaveStateUnverified.value
  ) {
    return;
  }

  const confirmed = await leaveConfirmation.value.showConfirmation();
  if (!confirmed) return;

  isLeaving.value = true;
  try {
    const { data } = await conversationApi.leaveGroup(props.conversationId);
    completeLeave(data);
  } catch (error) {
    if (isTimeoutError(error)) {
      leaveStateUnverified.value = true;
      useAlert(t('CONVERSATION.GROUP.LEAVE_TIMEOUT_VERIFYING'));
      await verifyLeaveState();
      return;
    }

    useAlert(
      error.response?.data?.error ||
        error.message ||
        t('CONVERSATION.GROUP.LEAVE_ERROR')
    );
  } finally {
    isLeaving.value = false;
  }
};

watch(
  () => show.value,
  isVisible => {
    if (isVisible) resetState();
  }
);
</script>

<template>
  <Modal v-model:show="show" size="medium" :on-close="close">
    <div class="flex flex-col">
      <div class="flex items-start gap-3 border-b border-n-weak px-6 py-5">
        <span
          class="i-lucide-shield-check mt-0.5 size-5 shrink-0 text-n-slate-11"
        />
        <div>
          <h3 class="m-0 text-lg font-medium text-n-slate-12">
            {{ $t('CONVERSATION.GROUP.PERMISSIONS') }}
          </h3>
          <p class="m-0 text-sm text-n-slate-10">
            {{ $t('CONVERSATION.GROUP.PERMISSIONS_SUBTITLE') }}
          </p>
        </div>
      </div>

      <div class="flex flex-col gap-3 px-6 py-5">
        <div
          v-if="!isSessionAdmin"
          class="rounded-md border border-n-weak bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-11"
        >
          {{ $t('CONVERSATION.GROUP.PERMISSIONS_ADMIN_REQUIRED') }}
        </div>

        <div
          v-if="leaveStateUnverified"
          class="flex items-center justify-between gap-3 rounded-md border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
        >
          <span>{{ $t('CONVERSATION.GROUP.LEAVE_STATUS_UNKNOWN') }}</span>
          <Button
            variant="faded"
            color="amber"
            size="xs"
            :label="$t('CONVERSATION.GROUP.VERIFY_LEAVE_STATUS')"
            :disabled="isVerifyingLeave"
            :is-loading="isVerifyingLeave"
            @click="verifyLeaveState"
          />
        </div>

        <label
          class="flex items-start gap-3 rounded-lg border border-n-weak p-3"
          :class="{ 'cursor-not-allowed opacity-60': !isSessionAdmin }"
        >
          <Checkbox
            v-model="onlyAdminsCanSend"
            :disabled="!isSessionAdmin || isSaving || isLeaving"
            class="mt-0.5"
          />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.GROUP.PERMISSION_SEND_MESSAGES') }}
            </span>
            <span class="block text-xs text-n-slate-10">
              {{ $t('CONVERSATION.GROUP.PERMISSION_SEND_MESSAGES_HELP') }}
            </span>
          </span>
        </label>

        <label
          class="flex items-start gap-3 rounded-lg border border-n-weak p-3"
          :class="{ 'cursor-not-allowed opacity-60': !isSessionAdmin }"
        >
          <Checkbox
            v-model="onlyAdminsCanEdit"
            :disabled="!isSessionAdmin || isSaving || isLeaving"
            class="mt-0.5"
          />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.GROUP.PERMISSION_EDIT_GROUP') }}
            </span>
            <span class="block text-xs text-n-slate-10">
              {{ $t('CONVERSATION.GROUP.PERMISSION_EDIT_GROUP_HELP') }}
            </span>
          </span>
        </label>

        <label
          class="flex items-start gap-3 rounded-lg border border-n-weak p-3"
          :class="{ 'cursor-not-allowed opacity-60': !isSessionAdmin }"
        >
          <Checkbox
            v-model="approveNewParticipants"
            :disabled="!isSessionAdmin || isSaving || isLeaving"
            class="mt-0.5"
          />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.GROUP.PERMISSION_APPROVE_PARTICIPANTS') }}
            </span>
            <span class="block text-xs text-n-slate-10">
              {{
                $t('CONVERSATION.GROUP.PERMISSION_APPROVE_PARTICIPANTS_HELP')
              }}
            </span>
          </span>
        </label>
      </div>

      <div
        class="flex items-center justify-between gap-3 border-t border-n-weak px-6 py-4"
      >
        <Button
          variant="faded"
          color="ruby"
          size="sm"
          icon="i-lucide-log-out"
          :label="$t('CONVERSATION.GROUP.LEAVE')"
          :disabled="
            isSaving || isLeaving || isVerifyingLeave || leaveStateUnverified
          "
          :is-loading="isLeaving"
          @click="leaveGroup"
        />
        <div class="flex justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            :label="$t('CONVERSATION.GROUP.CANCEL')"
            :disabled="isSaving || isLeaving || isVerifyingLeave"
            @click="close"
          />
          <Button
            color="blue"
            size="sm"
            :label="$t('CONVERSATION.GROUP.SAVE_PERMISSIONS')"
            :disabled="
              !isSessionAdmin || isSaving || isLeaving || isVerifyingLeave
            "
            :is-loading="isSaving"
            @click="savePermissions"
          />
        </div>
      </div>
    </div>
  </Modal>
  <ConfirmationModal
    ref="leaveConfirmation"
    :title="$t('CONVERSATION.GROUP.LEAVE_CONFIRM_TITLE')"
    :description="$t('CONVERSATION.GROUP.LEAVE_CONFIRM_DESCRIPTION')"
    :confirm-label="$t('CONVERSATION.GROUP.LEAVE_CONFIRM')"
    :cancel-label="$t('CONVERSATION.GROUP.CANCEL')"
  />
</template>

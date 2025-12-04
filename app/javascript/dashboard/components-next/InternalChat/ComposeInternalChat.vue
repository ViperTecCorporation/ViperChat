<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { useAlert } from 'dashboard/composables';
import InternalConversationsAPI from 'dashboard/api/internalConversations';
import Avatar from 'next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MultiselectDropdownItems from 'shared/components/ui/MultiselectDropdownItems.vue';

const props = defineProps({
  alignPosition: {
    type: String,
    default: 'left',
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();

const agents = useMapGetter('agents/getVerifiedAgents');
const currentUser = useMapGetter('getCurrentUser');
const inboxes = useMapGetter('inboxes/getInboxes');

const showCompose = ref(false);
const showParticipantsDropdown = ref(false);
const selectedInboxId = ref(null);
const selectedParticipants = ref([]);
const title = ref('');
const message = ref('');
const isSubmitting = ref(false);

const internalInboxes = computed(() =>
  inboxes.value.filter(inbox => inbox.channel_type === 'Channel::Internal')
);

const selectedInbox = computed(() =>
  internalInboxes.value.find(inbox => inbox.id === Number(selectedInboxId.value))
);

const canSubmit = computed(() => {
  return (
    selectedInbox.value &&
    selectedParticipants.value.length > 0 &&
    message.value.trim().length > 0 &&
    !isSubmitting.value
  );
});

const toggle = () => {
  showCompose.value = !showCompose.value;
  if (!showCompose.value) {
    emit('close');
  }
};

const resetForm = () => {
  selectedInboxId.value = null;
  selectedParticipants.value = [];
  title.value = '';
  message.value = '';
};

const handleClickOutside = () => {
  if (!showCompose.value) return;
  showCompose.value = false;
  showParticipantsDropdown.value = false;
  resetForm();
  emit('close');
};

const onSelectParticipant = user => {
  const exists = selectedParticipants.value.some(
    participant => participant.id === user.id
  );
  if (exists) {
    selectedParticipants.value = selectedParticipants.value.filter(
      participant => participant.id !== user.id
    );
  } else {
    selectedParticipants.value = [...selectedParticipants.value, user];
  }
};

const onSelfAdd = user => {
  if (!user?.id) return;
  const exists = selectedParticipants.value.some(
    participant => participant.id === user.id
  );
  if (!exists) {
    selectedParticipants.value = [...selectedParticipants.value, user];
  }
};

const createInternalConversation = async () => {
  if (!canSubmit.value) return;
  isSubmitting.value = true;
  try {
    const payload = {
      inbox_id: selectedInbox.value.id,
      title: title.value,
      participant_ids: selectedParticipants.value.map(user => user.id),
      message: { content: message.value.trim() },
    };
    const { data } = await InternalConversationsAPI.create(payload);
    const conversationLink = frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: data.id,
      })
    );

    useAlert(t('CONVERSATION.INTERNAL_CHAT.SUCCESS'), {
      type: 'link',
      to: conversationLink,
      message: t('CONVERSATION.INTERNAL_CHAT.GO_TO_CONVERSATION'),
    });

    router.push(conversationLink);
    resetForm();
    showCompose.value = false;
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error || t('CONVERSATION.INTERNAL_CHAT.ERROR');
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};

const composePopoverClass = computed(() => {
  return props.alignPosition === 'right'
    ? 'absolute ltr:left-0 ltr:right-[unset] rtl:right-0 rtl:left-[unset]'
    : 'absolute rtl:left-0 rtl:right-[unset] ltr:right-0 ltr:left-[unset]';
});

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('inboxes/get');
});
</script>

<template>
  <div
    v-on-click-outside="handleClickOutside"
    class="relative"
    :class="{ 'z-50': showCompose }"
  >
    <slot name="trigger" :is-open="showCompose" :toggle="toggle" />
    <div
      v-if="showCompose"
      class="fixed z-50 bg-n-alpha-black1 backdrop-blur-[4px] flex items-start pt-[clamp(3rem,15vh,10rem)] justify-center inset-0"
      @click.self="handleClickOutside"
    >
      <div
        :class="composePopoverClass"
        class="bg-n-solid-1 border border-n-strong rounded-xl shadow-2xl w-full max-w-xl mx-auto p-4 grid gap-4"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="m-0 text-base font-semibold text-n-slate-12">
              {{ $t('CONVERSATION.INTERNAL_CHAT.TITLE') }}
            </p>
            <p class="m-0 text-sm text-n-slate-10">
              {{ $t('CONVERSATION.INTERNAL_CHAT.DESCRIPTION') }}
            </p>
          </div>
          <NextButton
            icon="i-lucide-x"
            slate
            ghost
            sm
            class="self-start"
            @click="handleClickOutside"
          />
        </div>

        <div v-if="!internalInboxes.length" class="p-3 bg-n-alpha-2 rounded-lg">
          <p class="m-0 text-sm text-n-slate-11">
            {{ $t('CONVERSATION.INTERNAL_CHAT.NO_INBOX') }}
          </p>
        </div>

        <div v-else class="grid gap-3">
          <div class="grid gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.INTERNAL_CHAT.INBOX_LABEL') }}
            </label>
            <select
              v-model.number="selectedInboxId"
              class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option :value="null" disabled>
                {{ $t('CONVERSATION.INTERNAL_CHAT.INBOX_PLACEHOLDER') }}
              </option>
              <option
                v-for="inbox in internalInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
          </div>

          <div class="grid gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.INTERNAL_CHAT.TITLE_LABEL') }}
              <span class="text-n-slate-9">
                ({{ $t('CONVERSATION.INTERNAL_CHAT.OPTIONAL') }})
              </span>
            </label>
            <input
              v-model="title"
              type="text"
              class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="$t('CONVERSATION.INTERNAL_CHAT.TITLE_PLACEHOLDER')"
            />
          </div>

          <div class="grid gap-2">
            <div class="flex items-center justify-between">
              <label class="text-sm font-medium text-n-slate-12">
                {{ $t('CONVERSATION.INTERNAL_CHAT.PARTICIPANTS_LABEL') }}
              </label>
              <NextButton
                v-if="!showParticipantsDropdown"
                ghost
                slate
                xs
                icon="i-lucide-plus"
                @click="showParticipantsDropdown = true"
              />
              <NextButton
                v-else
                ghost
                slate
                xs
                icon="i-lucide-x"
                @click="showParticipantsDropdown = false"
              />
            </div>
            <div class="flex flex-wrap gap-2">
              <div
                v-for="participant in selectedParticipants"
                :key="participant.id"
                class="inline-flex items-center gap-2 px-2 py-1 rounded-full bg-n-alpha-2 text-sm text-n-slate-12"
              >
                <Avatar
                  :src="participant.avatar_url"
                  :name="participant.name"
                  :size="22"
                  hide-offline-status
                  rounded-full
                />
                <span class="max-w-[10rem] truncate">{{ participant.name }}</span>
                <button
                  type="button"
                  class="text-n-slate-10 hover:text-n-slate-12"
                  @click="onSelectParticipant(participant)"
                >
                  ✕
                </button>
              </div>
              <p
                v-if="!selectedParticipants.length"
                class="m-0 text-sm text-n-slate-10"
              >
                {{ $t('CONVERSATION.INTERNAL_CHAT.NO_PARTICIPANT_SELECTED') }}
              </p>
            </div>
            <div
              v-if="showParticipantsDropdown"
              class="relative border border-n-strong rounded-lg"
            >
              <div class="p-2 flex justify-between items-center">
                <p class="m-0 text-sm font-medium text-n-slate-12">
                  {{ $t('CONVERSATION.INTERNAL_CHAT.ADD_PARTICIPANTS') }}
                </p>
                <NextButton
                  ghost
                  xs
                  icon="i-lucide-user-plus"
                  @click="onSelfAdd(currentUser)"
                >
                  {{ $t('CONVERSATION.INTERNAL_CHAT.ADD_ME') }}
                </NextButton>
              </div>
              <MultiselectDropdownItems
                :options="agents"
                :selected-items="selectedParticipants"
                :input-placeholder="
                  $t('CONVERSATION.INTERNAL_CHAT.SEARCH_PARTICIPANTS')
                "
                @select="onSelectParticipant"
              />
            </div>
          </div>

          <div class="grid gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.INTERNAL_CHAT.MESSAGE_LABEL') }}
            </label>
            <textarea
              v-model="message"
              rows="3"
              class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
              :placeholder="$t('CONVERSATION.INTERNAL_CHAT.MESSAGE_PLACEHOLDER')"
            />
          </div>

          <div class="flex justify-end gap-2">
            <NextButton slate ghost sm @click="handleClickOutside">
              {{ $t('CONVERSATION.INTERNAL_CHAT.CANCEL') }}
            </NextButton>
            <NextButton
              blue
              solid
              sm
              :is-loading="isSubmitting"
              :disabled="!canSubmit"
              @click="createInternalConversation"
            >
              {{ $t('CONVERSATION.INTERNAL_CHAT.SUBMIT') }}
            </NextButton>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

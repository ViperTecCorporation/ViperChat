<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import conversationApi from 'dashboard/api/inbox/conversation';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import Avatar from 'next/avatar/Avatar.vue';
import GroupMembersModal from './GroupMembersModal.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const groupContacts = ref([]);
const groupInfo = ref({});
const inviteLink = ref('');
const groupTitle = ref('');
const groupDescription = ref('');
const groupPictureUrl = ref('');
const joinRequests = ref([]);
const currentPage = ref(1);
const totalCount = ref(0);
const isLoading = ref(false);
const isSyncing = ref(false);
const isLoadingInviteLink = ref(false);
const isUpdatingGroup = ref(false);
const isUploadingPicture = ref(false);
const isLoadingJoinRequests = ref(false);
const showMembersModal = ref(false);

const isSessionAdmin = computed(() => groupInfo.value.group_session_admin);
const groupDisplayTitle = computed(
  () => groupTitle.value || groupInfo.value.group_title || 'Group Chat'
);
const groupMemberCount = computed(
  () => groupInfo.value.group_contacts_count || totalCount.value
);
const visibleGroupContacts = computed(() => groupContacts.value.slice(0, 3));

const memberName = groupContact =>
  groupContact.contact?.name ||
  groupContact.participant_identifier ||
  groupContact.metadata?.jid ||
  groupContact.metadata?.lid ||
  groupContact.metadata?.wa_id;

const memberSubtitle = groupContact =>
  [
    groupContact.metadata?.role,
    groupContact.contact?.whatsapp_username,
    groupContact.contact?.bsuid,
    groupContact.contact?.phone_number,
    groupContact.participant_identifier,
  ]
    .filter(Boolean)
    .join(' · ');

const fetchGroupInfo = async () => {
  const { data } = await conversationApi.fetchGroup(props.conversationId);
  groupInfo.value = data || {};
  inviteLink.value = data?.group_invite_link || '';
  groupTitle.value = data?.group_title || '';
  groupDescription.value = data?.group_description || '';
  groupPictureUrl.value =
    data?.group_picture || data?.additional_attributes?.group_picture || '';
};

const fetchGroupContacts = async ({ reset = false } = {}) => {
  if (isLoading.value) return;

  isLoading.value = true;
  const page = reset ? 1 : currentPage.value;
  try {
    const { data } = await conversationApi.fetchGroupContacts(
      props.conversationId,
      page
    );
    groupContacts.value = reset
      ? data.payload || []
      : [...groupContacts.value, ...(data.payload || [])];
    totalCount.value = data.meta?.count || 0;
    currentPage.value = page + 1;
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => props.conversationId,
  () => {
    fetchGroupInfo();
    fetchGroupContacts({ reset: true });
  }
);

onMounted(() => {
  fetchGroupInfo();
  fetchGroupContacts({ reset: true });
});

const syncGroupContacts = async () => {
  if (isSyncing.value) return;

  isSyncing.value = true;
  try {
    const { data } = await conversationApi.syncGroup(props.conversationId);
    groupInfo.value = data || {};
    groupTitle.value = data?.group_title || '';
    groupDescription.value = data?.group_description || '';
    groupPictureUrl.value =
      data?.group_picture || data?.additional_attributes?.group_picture || '';
    await fetchGroupContacts({ reset: true });
  } finally {
    isSyncing.value = false;
  }
};

const fetchInviteLink = async () => {
  if (isLoadingInviteLink.value) return;

  isLoadingInviteLink.value = true;
  try {
    const { data } = await conversationApi.fetchGroupInviteLink(
      props.conversationId
    );
    inviteLink.value = data.invite_link || '';
  } finally {
    isLoadingInviteLink.value = false;
  }
};

const resetInviteLink = async () => {
  if (isLoadingInviteLink.value) return;

  isLoadingInviteLink.value = true;
  try {
    const { data } = await conversationApi.resetGroupInviteLink(
      props.conversationId
    );
    inviteLink.value = data.invite_link || '';
  } finally {
    isLoadingInviteLink.value = false;
  }
};

const fetchJoinRequests = async () => {
  if (isLoadingJoinRequests.value) return;

  isLoadingJoinRequests.value = true;
  try {
    const { data } = await conversationApi.fetchGroupJoinRequests(
      props.conversationId
    );
    joinRequests.value = data.join_requests || [];
  } finally {
    isLoadingJoinRequests.value = false;
  }
};

const joinRequestIdentifier = request => request.wa_id || request.user_id;

const joinRequestName = request =>
  request.name || request.username || request.wa_id || request.user_id;

const joinRequestSubtitle = request =>
  [request.username, request.wa_id, request.user_id]
    .filter(Boolean)
    .join(' · ');

const approveJoinRequest = async request => {
  const participant = joinRequestIdentifier(request);
  if (!participant) return;

  await conversationApi.approveGroupJoinRequests({
    conversationId: props.conversationId,
    participants: [participant],
  });
  await fetchJoinRequests();
};

const rejectJoinRequest = async request => {
  const participant = joinRequestIdentifier(request);
  if (!participant) return;

  await conversationApi.rejectGroupJoinRequests({
    conversationId: props.conversationId,
    participants: [participant],
  });
  await fetchJoinRequests();
};

const removeGroupContact = async groupContact => {
  if (!groupContact.participant_identifier) return;

  await conversationApi.removeGroupContacts({
    conversationId: props.conversationId,
    participants: [groupContact.participant_identifier],
  });
  await fetchGroupContacts({ reset: true });
};

const uploadGroupPicture = async event => {
  const [file] = event.target.files || [];
  if (!file) return;

  isUploadingPicture.value = true;
  try {
    const { fileUrl } = await uploadFile(file);
    groupPictureUrl.value = fileUrl;
  } finally {
    isUploadingPicture.value = false;
    event.target.value = '';
  }
};

const updateGroupInfo = async () => {
  if (isUpdatingGroup.value || isUploadingPicture.value) return;

  isUpdatingGroup.value = true;
  try {
    const { data } = await conversationApi.updateGroup({
      conversationId: props.conversationId,
      subject: groupTitle.value,
      description: groupDescription.value,
      picture_url: groupPictureUrl.value,
    });
    groupInfo.value = data || {};
    groupTitle.value = data?.group_title || '';
    groupDescription.value = data?.group_description || '';
    groupPictureUrl.value =
      data?.group_picture || data?.additional_attributes?.group_picture || '';
  } finally {
    isUpdatingGroup.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 p-4 border-b border-n-weak">
    <div class="flex flex-col items-start gap-3">
      <Avatar
        :name="groupDisplayTitle"
        :src="groupPictureUrl"
        :size="48"
        hide-offline-status
      />
      <div class="min-w-0">
        <h3 class="m-0 text-base font-medium break-words text-n-slate-12">
          {{ groupDisplayTitle }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">
          {{ groupMemberCount }} {{ $t('CONVERSATION.GROUP.MEMBERS') }}
        </p>
      </div>
    </div>

    <div class="flex items-center justify-between gap-2">
      <h4 class="m-0 text-xs font-semibold uppercase text-n-slate-10">
        {{ $t('CONVERSATION.GROUP.MEMBERS_TITLE') }}
      </h4>
      <button
        type="button"
        class="inline-flex items-center gap-1 text-xs font-medium text-n-blue-11 hover:underline disabled:opacity-50"
        :disabled="isSyncing"
        @click="syncGroupContacts"
      >
        <span class="i-lucide-refresh-cw size-3" />
        {{
          isSyncing
            ? $t('CONVERSATION.GROUP.SYNCING')
            : $t('CONVERSATION.GROUP.SYNC')
        }}
      </button>
    </div>

    <div class="flex flex-col gap-2">
      <div
        v-for="groupContact in visibleGroupContacts"
        :key="groupContact.id"
        class="flex items-center gap-3 rounded-md border border-n-weak bg-n-alpha-1 p-2"
      >
        <div class="flex min-w-0 flex-1 items-center gap-3">
          <Avatar
            :name="memberName(groupContact)"
            :src="groupContact.contact?.thumbnail"
            :size="32"
            hide-offline-status
          />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-n-slate-12">
              {{ memberName(groupContact) }}
            </span>
            <span
              v-if="memberSubtitle(groupContact)"
              class="block truncate text-xs text-n-slate-10"
            >
              {{ memberSubtitle(groupContact) }}
            </span>
          </span>
        </div>
        <button
          v-if="isSessionAdmin"
          type="button"
          class="inline-flex size-7 items-center justify-center rounded-md text-n-ruby-9 hover:bg-n-ruby-9/10"
          :aria-label="$t('CONVERSATION.GROUP.REMOVE_MEMBER')"
          @click.stop="removeGroupContact(groupContact)"
        >
          <span class="i-lucide-trash-2 size-3.5" />
        </button>
      </div>
    </div>

    <button
      v-if="groupMemberCount"
      type="button"
      class="text-sm font-medium text-n-blue-11 text-left hover:underline"
      @click="showMembersModal = true"
    >
      {{
        $t('CONVERSATION.GROUP.VIEW_ALL_MEMBERS', {
          count: groupMemberCount,
        })
      }}
    </button>

    <div
      v-if="isSessionAdmin"
      class="flex flex-col gap-3 border-t border-n-weak pt-3"
    >
      <form class="flex flex-col gap-2" @submit.prevent="updateGroupInfo">
        <input
          v-model.trim="groupTitle"
          type="text"
          class="w-full rounded-md border border-n-weak bg-n-background px-2 py-1.5 text-sm text-n-slate-12"
          :placeholder="$t('CONVERSATION.GROUP.TITLE')"
        />
        <textarea
          v-model.trim="groupDescription"
          rows="2"
          class="w-full rounded-md border border-n-weak bg-n-background px-2 py-1.5 text-sm text-n-slate-12"
          :placeholder="$t('CONVERSATION.GROUP.DESCRIPTION')"
        />
        <div class="flex items-center justify-between gap-2">
          <label
            class="inline-flex cursor-pointer items-center gap-1 text-xs font-medium text-n-blue-11 hover:underline"
          >
            <span class="i-lucide-image-plus size-3.5" />
            {{
              isUploadingPicture
                ? $t('CONVERSATION.GROUP.UPLOADING_PICTURE')
                : $t('CONVERSATION.GROUP.UPLOAD_PICTURE')
            }}
            <input
              type="file"
              accept="image/*"
              class="hidden"
              :disabled="isUploadingPicture"
              @change="uploadGroupPicture"
            />
          </label>
          <button
            type="submit"
            class="text-xs font-medium text-n-blue-11 hover:underline disabled:opacity-50"
            :disabled="isUpdatingGroup || isUploadingPicture"
          >
            {{
              isUpdatingGroup
                ? $t('CONVERSATION.GROUP.SAVING')
                : $t('CONVERSATION.GROUP.SAVE')
            }}
          </button>
        </div>
      </form>

      <div class="flex flex-wrap gap-3">
        <button
          type="button"
          class="text-xs font-medium text-n-blue-11 hover:underline disabled:opacity-50"
          :disabled="isLoadingInviteLink"
          @click="fetchInviteLink"
        >
          {{ $t('CONVERSATION.GROUP.INVITE_LINK') }}
        </button>
        <button
          type="button"
          class="text-xs font-medium text-n-blue-11 hover:underline disabled:opacity-50"
          :disabled="isLoadingInviteLink"
          @click="resetInviteLink"
        >
          {{ $t('CONVERSATION.GROUP.RESET_INVITE_LINK') }}
        </button>
        <button
          type="button"
          class="text-xs font-medium text-n-blue-11 hover:underline disabled:opacity-50"
          :disabled="isLoadingJoinRequests"
          @click="fetchJoinRequests"
        >
          {{ $t('CONVERSATION.GROUP.JOIN_REQUESTS') }}
        </button>
      </div>

      <div v-if="inviteLink" class="break-all text-xs text-n-slate-10">
        {{ inviteLink }}
      </div>

      <div
        v-for="request in joinRequests"
        :key="joinRequestIdentifier(request)"
        class="flex items-center gap-2"
      >
        <div class="min-w-0">
          <div class="truncate text-sm text-n-slate-12">
            {{ joinRequestName(request) }}
          </div>
          <div class="truncate text-xs text-n-slate-10">
            {{ joinRequestSubtitle(request) }}
          </div>
        </div>
        <button
          type="button"
          class="ml-auto text-xs font-medium text-n-blue-11 hover:underline"
          @click="approveJoinRequest(request)"
        >
          {{ $t('CONVERSATION.GROUP.APPROVE_JOIN_REQUEST') }}
        </button>
        <button
          type="button"
          class="text-xs font-medium text-n-ruby-9 hover:underline"
          @click="rejectJoinRequest(request)"
        >
          {{ $t('CONVERSATION.GROUP.REJECT_JOIN_REQUEST') }}
        </button>
      </div>
    </div>

    <GroupMembersModal
      v-model:show="showMembersModal"
      :conversation-id="conversationId"
      :total-count="groupMemberCount"
      :is-session-admin="isSessionAdmin"
      @member-removed="fetchGroupContacts({ reset: true })"
    />
  </div>
</template>

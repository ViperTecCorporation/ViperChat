<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import conversationApi from 'dashboard/api/inbox/conversation';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import Avatar from 'next/avatar/Avatar.vue';

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

const hasMore = computed(() => groupContacts.value.length < totalCount.value);
const isSessionAdmin = computed(() => groupInfo.value.group_session_admin);

const fetchGroupInfo = async () => {
  const { data } = await conversationApi.fetchGroup(props.conversationId);
  groupInfo.value = data || {};
  inviteLink.value = data?.group_invite_link || '';
  groupTitle.value = data?.group_title || '';
  groupDescription.value = data?.group_description || '';
  groupPictureUrl.value = data?.additional_attributes?.group_picture || '';
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
    groupPictureUrl.value = data?.additional_attributes?.group_picture || '';
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
    groupPictureUrl.value = data?.additional_attributes?.group_picture || '';
  } finally {
    isUpdatingGroup.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <button
      type="button"
      class="text-sm text-n-brand text-left"
      :disabled="isSyncing"
      @click="syncGroupContacts"
    >
      {{
        isSyncing
          ? $t('CONVERSATION.GROUP.SYNCING')
          : $t('CONVERSATION.GROUP.SYNC')
      }}
    </button>
    <div v-if="isSessionAdmin" class="flex flex-col gap-1">
      <form class="flex flex-col gap-2" @submit.prevent="updateGroupInfo">
        <input
          v-model.trim="groupTitle"
          type="text"
          class="w-full text-sm rounded border border-n-weak bg-n-background px-2 py-1"
          :placeholder="$t('CONVERSATION.GROUP.TITLE')"
        />
        <textarea
          v-model.trim="groupDescription"
          rows="2"
          class="w-full text-sm rounded border border-n-weak bg-n-background px-2 py-1"
          :placeholder="$t('CONVERSATION.GROUP.DESCRIPTION')"
        />
        <div class="flex items-center gap-2 min-w-0">
          <Avatar
            :name="groupTitle"
            :src="groupPictureUrl"
            :size="32"
            hide-offline-status
          />
          <label class="text-sm text-n-brand cursor-pointer">
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
        </div>
        <button
          type="submit"
          class="text-sm text-n-brand text-left"
          :disabled="isUpdatingGroup || isUploadingPicture"
        >
          {{
            isUpdatingGroup
              ? $t('CONVERSATION.GROUP.SAVING')
              : $t('CONVERSATION.GROUP.SAVE')
          }}
        </button>
      </form>
      <div class="flex gap-2">
        <button
          type="button"
          class="text-sm text-n-brand text-left"
          :disabled="isLoadingInviteLink"
          @click="fetchInviteLink"
        >
          {{ $t('CONVERSATION.GROUP.INVITE_LINK') }}
        </button>
        <button
          type="button"
          class="text-sm text-n-brand text-left"
          :disabled="isLoadingInviteLink"
          @click="resetInviteLink"
        >
          {{ $t('CONVERSATION.GROUP.RESET_INVITE_LINK') }}
        </button>
      </div>
      <div v-if="inviteLink" class="text-xs text-n-slate-10 break-all">
        {{ inviteLink }}
      </div>
      <div class="flex flex-col gap-2">
        <button
          type="button"
          class="text-sm text-n-brand text-left"
          :disabled="isLoadingJoinRequests"
          @click="fetchJoinRequests"
        >
          {{ $t('CONVERSATION.GROUP.JOIN_REQUESTS') }}
        </button>
        <div
          v-for="request in joinRequests"
          :key="joinRequestIdentifier(request)"
          class="flex items-center gap-2 min-w-0"
        >
          <div class="min-w-0">
            <div class="text-sm text-n-slate-12 truncate">
              {{ joinRequestName(request) }}
            </div>
            <div class="text-xs text-n-slate-10 truncate">
              {{ joinRequestSubtitle(request) }}
            </div>
          </div>
          <button
            type="button"
            class="ml-auto text-xs text-n-brand"
            @click="approveJoinRequest(request)"
          >
            {{ $t('CONVERSATION.GROUP.APPROVE_JOIN_REQUEST') }}
          </button>
          <button
            type="button"
            class="text-xs text-n-ruby-9"
            @click="rejectJoinRequest(request)"
          >
            {{ $t('CONVERSATION.GROUP.REJECT_JOIN_REQUEST') }}
          </button>
        </div>
      </div>
    </div>
    <div
      v-for="groupContact in groupContacts"
      :key="groupContact.id"
      class="flex items-center gap-2 min-w-0"
    >
      <Avatar
        :name="groupContact.contact.name"
        :src="groupContact.contact.thumbnail"
        :size="24"
        hide-offline-status
      />
      <div class="min-w-0">
        <div class="text-sm text-n-slate-12 truncate">
          {{ groupContact.contact.name }}
        </div>
        <div
          v-if="groupContact.metadata.role"
          class="text-xs text-n-slate-10 truncate"
        >
          {{ groupContact.metadata.role }}
        </div>
      </div>
      <button
        v-if="isSessionAdmin"
        type="button"
        class="ml-auto text-xs text-n-ruby-9"
        @click="removeGroupContact(groupContact)"
      >
        {{ $t('CONVERSATION.GROUP.REMOVE_MEMBER') }}
      </button>
    </div>
    <button
      v-if="hasMore"
      type="button"
      class="text-sm text-n-brand text-left"
      :disabled="isLoading"
      @click="fetchGroupContacts()"
    >
      {{ $t('CONVERSATION.GROUP.LOAD_MORE') }}
    </button>
  </div>
</template>

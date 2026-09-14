<script setup>
import { computed, ref, watch, inject, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useConversationPins } from 'dashboard/composables/useConversationPins';
import { useConversationArchives } from 'dashboard/composables/useConversationArchives';
import { canArchiveConversation } from 'dashboard/helper/conversationArchives';
import { shouldShowConversationAssignee } from 'dashboard/helper/conversationPins';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import ConversationCard from './widgets/conversation/ConversationCard.vue';
import ConversationCardExpanded from 'dashboard/components-next/Conversation/ConversationCard/ConversationCardExpanded.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import ConversationContextMenu from './widgets/conversation/contextMenu/Index.vue';

const props = defineProps({
  source: { type: Object, required: true },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showAssignee: { type: Boolean, default: false },
  showExpanded: { type: Boolean, default: false },
});

const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { isPinned, setPinned } = useConversationPins();
const { setArchived } = useConversationArchives();
const activeTab = inject('activeAssigneeTab', ref(''));
const archiveBusy = ref(false);
const canArchive = computed(() =>
  canArchiveConversation(
    props.source,
    store.getters.getCurrentUser?.id,
    activeTab.value
  )
);
const pinBusy = ref(false);
const pinned = computed(() => isPinned(props.source.id));
const showCardAssignee = computed(() =>
  shouldShowConversationAssignee(props.showAssignee, props.source)
);

const selectConversation = inject('selectConversation');
const deSelectConversation = inject('deSelectConversation');
const assignAgent = inject('assignAgent');
const assignTeam = inject('assignTeam');
const assignLabels = inject('assignLabels');
const removeLabels = inject('removeLabels');
const updateConversationStatus = inject('updateConversationStatus');
const toggleContextMenu = inject('toggleContextMenu');
const markAsUnread = inject('markAsUnread');
const markAsRead = inject('markAsRead');
const assignPriority = inject('assignPriority');
const isConversationSelected = inject('isConversationSelected');
const deleteConversation = inject('deleteConversation');

// --- Context menu state (shared by both layouts) ---
const showContextMenu = ref(false);
let suppressTouchClick = false;
const contextMenu = ref({ x: null, y: null });

// Reset context menu state when the row is recycled to a different conversation.
watch(
  () => props.source.id,
  () => {
    if (showContextMenu.value) {
      toggleContextMenu(false);
    }
    showContextMenu.value = false;
    contextMenu.value = { x: null, y: null };
  }
);

const currentChat = useMapGetter('getSelectedChat');
const inboxesList = useMapGetter('inboxes/getInboxes');
const activeInbox = useMapGetter('getSelectedInbox');
const accountId = useMapGetter('getCurrentAccountId');

const chatMetadata = computed(() => props.source.meta || {});
const assignee = computed(() => chatMetadata.value.assignee || {});
const senderId = computed(() => chatMetadata.value.sender?.id);

const currentContact = computed(() => {
  const contact = senderId.value
    ? store.getters['contacts/getContact'](senderId.value)
    : {};
  if (!props.source.group) return contact;

  return {
    ...contact,
    name: props.source.group_title || contact.name,
    thumbnail:
      props.source.group_picture ||
      props.source.additional_attributes?.group_picture ||
      '',
  };
});

const isActiveChat = computed(() => currentChat.value.id === props.source.id);

const inbox = computed(() => {
  const inboxId = props.source.inbox_id;
  return inboxId ? store.getters['inboxes/getInbox'](inboxId) : {};
});

const showInboxName = computed(
  () => !activeInbox.value && inboxesList.value.length > 1
);
const isInboxView = computed(() => !!activeInbox.value);
const showAssigneeForExpandedCard = computed(
  () => props.showExpanded || props.showAssignee
);

const conversationPath = computed(() =>
  frontendURL(
    conversationUrl({
      accountId: accountId.value,
      activeInbox: activeInbox.value,
      id: props.source.id,
      label: props.label,
      teamId: props.teamId,
      conversationType: props.conversationType,
      foldersId: props.foldersId,
    })
  )
);

const onCardClick = e => {
  if (showContextMenu.value || suppressTouchClick) return;
  const path = conversationPath.value;
  if (!path) return;

  if (e.metaKey || e.ctrlKey) {
    e.preventDefault();
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }

  if (isActiveChat.value) return;
  router.push({ path });
};

const onExpandedSelect = checked => {
  if (checked) {
    selectConversation(props.source.id, inbox.value.id);
  } else {
    deSelectConversation(props.source.id, inbox.value.id);
  }
};

const openContextMenu = e => {
  e.preventDefault();
  toggleContextMenu(true);
  contextMenu.value.x = e.pageX || e.clientX;
  contextMenu.value.y = e.pageY || e.clientY;
  showContextMenu.value = true;
};

const closeContextMenu = () => {
  toggleContextMenu(false);
  showContextMenu.value = false;
  contextMenu.value.x = null;
  contextMenu.value.y = null;
};

let touchTimer;
let touchOrigin;
const cancelTouch = () => {
  clearTimeout(touchTimer);
  touchOrigin = null;
};
const startTouch = event => {
  cancelTouch();
  suppressTouchClick = false;
  if (event.touches.length !== 1) return;
  const touch = event.touches[0];
  touchOrigin = { x: touch.clientX, y: touch.clientY };
  touchTimer = setTimeout(() => {
    suppressTouchClick = true;
    openContextMenu({
      preventDefault() {},
      pageX: touch.pageX,
      pageY: touch.pageY,
    });
  }, 550);
};
const moveTouch = event => {
  const touch = event.touches[0];
  if (
    touchOrigin &&
    (!touch ||
      Math.hypot(touch.clientX - touchOrigin.x, touch.clientY - touchOrigin.y) >
        10)
  )
    cancelTouch();
};
onBeforeUnmount(cancelTouch);
watch(() => props.source.id, cancelTouch);

const onTogglePin = async () => {
  if (pinBusy.value) return;
  pinBusy.value = true;
  try {
    await setPinned(props.source.id, !pinned.value);
    closeContextMenu();
  } catch (error) {
    useAlert(
      t(
        error.response?.data?.error === 'pin_limit_reached'
          ? 'CONVERSATION.PIN.LIMIT'
          : 'CONVERSATION.PIN.ERROR'
      )
    );
  } finally {
    pinBusy.value = false;
  }
};

const onArchive = async () => {
  if (!canArchive.value || archiveBusy.value) return;
  archiveBusy.value = true;
  try {
    await setArchived(props.source.id, true);
    closeContextMenu();
  } catch {
    useAlert(t('CONVERSATION.ARCHIVE.ERROR'));
  } finally {
    archiveBusy.value = false;
  }
};

const onUpdateConversation = (status, snoozedUntil) => {
  closeContextMenu();
  updateConversationStatus(props.source.id, status, snoozedUntil);
};

const onAssignAgent = agent => {
  assignAgent(agent, [props.source.id]);
  closeContextMenu();
};

const onAssignLabel = label => {
  assignLabels([label.title], [props.source.id]);
};

const onRemoveLabel = label => {
  removeLabels([label.title], [props.source.id]);
};

const onAssignTeam = team => {
  assignTeam(team, props.source.id);
  closeContextMenu();
};

const onMarkAsUnread = () => {
  markAsUnread(props.source.id);
  closeContextMenu();
};

const onMarkAsRead = () => {
  markAsRead(props.source.id);
  closeContextMenu();
};

const onAssignPriority = priority => {
  assignPriority(priority, props.source.id);
  closeContextMenu();
};

const onDeleteConversation = () => {
  deleteConversation(props.source.id);
  closeContextMenu();
};
</script>

<template>
  <!-- Expanded layout: wide screen + expanded setting -->
  <ConversationCardExpanded
    v-if="showExpanded"
    :chat="source"
    :current-contact="currentContact"
    :assignee="assignee"
    :inbox="inbox"
    :selected="isConversationSelected(source.id)"
    :is-active-chat="isActiveChat"
    :show-assignee="showAssigneeForExpandedCard"
    :is-pinned="pinned"
    :show-inbox-name="showInboxName"
    :is-inbox-view="isInboxView"
    @select-conversation="onExpandedSelect"
    @de-select-conversation="onExpandedSelect"
    @click="onCardClick"
    @contextmenu="openContextMenu"
    @touchstart.passive="startTouch"
    @touchmove.passive="moveTouch"
    @touchend.passive="cancelTouch"
    @touchcancel.passive="cancelTouch"
  />

  <!-- Default (condensed) layout -->
  <ConversationCard
    v-else
    :chat="source"
    :current-contact="currentContact"
    :assignee="assignee"
    :inbox="inbox"
    :selected="isConversationSelected(source.id)"
    :is-active-chat="isActiveChat"
    :show-assignee="showCardAssignee"
    :is-pinned="pinned"
    :show-inbox-name="showInboxName"
    @click="onCardClick"
    @contextmenu="openContextMenu"
    @touchstart.passive="startTouch"
    @touchmove.passive="moveTouch"
    @touchend.passive="cancelTouch"
    @touchcancel.passive="cancelTouch"
    @select-conversation="selectConversation"
    @de-select-conversation="deSelectConversation"
  />

  <!-- Shared context menu for both layouts -->
  <ContextMenu
    v-if="showContextMenu"
    :x="contextMenu.x"
    :y="contextMenu.y"
    @close="closeContextMenu"
  >
    <ConversationContextMenu
      :status="source.status"
      :is-pinned="pinned"
      :pin-busy="pinBusy"
      :can-archive="canArchive"
      :archive-busy="archiveBusy"
      :inbox-id="inbox.id"
      :priority="source.priority"
      :chat-id="source.id"
      :has-unread-messages="source.unread_count > 0"
      :conversation-labels="source.labels"
      :conversation-url="conversationPath"
      @archive="onArchive"
      @toggle-pin="onTogglePin"
      @update-conversation="onUpdateConversation"
      @assign-agent="onAssignAgent"
      @assign-label="onAssignLabel"
      @remove-label="onRemoveLabel"
      @assign-team="onAssignTeam"
      @mark-as-unread="onMarkAsUnread"
      @mark-as-read="onMarkAsRead"
      @assign-priority="onAssignPriority"
      @delete-conversation="onDeleteConversation"
      @close="closeContextMenu"
    />
  </ContextMenu>
</template>

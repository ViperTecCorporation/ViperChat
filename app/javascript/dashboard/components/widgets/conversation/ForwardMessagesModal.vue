<script setup>
import { ref, computed, watch } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactSelector from 'dashboard/components-next/NewConversation/components/ContactSelector.vue';
import InboxSelector from 'dashboard/components-next/NewConversation/components/InboxSelector.vue';
import WhatsappTransportSelector from 'dashboard/components-next/NewConversation/components/WhatsappTransportSelector.vue';
import {
  getWhatsappInboxLink,
  getWhatsappTransport,
  getWhatsappRouting,
} from 'dashboard/components-next/NewConversation/helpers/whatsappUnifiedInbox';
import {
  searchContacts,
  createNewContact,
  fetchContactableInboxes,
  mergeInboxDetails,
  buildContactableInboxesList,
  getContactInboxes,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper.js';
import ConversationApi from 'dashboard/api/conversations';
import SearchAPI from 'dashboard/api/search';

const props = defineProps({
  selectedMessages: {
    type: Array,
    default: () => [],
  },
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['forwarded', 'close']);

const show = defineModel('show', { type: Boolean, default: false });

const { t } = useI18n();

const currentUser = useMapGetter('getCurrentUser');
const inboxesList = useMapGetter('inboxes/getInboxes');

const contacts = ref([]);
const selectedContact = ref(null);
const targetInbox = ref(null);
const isCreatingContact = ref(false);
const isFetchingInboxes = ref(false);
const isSearching = ref(false);
const showContactsDropdown = ref(false);
const showInboxesDropdown = ref(false);
const isForwarding = ref(false);
const whatsappTransport = ref('');
const whatsappLink = computed(() =>
  getWhatsappInboxLink(targetInbox.value, selectedContact.value)
);
watch(
  () => [
    whatsappLink.value?.linkId,
    targetInbox.value?.id,
    selectedContact.value,
  ],
  () => {
    whatsappTransport.value = whatsappLink.value?.defaultProvider || '';
  },
  { immediate: true }
);

const contactableInboxesList = computed(() => {
  return buildContactableInboxesList(
    getContactInboxes(selectedContact.value, inboxesList.value),
    selectedContact.value
  );
});

const forwardMessagePreview = computed(() => {
  if (!props.selectedMessages || !props.selectedMessages.length) {
    return '';
  }

  const lines = props.selectedMessages
    .map(message => {
      const senderName = message.sender?.name || '';
      const content = message.content || '';
      if (!content) return '';
      if (senderName) {
        return `${senderName}: ${content}`;
      }
      return content;
    })
    .filter(Boolean);

  return lines.join('\n');
});

const hasForwardableContent = computed(() => {
  if (!props.selectedMessages || !props.selectedMessages.length) {
    return false;
  }

  const hasText = forwardMessagePreview.value.trim().length > 0;
  const hasAttachments = props.selectedMessages.some(message => {
    return Array.isArray(message.attachments) && message.attachments.length > 0;
  });

  return hasText || hasAttachments;
});

const resetState = () => {
  contacts.value = [];
  selectedContact.value = null;
  targetInbox.value = null;
  isCreatingContact.value = false;
  isFetchingInboxes.value = false;
  isSearching.value = false;
  showContactsDropdown.value = false;
  showInboxesDropdown.value = false;
};

const close = () => {
  resetState();
  emit('close');
};

const handleClose = () => {
  show.value = false;
  close();
};

const handleContactSearch = async value => {
  const query = typeof value === 'string' ? value.trim() : '';
  if (!query) {
    contacts.value = [];
    return;
  }

  isSearching.value = true;
  showContactsDropdown.value = true;
  contacts.value = [];
  try {
    const [contactResults, conversationResponse] = await Promise.all([
      searchContacts({ query }),
      SearchAPI.conversations({ q: query }),
    ]);
    const conversationResults = camelcaseKeys(
      conversationResponse?.data?.payload?.conversations || [],
      { deep: true }
    );
    const groupResults = conversationResults
      .filter(
        conversation =>
          conversation.group &&
          String(conversation.id) !== String(props.conversationId)
      )
      .map(conversation => {
        const groupSourceId = conversation.groupSourceId || '';
        const groupTitle =
          conversation.groupTitle ||
          conversation.contact?.name ||
          groupSourceId;
        const inbox = mergeInboxDetails(
          [conversation.inbox || { id: conversation.inboxId }],
          inboxesList.value
        )[0];

        return {
          ...conversation.contact,
          id: conversation.contact?.id,
          name: groupTitle,
          email: groupSourceId || conversation.contact?.email,
          targetConversationId: conversation.id,
          groupSourceId,
          groupTitle,
          contactInboxes: [
            {
              ...inbox,
              phoneNumber: groupSourceId,
              sourceId: groupSourceId,
            },
          ],
        };
      });
    const groupContactIds = new Set(groupResults.map(group => group.id));

    contacts.value = [
      ...groupResults,
      ...contactResults.filter(contact => !groupContactIds.has(contact.id)),
    ];
  } catch (error) {
    useAlert(t('COMPOSE_NEW_CONVERSATION.CONTACT_SEARCH.ERROR_MESSAGE'));
  } finally {
    isSearching.value = false;
  }
};

const handleSelectedContact = async ({ value, action, ...rest }) => {
  targetInbox.value = null;
  let contact;
  if (action === 'direct') {
    contact = {
      recipient: rest.recipient,
      name: Object.values(rest.recipient)[0],
    };
  } else if (action === 'create') {
    isCreatingContact.value = true;
    try {
      contact = await createNewContact(value);
    } catch (error) {
      isCreatingContact.value = false;
      return;
    }
    isCreatingContact.value = false;
  } else {
    contact = camelcaseKeys(rest, { deep: true });
  }

  contact = {
    ...contact,
    phoneNumber: contact.phoneNumber || contact.bsuid,
  };

  selectedContact.value = contact;

  if (contact.targetConversationId) {
    targetInbox.value =
      buildContactableInboxesList(contact.contactInboxes, contact)[0] || null;
    return;
  }

  if (contact?.id) {
    isFetchingInboxes.value = true;
    try {
      const contactableInboxes = await fetchContactableInboxes(contact.id);
      selectedContact.value.contactInboxes = mergeInboxDetails(
        contactableInboxes,
        inboxesList.value
      );
    } catch (error) {
      // ignore
    } finally {
      isFetchingInboxes.value = false;
    }
  }
};

const handleTargetInbox = inbox => {
  targetInbox.value = inbox;
};

const clearSelectedContact = () => {
  selectedContact.value = null;
  targetInbox.value = null;
  contacts.value = [];
};

const canSubmit = computed(() => {
  return (
    !!selectedContact.value &&
    !!targetInbox.value &&
    hasForwardableContent.value &&
    !isFetchingInboxes.value &&
    !isForwarding.value &&
    (!whatsappLink.value ||
      !!getWhatsappTransport(
        targetInbox.value,
        whatsappTransport.value,
        selectedContact.value
      ))
  );
});

const handleContactDropdownUpdate = type => {
  if (type === 'contacts') {
    showContactsDropdown.value = false;
  }
};

const handleInboxDropdownToggle = value => {
  showInboxesDropdown.value = value;
};

const handleForward = async () => {
  if (!canSubmit.value || !currentUser.value) {
    return;
  }

  if (!hasForwardableContent.value) {
    useAlert(t('CONVERSATION.FORWARD_MESSAGES.ERROR_NO_CONTENT'));
    return;
  }

  try {
    isForwarding.value = true;
    const routing = getWhatsappRouting(
      targetInbox.value,
      whatsappTransport.value,
      selectedContact.value
    );
    const { data } = await ConversationApi.forwardMessages(
      props.conversationId,
      selectedContact.value.targetConversationId
        ? {
            message_ids: props.selectedMessages.map(message => message.id),
            target_conversation_id: selectedContact.value.targetConversationId,
            ...(routing.whatsappTransport
              ? { whatsapp_transport: routing.whatsappTransport }
              : {}),
          }
        : {
            message_ids: props.selectedMessages.map(message => message.id),
            ...(selectedContact.value.recipient
              ? { recipient: selectedContact.value.recipient }
              : { target_contact_id: selectedContact.value.id }),
            target_inbox_id: routing.inboxId,
            ...(routing.whatsappTransport
              ? { whatsapp_transport: routing.whatsappTransport }
              : {}),
          }
    );
    emit('forwarded', data);
    show.value = false;
    resetState();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        error?.response?.data?.errors?.join?.(', ') ||
        t('CONVERSATION.FORWARD_MESSAGES.ERROR_API')
    );
  } finally {
    isForwarding.value = false;
  }
};
</script>

<template>
  <Modal v-model:show="show" :on-close="handleClose">
    <woot-modal-header
      :header-title="$t('CONVERSATION.FORWARD_MESSAGES.TITLE')"
      :header-content="$t('CONVERSATION.FORWARD_MESSAGES.DESCRIPTION')"
    />
    <div
      class="flex min-w-0 flex-col gap-4 overflow-y-auto max-h-[calc(100dvh-10rem-env(safe-area-inset-bottom))] p-4 sm:p-8"
    >
      <p class="text-xs text-n-slate-11">
        {{
          $t('CONVERSATION.FORWARD_MESSAGES.SELECTED_COUNT', {
            count: selectedMessages.length,
          })
        }}
      </p>

      <div class="flex flex-col gap-2">
        <ContactSelector
          :contacts="contacts"
          :selected-contact="selectedContact"
          :show-contacts-dropdown="showContactsDropdown"
          :is-loading="isSearching"
          :is-creating-contact="isCreatingContact"
          :contact-id="null"
          :contactable-inboxes-list="contactableInboxesList"
          :show-inboxes-dropdown="showInboxesDropdown"
          :has-errors="false"
          @search-contacts="handleContactSearch"
          @set-selected-contact="handleSelectedContact"
          @clear-selected-contact="clearSelectedContact"
          @update-dropdown="handleContactDropdownUpdate"
        />
        <InboxSelector
          v-if="!selectedContact?.targetConversationId"
          :target-inbox="targetInbox"
          :selected-contact="selectedContact"
          :show-inboxes-dropdown="showInboxesDropdown"
          :contactable-inboxes-list="contactableInboxesList"
          :has-errors="false"
          @update-inbox="handleTargetInbox"
          @toggle-dropdown="handleInboxDropdownToggle"
          @handle-inbox-action="handleTargetInbox"
        />
        <WhatsappTransportSelector
          v-if="whatsappLink"
          v-model="whatsappTransport"
          :inbox="targetInbox"
          :contact="selectedContact"
          :disabled="isForwarding"
        />
      </div>

      <div
        class="min-w-0 break-words rounded-md bg-n-alpha-2 p-3 text-xs text-n-slate-12 whitespace-pre-line"
      >
        {{ forwardMessagePreview }}
      </div>

      <div class="flex justify-end gap-2">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :label="$t('CONVERSATION.FORWARD_MESSAGES.CANCEL')"
          type="button"
          @click="handleClose"
        />
        <Button
          color="blue"
          size="sm"
          :disabled="!canSubmit"
          :label="$t('CONVERSATION.FORWARD_MESSAGES.ACTION_LABEL')"
          type="button"
          @click="handleForward"
        />
      </div>
    </div>
  </Modal>
</template>

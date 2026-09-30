<script setup>
import { computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMessageContext } from '../provider.js';
import BaseAttachmentBubble from './BaseAttachment.vue';

const props = defineProps({
  contactAttachment: { type: Object, default: null },
  listItem: { type: Boolean, default: false },
});
const emit = defineEmits(['opened']);

import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

const { attachments, content } = useMessageContext();

const $store = useStore();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const attachment = computed(() => {
  return props.contactAttachment || attachments.value[0];
});

const phoneNumber = computed(() => {
  return attachment.value?.fallbackTitle || '';
});
const email = computed(() => attachment.value?.meta?.email || '');

const contactName = computed(() => {
  const { meta } = attachment.value ?? {};
  const { formattedName, firstName, lastName } = meta ?? {};
  return (
    formattedName ||
    `${firstName ?? ''} ${lastName ?? ''}`.trim() ||
    content.value ||
    ''
  );
});

const formattedPhoneNumber = computed(() => {
  return phoneNumber.value.replace(/\s|-|[A-Za-z]/g, '');
});

const rawPhoneNumber = computed(() => {
  return phoneNumber.value.replace(/\D/g, '');
});

function getContactObject() {
  const contactItem = {
    name: contactName.value,
    ...(rawPhoneNumber.value
      ? { phone_number: `+${rawPhoneNumber.value}` }
      : {}),
    ...(email.value ? { email: email.value } : {}),
  };
  return contactItem;
}

async function filterContactByNumber(searchCandidate) {
  const query = {
    attribute_key: rawPhoneNumber.value ? 'phone_number' : 'email',
    filter_operator: 'equal_to',
    values: [searchCandidate],
    attribute_model: 'standard',
    custom_attribute_type: '',
  };

  const queryPayload = { payload: [query] };
  const contacts = await $store.dispatch('contacts/filter', {
    queryPayload,
    resetState: false,
  });
  return contacts.shift();
}

function openContact(contactId) {
  return router.push({
    name: 'contacts_edit',
    params: {
      accountId: route.params.accountId,
      contactId,
    },
  });
}

async function addContact() {
  try {
    let contact = await filterContactByNumber(
      rawPhoneNumber.value || email.value
    );
    if (contact) {
      useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
    } else {
      contact = await $store.dispatch('contacts/create', getContactObject());
      useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
    }
    await openContact(contact.id);
    emit('opened');
  } catch (error) {
    if (error instanceof DuplicateContactException) {
      if (error.contactErrorAttributes.includes('phone_number')) {
        useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
      } else {
        useAlert(error.contactErrorDetail || t('CONTACT_FORM.ERROR_MESSAGE'));
      }
    } else if (error instanceof ExceptionWithMessage) {
      useAlert(error.data);
    } else {
      useAlert(t('CONTACT_FORM.ERROR_MESSAGE'));
    }
  }
}

const action = computed(() => ({
  label: t('CONVERSATION.SAVE_CONTACT'),
  onClick: addContact,
}));
</script>

<template>
  <div
    v-if="listItem"
    class="flex min-w-0 items-center gap-3 rounded-lg bg-n-solid-2 p-3"
  >
    <span
      class="i-teenyicons-user-circle-solid size-8 shrink-0 text-n-slate-10"
    />
    <div class="min-w-0 flex-1">
      <p class="m-0 break-words text-n-slate-12">{{ contactName }}</p>
      <p class="m-0 break-all text-sm text-n-slate-11">
        {{ phoneNumber || email }}
      </p>
      <p v-if="!phoneNumber && !email" class="m-0 text-sm text-n-ruby-11">
        {{ t('CONVERSATION.CONTACT_BUNDLE.MISSING_DETAILS') }}
      </p>
      <button
        v-else
        type="button"
        class="mt-2 text-sm text-n-blue-text"
        @click="addContact"
      >
        {{ t('CONVERSATION.CONTACT_BUNDLE.OPEN_CONTACT') }}
      </button>
    </div>
  </div>
  <BaseAttachmentBubble
    v-else
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-[#D6409F]"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.CONTACT"
    :title="contactName"
    :content="phoneNumber || email"
    :action="formattedPhoneNumber || email ? action : null"
  />
</template>

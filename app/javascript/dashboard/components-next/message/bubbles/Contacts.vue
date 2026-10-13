<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../provider';
import BaseAttachmentBubble from './BaseAttachment.vue';
import Dialog from 'next/dialog/Dialog.vue';
import ContactBubble from './Contact.vue';

defineOptions({ inheritAttrs: false });

const { attachments, contentAttributes } = useMessageContext();
const { t } = useI18n();
const dialog = ref(null);
const search = ref('');
const contacts = computed(() => {
  const items = (attachments.value || []).filter(a => a.fileType === 'contact');
  if (items.length) return items;
  return (contentAttributes.value.contacts || []).map((contact, index) => ({
    id: index,
    fileType: 'contact',
    fallbackTitle: contact.phoneNumber || contact.phone_number || '',
    meta: {
      formattedName:
        contact.formattedName || contact.formatted_name || contact.name,
      firstName: contact.firstName || contact.first_name,
      lastName: contact.lastName || contact.last_name,
      email: contact.email,
    },
  }));
});
const name = contact =>
  contact.meta?.formattedName ||
  [contact.meta?.firstName, contact.meta?.lastName].filter(Boolean).join(' ');
const title = computed(() =>
  contacts.value.length > 1
    ? t(
        'CONVERSATION.CONTACT_BUNDLE.SUMMARY',
        {
          name: name(contacts.value[0]),
          count: contacts.value.length - 1,
        },
        contacts.value.length - 1
      )
    : name(contacts.value[0] || {})
);
const filteredContacts = computed(() =>
  contacts.value.filter(contact =>
    `${name(contact)} ${contact.fallbackTitle} ${contact.meta?.email || ''}`
      .toLocaleLowerCase()
      .includes(search.value.trim().toLocaleLowerCase())
  )
);
const action = computed(() => ({
  label: t('CONVERSATION.CONTACT_BUNDLE.VIEW_ALL'),
  onClick: () => {
    search.value = '';
    dialog.value.open();
  },
}));
</script>

<template>
  <BaseAttachmentBubble
    icon="i-teenyicons-users-outline"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.CONTACT"
    :title="title"
    content=""
    :action="action"
  />
  <Dialog
    ref="dialog"
    :title="t('CONVERSATION.CONTACT_BUNDLE.TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="t('CONVERSATION.CONTACT_BUNDLE.CLOSE')"
    mobile-constrained
    width="md"
    dialog-class="max-h-[calc(100dvh-1rem)]"
    content-class="max-h-[calc(100dvh-1rem)]"
  >
    <input
      v-model="search"
      type="search"
      :aria-label="t('CONVERSATION.CONTACT_BUNDLE.SEARCH')"
      :placeholder="t('CONVERSATION.CONTACT_BUNDLE.SEARCH')"
      class="w-full min-w-0 shrink-0 rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12"
    />
    <div
      class="min-h-0 max-h-[50dvh] overflow-y-auto min-w-0 flex flex-col gap-3"
    >
      <ContactBubble
        v-for="contact in filteredContacts"
        :key="contact.id"
        :contact-attachment="contact"
        list-item
        @opened="dialog.close()"
      />
      <p v-if="!filteredContacts.length" class="text-n-slate-11 text-sm">
        {{ t('CONVERSATION.CONTACT_BUNDLE.EMPTY') }}
      </p>
    </div>
  </Dialog>
</template>

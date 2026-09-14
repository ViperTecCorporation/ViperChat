<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { INPUT_TYPES } from 'dashboard/components-next/taginput/helper/tagInputHelper.js';

import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { normalizeDirectRecipient } from '../helpers/directRecipient';

const props = defineProps({
  contacts: {
    type: Array,
    required: true,
  },
  selectedContact: {
    type: Object,
    default: null,
  },
  showContactsDropdown: {
    type: Boolean,
    required: true,
  },
  isLoading: {
    type: Boolean,
    required: true,
  },
  isCreatingContact: {
    type: Boolean,
    required: true,
  },
  contactId: {
    type: String,
    default: null,
  },
  contactableInboxesList: {
    type: Array,
    default: () => [],
  },
  showInboxesDropdown: {
    type: Boolean,
    required: true,
  },
  hasErrors: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'searchContacts',
  'setSelectedContact',
  'clearSelectedContact',
  'updateDropdown',
]);

const i18nPrefix = 'COMPOSE_NEW_CONVERSATION.FORM.CONTACT_SELECTOR';
const { t } = useI18n();

const query = ref('');
const recipientMode = ref('phone');
const directRecipient = computed(() =>
  normalizeDirectRecipient(query.value, recipientMode.value)
);
const inputType = computed(() =>
  directRecipient.value ? INPUT_TYPES.TEXT : INPUT_TYPES.EMAIL
);

const selectContact = item => {
  if (item.action === 'create' && directRecipient.value) {
    emit('setSelectedContact', {
      ...item,
      action: 'direct',
      recipient: directRecipient.value,
    });
  } else {
    emit('setSelectedContact', item);
  }
};

const contactLabel = ({
  name,
  email,
  phoneNumber,
  bsuid,
  whatsappUsername,
}) => {
  const identifier = email || whatsappUsername || phoneNumber || bsuid;
  return identifier ? `${name} (${identifier})` : name;
};

const contactsList = computed(() => {
  return props.contacts?.map(
    ({
      name,
      id,
      thumbnail,
      email,
      phoneNumber,
      bsuid,
      whatsappUsername,
      ...rest
    }) => ({
      id,
      label: contactLabel({
        name,
        email,
        phoneNumber,
        bsuid,
        whatsappUsername,
      }),
      value: id,
      thumbnail: { name, src: thumbnail },
      ...rest,
      name,
      email,
      phoneNumber,
      bsuid,
      whatsappUsername,
      action: 'contact',
    })
  );
});

const selectedContactLabel = computed(() => {
  const {
    name,
    email = '',
    phoneNumber = '',
    bsuid = '',
    whatsappUsername = '',
  } = props.selectedContact || {};
  return (
    contactLabel({
      name,
      email,
      phoneNumber,
      bsuid,
      whatsappUsername,
    }) || ''
  );
});

const errorClass = computed(() => {
  return props.hasErrors
    ? '[&_input]:placeholder:!text-n-ruby-9 [&_input]:dark:placeholder:!text-n-ruby-9'
    : '';
});

const handleInput = value => {
  // Update input type based on whether input starts with '+'
  // If it does, set input type to 'tel'
  // Otherwise, set input type to 'email'
  query.value = value;
  emit(
    'searchContacts',
    directRecipient.value?.phone_number || directRecipient.value?.bsuid || value
  );
};
</script>

<template>
  <div class="relative flex-1 px-4 py-3 overflow-y-visible">
    <div class="flex items-baseline w-full gap-3 min-h-7">
      <label class="text-sm font-medium text-n-slate-11 whitespace-nowrap">
        {{ t(`${i18nPrefix}.LABEL`) }}
      </label>

      <div
        v-if="isCreatingContact"
        class="flex items-center gap-1.5 rounded-md bg-n-alpha-2 px-3 min-h-7 min-w-0"
      >
        <span class="text-sm truncate text-n-slate-12">
          {{ t(`${i18nPrefix}.CONTACT_CREATING`) }}
        </span>
      </div>
      <div
        v-else-if="selectedContact"
        class="flex items-center gap-1.5 rounded-md bg-n-alpha-2 min-h-7 min-w-0"
        :class="!contactId ? 'ltr:pl-3 rtl:pr-3 ltr:pr-1 rtl:pl-1' : 'px-3'"
      >
        <span class="text-sm truncate text-n-slate-12">
          {{
            isCreatingContact
              ? t(`${i18nPrefix}.CONTACT_CREATING`)
              : selectedContactLabel
          }}
        </span>
        <Button
          v-if="!contactId"
          variant="ghost"
          icon="i-lucide-x"
          color="slate"
          :disabled="contactId"
          size="xs"
          @click="emit('clearSelectedContact')"
        />
      </div>
      <TagInput
        v-else
        :placeholder="t(`${i18nPrefix}.TAG_INPUT_PLACEHOLDER`)"
        mode="single"
        :menu-items="contactsList"
        :show-dropdown="showContactsDropdown"
        :is-loading="isLoading"
        :disabled="contactableInboxesList?.length > 0 && showInboxesDropdown"
        allow-create
        :type="inputType"
        :filter-menu-items="false"
        class="flex-1 min-h-7"
        :class="errorClass"
        focus-on-mount
        @input="handleInput"
        @on-click-outside="emit('updateDropdown', 'contacts', false)"
        @add="selectContact"
        @remove="emit('clearSelectedContact')"
      />
    </div>
    <div
      v-if="query && !selectedContact && /\d/.test(query)"
      class="flex flex-wrap items-center gap-2 mt-2 text-xs text-n-slate-11"
    >
      <select
        v-model="recipientMode"
        :aria-label="t(`${i18nPrefix}.IDENTIFIER_TYPE`)"
        class="max-w-full rounded border border-n-weak bg-n-background text-n-slate-12"
      >
        <option value="phone">{{ t(`${i18nPrefix}.PHONE_TYPE`) }}</option>
        <option value="bsuid">{{ t(`${i18nPrefix}.BSUID_TYPE`) }}</option>
      </select>
      <span>{{
        directRecipient
          ? Object.values(directRecipient)[0]
          : t(`${i18nPrefix}.IDENTIFIER_HINT`)
      }}</span>
      <Button
        v-if="directRecipient"
        size="sm"
        :label="t(`${i18nPrefix}.USE_IDENTIFIER`)"
        @click="selectContact({ action: 'create' })"
      />
    </div>
  </div>
</template>

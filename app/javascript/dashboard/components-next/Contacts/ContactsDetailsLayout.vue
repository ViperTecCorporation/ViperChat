<script setup>
import { computed, useSlots, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMediaQuery } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    default: () => ({}),
  },
  isUpdating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['goToContactsList', 'toggleBlock']);

const { t } = useI18n();
const slots = useSlots();
const route = useRoute();

const isContactSidebarOpen = ref(false);
const isDesktop = useMediaQuery('(min-width: 1024px)');

const contactId = computed(() => route.params.contactId);

const selectedContactName = computed(() => {
  return props.selectedContact?.name;
});

const breadcrumbItems = computed(() => {
  const items = [
    {
      label: t('CONTACTS_LAYOUT.HEADER.BREADCRUMB.CONTACTS'),
      link: '#',
    },
  ];
  if (props.selectedContact) {
    items.push({
      label: selectedContactName.value,
    });
  }
  return items;
});

const isContactBlocked = computed(() => {
  return props.selectedContact?.blocked;
});

const handleBreadcrumbClick = () => {
  emit('goToContactsList');
};

const toggleBlock = () => {
  emit('toggleBlock', isContactBlocked.value);
};

const handleConversationSidebarToggle = () => {
  isContactSidebarOpen.value = !isContactSidebarOpen.value;
};

const closeMobileSidebar = () => {
  if (!isContactSidebarOpen.value) return;
  isContactSidebarOpen.value = false;
};
</script>

<template>
  <section
    class="flex min-w-0 w-full h-full min-h-0 overflow-hidden justify-evenly bg-n-surface-1"
  >
    <div
      v-show="isDesktop || !isContactSidebarOpen"
      class="flex min-w-0 flex-col w-full h-full min-h-0 ltr:2xl:ml-56 rtl:2xl:mr-56"
    >
      <header class="shrink-0 px-4 sm:px-6 3xl:px-0">
        <div class="w-full mx-auto max-w-[40.625rem]">
          <div
            class="flex flex-col xl:flex-row items-start xl:items-center justify-between w-full py-4 sm:py-7 gap-3"
          >
            <Breadcrumb
              :items="breadcrumbItems"
              @click="handleBreadcrumbClick"
            />
            <div class="flex flex-wrap items-center gap-2">
              <Button
                :label="
                  !isContactBlocked
                    ? $t('CONTACTS_LAYOUT.HEADER.BLOCK_CONTACT')
                    : $t('CONTACTS_LAYOUT.HEADER.UNBLOCK_CONTACT')
                "
                size="sm"
                slate
                :is-loading="isUpdating"
                :disabled="isUpdating"
                @click="toggleBlock"
              />
              <VoiceCallButton
                v-if="contactId && selectedContact?.phoneNumber"
                :phone="selectedContact?.phoneNumber"
                :contact-id="contactId"
                :label="$t('CONTACT_PANEL.CALL')"
                size="sm"
              />
              <ComposeConversation :contact-id="contactId">
                <template #trigger>
                  <Button
                    :label="$t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
                    size="sm"
                  />
                </template>
              </ComposeConversation>
              <Button
                v-if="slots.sidebar && !isDesktop"
                :label="t('CONTACTS_LAYOUT.MOBILE_PANEL.OPEN')"
                icon="i-lucide-panel-right-open"
                size="sm"
                slate
                data-contact-sidebar-toggle
                :aria-expanded="isContactSidebarOpen"
                @click="handleConversationSidebarToggle"
              />
            </div>
          </div>
        </div>
      </header>
      <main
        class="flex-1 min-h-0 min-w-0 px-4 sm:px-6 overflow-y-auto 3xl:px-px"
      >
        <div class="w-full py-4 mx-auto max-w-[40.625rem]">
          <slot name="default" />
        </div>
      </main>
    </div>

    <!-- Desktop sidebar -->
    <div
      v-if="slots.sidebar && isDesktop"
      class="hidden lg:flex flex-col min-w-52 w-full max-w-md border-l border-n-weak bg-n-solid-2"
    >
      <div class="shrink-0">
        <slot name="sidebarHeader" />
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto pb-6 pt-3">
        <slot name="sidebar" />
      </div>
    </div>

    <aside
      v-if="slots.sidebar && !isDesktop && isContactSidebarOpen"
      id="contact-sidebar-content"
      class="flex w-full min-w-0 h-full min-h-0 flex-col bg-n-solid-2"
      :aria-label="t('CONTACTS_LAYOUT.MOBILE_PANEL.OPEN')"
    >
      <div class="flex shrink-0 min-w-0 items-center gap-3 px-4 pt-4">
        <Button
          icon="i-lucide-arrow-left"
          :aria-label="t('CONTACTS_LAYOUT.MOBILE_PANEL.BACK')"
          :label="t('CONTACTS_LAYOUT.MOBILE_PANEL.BACK')"
          size="sm"
          slate
          @click="closeMobileSidebar"
        />
        <span class="min-w-0 truncate text-sm font-medium text-n-slate-12">
          {{ selectedContactName }}
        </span>
      </div>
      <div class="shrink-0 min-w-0">
        <slot name="sidebarHeader" />
      </div>
      <div
        class="flex-1 min-h-0 min-w-0 overflow-y-auto overscroll-contain pb-20 pt-3"
      >
        <slot name="sidebar" />
      </div>
    </aside>
  </section>
</template>

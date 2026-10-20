<script setup>
import { includesNormalized } from 'shared/helpers/search';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLabelCreation } from 'dashboard/composables/useLabelCreation';
import CreateLabel from 'dashboard/routes/dashboard/settings/labels/AddLabel.vue';

import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  labelMenuItems: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['updateLabel']);

const { t } = useI18n();

const showDropdown = ref(false);
const showCreateModal = ref(false);
const { canCreateLabels } = useLabelCreation();
const search = ref('');
const menuItems = computed(() => {
  const items = props.labelMenuItems.filter(item =>
    includesNormalized(item.label, search.value)
  );
  if (canCreateLabels.value) {
    items.push({
      label: t('LABEL_MGMT.HEADER_BTN_TXT'),
      action: 'createLabel',
      value: 'createLabel',
      icon: 'i-lucide-plus',
    });
  }
  return items;
});
const handleAction = item => {
  if (item.action === 'createLabel') {
    showDropdown.value = false;
    showCreateModal.value = true;
  } else {
    emit('updateLabel', item);
  }
};
</script>

<template>
  <div class="relative">
    <button
      class="flex items-center gap-1 px-2 py-1 rounded-md outline-dashed h-6 outline-1 outline-n-slate-6 hover:bg-n-alpha-2"
      :class="{ 'bg-n-alpha-2': showDropdown }"
      @click="showDropdown = !showDropdown"
    >
      <span class="i-lucide-plus" />
      <span class="text-sm text-n-slate-11">
        {{ t('LABEL.TAG_BUTTON') }}
      </span>
    </button>
    <DropdownMenu
      v-if="showDropdown"
      v-on-clickaway="() => (showDropdown = false)"
      :menu-items="menuItems"
      disable-local-filtering
      show-search
      class="z-[100] w-48 mt-2 ltr:left-0 rtl:right-0 top-full max-h-52"
      @search="search = $event"
      @action="handleAction"
    >
      <template #thumbnail="{ item }">
        <div
          v-if="item.thumbnail"
          class="rounded-sm size-2"
          :style="{ backgroundColor: item.thumbnail.color }"
        />
      </template>
    </DropdownMenu>
    <woot-modal
      v-model:show="showCreateModal"
      :on-close="() => (showCreateModal = false)"
    >
      <CreateLabel :prefill-title="search" @close="showCreateModal = false" />
    </woot-modal>
  </div>
</template>

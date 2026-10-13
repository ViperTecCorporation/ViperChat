<script setup>
import { useTemplateRef, onBeforeUnmount, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTrack } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { vOnClickOutside } from '@vueuse/components';
import { CONVERSATION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useConversationFilterContext } from './provider.js';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';

import Button from 'next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ConditionRow from './ConditionRow.vue';

const props = defineProps({
  isFolderView: {
    type: Boolean,
    default: false,
  },
  folderName: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['applyFilter', 'updateFolder', 'close']);
const { filterTypes } = useConversationFilterContext();

const filters = defineModel({
  type: Array,
  default: [],
});
const folderNameLocal = ref(props.folderName);

const DEFAULT_FILTER = {
  attributeKey: 'status',
  filterOperator: 'equal_to',
  values: [],
  queryOperator: 'and',
};

const { t } = useI18n();
const store = useStore();

const resetFilter = () => {
  filters.value = [{ ...DEFAULT_FILTER }];
};

const removeFilter = index => {
  if (filters.value.length === 1) {
    resetFilter();
  } else {
    filters.value.splice(index, 1);
  }
};

const addFilter = () => {
  filters.value.push({ ...DEFAULT_FILTER });
};

const conditionsRef = useTemplateRef('conditionsRef');

const isConditionsValid = () => {
  return conditionsRef.value.every(condition => condition.validate());
};

const updateSavedCustomViews = () => {
  if (isConditionsValid()) {
    emit('updateFolder', filters.value, folderNameLocal.value);
  }
};

function validateAndSubmit() {
  if (!isConditionsValid()) {
    return;
  }

  store.dispatch(
    'setConversationFilters',
    useSnakeCase(JSON.parse(JSON.stringify(filters.value)))
  );
  emit('applyFilter', filters.value);
  useTrack(CONVERSATION_EVENTS.APPLY_FILTER, {
    appliedFilters: filters.value.map(filter => ({
      key: filter.attributeKey,
      operator: filter.filterOperator,
      queryOperator: filter.queryOperator,
    })),
  });
}

const filterModalHeaderTitle = computed(() => {
  return !props.isFolderView
    ? t('FILTER.TITLE')
    : t('FILTER.EDIT_CUSTOM_FILTER');
});

onBeforeUnmount(() => emit('close'));
const outsideClickHandler = [
  () => emit('close'),
  { ignore: ['#toggleConversationFilterButton'] },
];
</script>

<template>
  <div
    v-on-click-outside="outsideClickHandler"
    data-testid="conversation-filter-panel"
    class="fixed inset-x-2 z-40 w-auto min-w-0 max-w-3xl max-h-[calc(100dvh-10rem)] overflow-y-auto border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] shadow-lg rounded-xl p-3 grid gap-4 lg:static lg:inset-x-auto lg:max-h-none lg:overflow-visible lg:p-6 lg:gap-6 lg:w-[750px]"
  >
    <h3 class="text-base font-medium leading-6 text-n-slate-12">
      {{ filterModalHeaderTitle }}
    </h3>
    <div v-if="props.isFolderView">
      <div class="border-b border-n-weak pb-6">
        <Input
          v-model="folderNameLocal"
          :label="t('FILTER.FOLDER_LABEL')"
          :placeholder="t('FILTER.INPUT_PLACEHOLDER')"
        />
      </div>
    </div>
    <ul class="grid min-w-0 gap-4 list-none">
      <template v-for="(filter, index) in filters" :key="filter.id">
        <ConditionRow
          v-if="index === 0"
          ref="conditionsRef"
          :key="`filter-${filter.attributeKey}-0`"
          v-model:attribute-key="filter.attributeKey"
          v-model:filter-operator="filter.filterOperator"
          v-model:values="filter.values"
          :filter-types="filterTypes"
          :show-query-operator="false"
          @remove="removeFilter(index)"
        />
        <ConditionRow
          v-else
          :key="`filter-${filter.attributeKey}-${index}`"
          ref="conditionsRef"
          v-model:attribute-key="filter.attributeKey"
          v-model:filter-operator="filter.filterOperator"
          v-model:query-operator="filters[index - 1].queryOperator"
          v-model:values="filter.values"
          show-query-operator
          :filter-types="filterTypes"
          @remove="removeFilter(index)"
        />
      </template>
    </ul>
    <div class="flex min-w-0 flex-col gap-2 lg:flex-row lg:justify-between">
      <Button sm ghost blue class="max-lg:min-h-11" @click="addFilter">
        {{ $t('FILTER.ADD_NEW_FILTER') }}
      </Button>
      <div
        class="grid min-w-0 grid-cols-2 gap-2 lg:flex max-lg:[&>button]:h-auto max-lg:[&>button]:min-h-11 max-lg:[&>button]:min-w-0 max-lg:[&>button]:whitespace-normal max-lg:[&>button]:py-2"
      >
        <Button sm faded slate @click="resetFilter">
          {{ t('FILTER.CLEAR_BUTTON_LABEL') }}
        </Button>
        <Button
          v-if="isFolderView"
          sm
          solid
          blue
          :disabled="!folderNameLocal"
          @click="updateSavedCustomViews"
        >
          {{ t('FILTER.UPDATE_BUTTON_LABEL') }}
        </Button>
        <Button v-else sm solid blue @click="validateAndSubmit">
          {{ t('FILTER.SUBMIT_BUTTON_LABEL') }}
        </Button>
      </div>
    </div>
  </div>
</template>

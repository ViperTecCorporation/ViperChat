<script setup>
import { computed, toRef } from 'vue';
import { useChannelIcon, useChannelBrandIcon } from './provider';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  useBrandIcon: {
    type: Boolean,
    default: false,
  },
});

defineOptions({ inheritAttrs: false });

const inboxRef = toRef(props, 'inbox');
const channelIcon = useChannelIcon(inboxRef);
const brandIcon = useChannelBrandIcon(inboxRef);

const icon = computed(() =>
  props.useBrandIcon && brandIcon.value ? brandIcon.value : channelIcon.value
);
</script>

<template>
  <span class="relative inline-flex" v-bind="$attrs">
    <Icon :icon="icon" class="size-full" />
  </span>
</template>

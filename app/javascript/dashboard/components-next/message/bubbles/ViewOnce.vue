<script setup>
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';

defineEmits(['reveal']);
</script>

<template>
  <BaseBubble class="p-3">
    <button
      type="button"
      class="flex items-center gap-2 p-2 rounded-lg hover:bg-n-alpha-1"
      @click="$emit('reveal')"
    >
      <Icon icon="i-lucide-eye" class="size-5" />
      {{ $t('CONVERSATION.VIEW_ONCE_OPEN') }}
    </button>
  </BaseBubble>
</template>

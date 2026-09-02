<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../provider.js';

defineProps({
  icon: { type: [String, Object], required: true },
  iconBgColor: { type: String, default: 'bg-n-alpha-3' },
  senderTranslationKey: { type: String, required: true },
  content: { type: String, required: true },
  title: { type: String, default: '' }, // Title can be any name, description, etc
  action: {
    type: Object,
    required: true,
    validator: action => {
      return action.label && (action.href || action.onClick);
    },
  },
});

const { sender } = useMessageContext();
const { t } = useI18n();

const senderName = computed(() => {
  return sender?.value?.name || '';
});
</script>

<template>
  <BaseBubble
    class="w-full max-w-full overflow-hidden p-3"
    data-bubble-name="attachment"
  >
    <div class="grid w-full min-w-0 gap-4">
      <div class="grid gap-3">
        <div
          class="size-8 rounded-lg grid place-content-center"
          :class="iconBgColor"
        >
          <slot name="icon">
            <Icon :icon="icon" class="text-white size-4" />
          </slot>
        </div>
        <div class="space-y-1 overflow-hidden">
          <div v-if="senderName" class="text-n-slate-12 text-sm truncate">
            {{
              t(senderTranslationKey, {
                sender: senderName,
              })
            }}
          </div>
          <slot>
            <div v-if="title" class="truncate text-sm text-n-slate-12">
              {{ title }}
            </div>
            <div v-if="content" class="truncate text-sm text-n-slate-11">
              {{ content }}
            </div>
          </slot>
        </div>
      </div>
      <div v-if="action" class="min-w-0 mb-2">
        <a
          v-if="action.href"
          :href="action.href"
          rel="noreferrer noopener nofollow"
          target="_blank"
          class="block w-full max-w-full px-4 py-2 text-sm text-center border rounded-lg box-border bg-n-solid-3 border-n-container"
        >
          {{ action.label }}
        </a>
        <button
          v-else
          class="w-full max-w-full px-4 py-2 text-sm text-center border rounded-lg box-border bg-n-solid-3 border-n-container"
          @click="action.onClick"
        >
          {{ action.label }}
        </button>
      </div>
    </div>
  </BaseBubble>
</template>

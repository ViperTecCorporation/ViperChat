<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Attachment from './Attachment.vue';

const props = defineProps({ message: { type: Object, required: true } });
const { t, locale } = useI18n();
const opened = ref(false);
const hidden = computed(() => props.message.view_once && !opened.value);
const status = computed(() =>
  ['sent', 'delivered', 'read'].includes(props.message.status)
    ? props.message.status
    : null
);
const statusLabel = computed(
  () =>
    ({
      sent: t('status.sent'),
      delivered: t('status.delivered'),
      read: t('status.read'),
    })[status.value]
);
const statusIcon = computed(() => (status.value === 'sent' ? '✓' : '✓✓'));
const time = computed(() =>
  new Date(props.message.created_at * 1000).toLocaleString(locale.value, {
    dateStyle: 'short',
    timeStyle: 'short',
  })
);
</script>

<template>
  <article
    class="flex min-w-0"
    :class="message.message_type === 0 ? 'justify-end' : 'justify-start'"
  >
    <div
      class="min-w-0 max-w-[90%] rounded-xl border border-n-weak p-3 sm:max-w-[80%]"
      :class="[
        message.message_type === 0 ? 'bg-n-alpha-2' : 'bg-n-background',
        message.attachments?.some(
          attachment => attachment.file_type === 'audio'
        )
          ? 'w-80'
          : '',
      ]"
    >
      <p class="mb-1 break-words text-xs font-medium text-n-slate-11">
        {{
          message.sender?.name ||
          (message.message_type === 0 ? t('you') : t('team'))
        }}
      </p>
      <button
        v-if="hidden"
        type="button"
        class="min-h-11 rounded-lg border border-n-weak px-3 text-sm font-medium"
        @click="opened = true"
      >
        {{ t('openOnce') }}
      </button>
      <template v-else>
        <p
          v-if="message.content"
          class="whitespace-pre-wrap break-words [overflow-wrap:anywhere]"
        >
          {{ message.content }}
        </p>
        <div class="mt-2 space-y-2">
          <Attachment
            v-for="attachment in message.attachments || []"
            :key="attachment.id"
            :attachment="attachment"
          />
        </div>
        <p v-if="message.view_once" class="mt-2 text-xs text-n-slate-11">
          {{ t('replay') }}
        </p>
      </template>
      <div
        class="mt-2 flex flex-wrap items-center justify-end gap-1 text-xs text-n-slate-11"
      >
        <time>{{ time }}</time>
        <span
          v-if="status"
          role="img"
          :aria-label="statusLabel"
          :title="statusLabel"
          :class="status === 'read' ? 'text-n-blue-11' : 'text-n-slate-11'"
        >
          <span aria-hidden="true">{{ statusIcon }}</span>
        </span>
      </div>
    </div>
  </article>
</template>

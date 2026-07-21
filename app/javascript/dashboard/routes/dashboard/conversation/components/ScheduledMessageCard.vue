<script setup>
import { computed, ref } from 'vue';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  item: { type: Object, required: true },
});

const emit = defineEmits(['edit', 'delete', 'retry', 'open']);

const showMenu = ref(false);

const statusConfig = {
  scheduled: { label: 'Agendado', className: 'text-n-blue-11 bg-n-blue-3' },
  sending: { label: 'Enviando', className: 'text-n-amber-11 bg-n-amber-3' },
  sent: { label: 'Enviado', className: 'text-n-teal-11 bg-n-teal-3' },
  failed: { label: 'Falhou', className: 'text-n-ruby-11 bg-n-ruby-3' },
  cancelled: { label: 'Cancelado', className: 'text-n-slate-11 bg-n-alpha-2' },
};

const status = computed(
  () => statusConfig[props.item.status] || statusConfig.scheduled
);

const preview = computed(() => {
  const messages = props.item.messages || [];
  if (messages.length > 1) {
    return messages
      .map(
        (message, index) =>
          `${index + 1}. ${message.content || (message.voice_message ? 'Áudio' : 'Anexo')}`
      )
      .join('\n');
  }
  return (
    messages[0]?.content ||
    props.item.content ||
    props.item.content_attributes?.template_name ||
    (messages[0]?.voice_message ? 'Mensagem de áudio' : 'Mensagem com anexo')
  );
});

const menuItems = computed(() => {
  const items = [
    {
      label: 'Abrir conversa',
      action: 'open',
      icon: 'i-lucide-message-square',
    },
  ];

  if (
    !props.item.can_manage ||
    ['sent', 'cancelled'].includes(props.item.status)
  ) {
    return items;
  }

  items.push({
    label: 'Editar',
    action: 'edit',
    icon: 'i-lucide-pencil',
  });

  if (props.item.status === 'failed') {
    items.push({
      label: 'Reagendar',
      action: 'retry',
      icon: 'i-lucide-calendar-clock',
    });
  }

  items.push({
    label: 'Excluir',
    action: 'delete',
    icon: 'i-lucide-trash-2',
  });
  return items;
});

const handleAction = ({ action }) => {
  showMenu.value = false;
  if (action === 'edit') emit('edit', props.item);
  if (action === 'delete') emit('delete', props.item);
  if (action === 'retry') emit('retry', props.item);
  if (action === 'open') emit('open', props.item);
};
</script>

<template>
  <article
    class="relative flex flex-col gap-3 p-3.5 bg-n-alpha-3 border border-n-weak rounded-xl shadow-sm hover:border-n-strong transition-colors"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="flex items-center min-w-0 gap-2.5">
        <Avatar
          :name="item.contact.name"
          :src="item.contact.thumbnail"
          :size="36"
          rounded-full
        />
        <div class="min-w-0">
          <p class="mb-0 text-sm font-medium truncate text-n-slate-12">
            {{ item.contact.name }}
          </p>
          <p class="mb-0 text-xs truncate text-n-slate-11">
            {{ item.inbox.name }}
          </p>
        </div>
      </div>
      <div v-on-clickaway="() => (showMenu = false)" class="relative shrink-0">
        <Button
          icon="i-lucide-ellipsis-vertical"
          color="slate"
          variant="ghost"
          size="xs"
          @click="showMenu = !showMenu"
        />
        <DropdownMenu
          v-if="showMenu"
          :menu-items="menuItems"
          class="top-full end-0 mt-1 w-44"
          @action="handleAction"
        />
      </div>
    </div>

    <p class="mb-0 text-sm leading-5 text-n-slate-12 line-clamp-3">
      {{ preview }}
    </p>

    <div
      v-if="item.reason"
      class="flex gap-2 p-2 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11"
    >
      <Icon icon="i-lucide-notebook-pen" class="mt-0.5 size-3.5 shrink-0" />
      <span class="line-clamp-2">{{ item.reason }}</span>
    </div>

    <div
      v-if="item.error_message"
      class="flex gap-2 p-2 text-xs rounded-lg bg-n-ruby-3 text-n-ruby-11"
    >
      <Icon icon="i-lucide-circle-alert" class="mt-0.5 size-3.5 shrink-0" />
      <span class="line-clamp-3">{{ item.error_message }}</span>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-2 pt-1">
      <div class="flex items-center min-w-0 gap-1.5 text-xs text-n-slate-11">
        <span
          v-if="item.label"
          class="rounded-sm size-2 shrink-0"
          :style="{ backgroundColor: item.label.color }"
        />
        <span class="truncate">{{ item.label?.title || 'Sem etiqueta' }}</span>
        <Icon icon="i-lucide-user-round" class="size-3.5 shrink-0" />
        <span class="truncate">{{ item.sender.name }}</span>
        <span
          v-if="item.message_count > 1"
          class="inline-flex items-center gap-1 ml-1"
        >
          <Icon icon="i-lucide-list-ordered" class="size-3.5" />
          {{ `${item.message_count} mensagens` }}
        </span>
        <span
          v-if="item.attachment_count"
          class="inline-flex items-center gap-1 ml-1"
        >
          <Icon icon="i-lucide-paperclip" class="size-3.5" />
          {{ item.attachment_count }}
        </span>
      </div>
      <span
        class="px-2 py-1 text-xs font-medium rounded-md"
        :class="status.className"
      >
        {{ status.label }}
      </span>
    </div>
  </article>
</template>

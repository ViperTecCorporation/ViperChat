<script setup>
/* eslint-disable no-console */
import { computed, ref, onMounted, onUnmounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  pipelineAgents: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits([
  'click',
  'resolve',
  'assign',
  'removePipeline',
  'toggleSort',
]);

const { t } = useI18n();
const store = ref(useStore());

// Hover state
const isHovered = ref(false);
const showPriorityPopover = ref(false);
const showAssigneePopover = ref(false);
const showMoreMenu = ref(false);
const showDateEditor = ref(false);
const editingDateValue = ref('');

const allAgents = computed(() => store.value.getters['agents/getAgents'] || []);

const filteredAgents = computed(() => {
  if (props.pipelineAgents.length > 0) {
    return allAgents.value.filter(a => props.pipelineAgents.includes(a.id));
  }
  return allAgents.value;
});

// Online indicator
const isOnline = computed(() => {
  return (
    props.conversation.meta?.sender?.availability_status === 'online' ||
    props.conversation.meta?.sender?.online === true
  );
});

// Format Creation Time Tooltip
const exactCreationTime = computed(() => {
  const dateVal = props.conversation.created_at || props.conversation.timestamp;
  if (!dateVal) return '';
  const d = new Date(dateVal * 1000 || dateVal);
  return `Criado em ${d.toLocaleDateString('pt-BR')} às ${d.toLocaleTimeString('pt-BR')}`;
});

// Custom timeago formatter (English/Portuguese abbreviated)
const timeAgo = computed(() => {
  const timeVal = props.conversation.created_at || props.conversation.timestamp;
  if (!timeVal) return '';
  const date = new Date(timeVal * 1000 || timeVal);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'agora';
  if (diffMins < 60) return `${diffMins}m`;
  if (diffHours < 24) return `${diffHours}h`;
  return `${diffDays}d`;
});

// Time badge for card: shows "Atrasado", "Amanhã", or timeago
const timeBadge = computed(() => {
  // First check due date for Atrasado/Amanhã
  const dVal = dueDateValue.value;
  if (dVal) {
    const dueDate = new Date(dVal);
    const today = new Date();
    const dDate = new Date(
      dueDate.getFullYear(),
      dueDate.getMonth(),
      dueDate.getDate()
    );
    const tDate = new Date(
      today.getFullYear(),
      today.getMonth(),
      today.getDate()
    );
    const diffDays = Math.floor((dDate - tDate) / (1000 * 60 * 60 * 24));

    if (diffDays < 0) {
      return {
        label: 'Atrasado',
        class: 'bg-rose-500/10 text-rose-400 border-rose-500/20',
      };
    }
    if (diffDays === 1) {
      return {
        label: 'Amanhã',
        class: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      };
    }
    if (diffDays === 0) {
      return {
        label: 'Hoje',
        class: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      };
    }
  }

  // Otherwise show time since creation
  const ta = timeAgo.value;
  if (!ta) return null;
  return {
    label: ta,
    class: 'bg-slate-800 text-slate-400 border-slate-700/50',
  };
});

const formattedTimestamp = computed(() => {
  const timeVal = props.conversation.created_at || props.conversation.timestamp;
  if (!timeVal) return null;
  const date = new Date(timeVal * 1000 || timeVal);
  const now = new Date();
  const diffMs = now - date;
  const diffHours = Math.floor(diffMs / 3600000);

  if (diffHours < 24) {
    return {
      text: timeAgo.value,
      icon: 'i-lucide-clock',
    };
  }
  const options = { day: 'numeric', month: 'short' };
  return {
    text: date.toLocaleDateString('pt-BR', options),
    icon: 'i-lucide-calendar',
  };
});

// Inbox & Channel Helpers
const inboxId = computed(() => props.conversation.inbox_id);
const inbox = computed(() => {
  return store.value.getters['inboxes/getInbox'](inboxId.value) || {};
});

const channelType = computed(() => {
  const ch = props.conversation.meta?.channel || inbox.value.channel_type || '';
  return ch.toLowerCase();
});

// Priority states & helpers
const conversationPriority = computed(() => {
  return (
    props.conversation.priority ||
    props.conversation.custom_attributes?.priority ||
    null
  );
});

const priorityMeta = computed(() => {
  const p = conversationPriority.value;
  switch (p) {
    case 'urgent':
      return {
        label: 'Urgente',
        colorClass: 'bg-rose-500/10 text-rose-400 border-rose-500/30',
        icon: 'i-lucide-alert-triangle',
      };
    case 'high':
      return {
        label: 'Alta',
        colorClass: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
        icon: 'i-lucide-chevron-up',
      };
    case 'medium':
      return {
        label: 'Média',
        colorClass: 'bg-blue-500/10 text-blue-400 border-blue-500/30',
        icon: 'i-lucide-minus',
      };
    case 'low':
      return {
        label: 'Baixa',
        colorClass: 'bg-slate-500/10 text-slate-400 border-slate-700/30',
        icon: 'i-lucide-chevron-down',
      };
    default:
      return null;
  }
});

// Due Date Urgency Logic
const dueDateValue = computed(() => {
  return props.conversation.custom_attributes?.due_date || null;
});

const urgencyMeta = computed(() => {
  const dVal = dueDateValue.value;
  if (!dVal) return null;

  const dueDate = new Date(dVal);
  const today = new Date();

  // Strip time for clean day comparison
  const dDate = new Date(
    dueDate.getFullYear(),
    dueDate.getMonth(),
    dueDate.getDate()
  );
  const tDate = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate()
  );

  const diffDays = Math.floor((dDate - tDate) / (1000 * 60 * 60 * 24));

  if (diffDays < 0) {
    return {
      status: 'overdue',
      label: '⚠️ Vencido',
      badgeClass: 'bg-rose-500/10 text-rose-400 border-rose-500/20',
      borderClass: 'border-rose-500/40 bg-rose-500/[0.02]',
      text: dueDate.toLocaleDateString('pt-BR', {
        day: 'numeric',
        month: 'short',
      }),
    };
  }
  if (diffDays === 0) {
    return {
      status: 'today',
      label: '⚠️ Hoje',
      badgeClass: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      borderClass: 'border-amber-500/40 bg-amber-500/[0.02]',
      text: 'Hoje',
    };
  }
  return {
    status: 'future',
    label: `📅 ${dueDate.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' })}`,
    badgeClass: 'bg-slate-800 text-slate-400 border-slate-700/50',
    borderClass: 'border-slate-800',
    text: dueDate.toLocaleDateString('pt-BR', {
      day: 'numeric',
      month: 'short',
    }),
  };
});

// Channel Style Metas
const channelMeta = computed(() => {
  const ch = channelType.value;
  if (ch.includes('whatsapp')) {
    return {
      icon: 'i-lucide-phone',
      color: 'text-emerald-500',
      name: 'WhatsApp',
    };
  }
  if (ch.includes('email')) {
    return { icon: 'i-lucide-mail', color: 'text-cyan-500', name: 'E-mail' };
  }
  if (ch.includes('instagram')) {
    return {
      icon: 'i-lucide-instagram',
      color: 'text-pink-500',
      name: 'Instagram',
    };
  }
  if (ch.includes('facebook')) {
    return {
      icon: 'i-lucide-facebook',
      color: 'text-blue-600',
      name: 'Facebook',
    };
  }
  if (ch.includes('twitter')) {
    return { icon: 'i-lucide-twitter', color: 'text-sky-400', name: 'Twitter' };
  }
  if (ch.includes('telegram')) {
    return { icon: 'i-lucide-send', color: 'text-sky-500', name: 'Telegram' };
  }
  if (ch.includes('tiktok')) {
    return {
      icon: 'i-lucide-music',
      color: 'text-pink-400',
      name: 'TikTok',
    };
  }
  return { icon: 'i-lucide-globe', color: 'text-slate-400', name: 'Web Chat' };
});

// Last message content
const messageSnippet = computed(() => {
  const msg =
    props.conversation.last_non_activity_message ||
    (props.conversation.messages && props.conversation.messages.length > 0
      ? props.conversation.messages[props.conversation.messages.length - 1]
      : null);
  if (!msg) return 'Sem mensagens';
  const cleanContent = msg.content || '';
  return cleanContent.length > 60
    ? cleanContent.substring(0, 60) + '...'
    : cleanContent;
});

// Quick Actions Implementation
const handleResolve = e => {
  e.stopPropagation();
  emit('resolve', props.conversation.id);
};

const handleAssign = (e, agentId) => {
  e.stopPropagation();
  showAssigneePopover.value = false;
  emit('assign', { conversationId: props.conversation.id, agentId });
};

const handleRemovePipeline = e => {
  e.stopPropagation();
  showMoreMenu.value = false;
  emit('removePipeline', props.conversation.id);
};

const updatePriority = async p => {
  showPriorityPopover.value = false;
  try {
    await store.value.dispatch('conversations/assignPriority', {
      conversationId: props.conversation.id,
      priority: p,
    });
  } catch (err) {
    console.error('Failed to assign priority:', err);
  }
};

const startEditDate = e => {
  e.stopPropagation();
  const dVal = dueDateValue.value;
  if (dVal) {
    editingDateValue.value = new Date(dVal).toISOString().split('T')[0];
  } else {
    editingDateValue.value = '';
  }
  showDateEditor.value = true;
};

const saveDate = async () => {
  const dVal = editingDateValue.value;
  const currentCustomAttributes = {
    ...(props.conversation.custom_attributes || {}),
  };
  if (dVal) {
    const localDate = new Date(dVal + 'T00:00:00');
    currentCustomAttributes.due_date = localDate.toISOString();
  } else {
    delete currentCustomAttributes.due_date;
  }
  try {
    await store.value.dispatch('conversations/updateCustomAttributes', {
      conversationId: props.conversation.id,
      customAttributes: currentCustomAttributes,
    });
  } catch (err) {
    console.error('Failed to update due date:', err);
  }
  showDateEditor.value = false;
};

// Popover closing click outside
const closePopover = () => {
  showPriorityPopover.value = false;
  showAssigneePopover.value = false;
  showMoreMenu.value = false;
  showDateEditor.value = false;
};

// Document click listener for popover
const handleDocumentClick = e => {
  if (
    showPriorityPopover.value &&
    !e.target.closest('.priority-popover-trigger')
  ) {
    showPriorityPopover.value = false;
  }
  if (
    showAssigneePopover.value &&
    !e.target.closest('.assignee-popover-trigger')
  ) {
    showAssigneePopover.value = false;
  }
  if (showMoreMenu.value && !e.target.closest('.more-menu-trigger')) {
    showMoreMenu.value = false;
  }
  if (showDateEditor.value && !e.target.closest('.date-editor-trigger')) {
    showDateEditor.value = false;
  }
};

onMounted(() => {
  document.addEventListener('click', handleDocumentClick);
});

onUnmounted(() => {
  document.removeEventListener('click', handleDocumentClick);
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <div
    class="group relative flex flex-col p-3.5 rounded-xl border bg-slate-900 shadow-md hover:shadow-lg hover:-translate-y-0.5 transition-all duration-200 cursor-grab active:cursor-grabbing hover:border-slate-700/80"
    :class="
      urgencyMeta ? urgencyMeta.borderClass : 'border-slate-850 bg-slate-900/90'
    "
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
    @click="emit('click', props.conversation.id)"
  >
    <!-- Drag Indicator (grip dots, top-left) -->
    <div
      class="absolute top-2 left-2 text-slate-600 opacity-0 group-hover:opacity-100 transition-opacity duration-150"
    >
      <Icon icon="i-lucide-grip-vertical" class="size-3.5" />
    </div>

    <!-- Card Header: Contact Avatar + Name/Channel | Assignee Avatar -->
    <div class="flex items-start justify-between w-full gap-2 pl-4">
      <div class="flex items-center gap-2.5 min-w-0">
        <!-- Avatar with Online Indicator -->
        <div class="relative shrink-0">
          <Thumbnail
            :src="props.conversation.meta?.sender?.thumbnail"
            :username="props.conversation.meta?.sender?.name || 'Cliente'"
            size="28px"
            class="shrink-0 rounded-full"
          />
          <span
            v-if="isOnline"
            class="absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full bg-emerald-500 border-2 border-slate-900"
          />
        </div>

        <div class="flex flex-col min-w-0">
          <span class="text-xs font-bold text-slate-100 truncate">
            {{ props.conversation.meta?.sender?.name || 'Cliente' }}
          </span>

          <!-- Channel Pill (lowercase and dot badge, Image 1 Style) -->
          <div v-if="channelMeta" class="flex items-center gap-1 mt-0.5">
            <span
              :class="channelMeta.color"
              class="flex items-center gap-1 text-[10px] font-semibold opacity-85"
            >
              <span class="size-1.5 rounded-full bg-current shrink-0" />
              <span>{{ channelMeta.name.toLowerCase() }}</span>
            </span>
          </div>
        </div>
      </div>

      <!-- Assignee Thumbnail on the Right (Image 1 Style) -->
      <div class="shrink-0 flex items-center relative assignee-popover-trigger">
        <div
          class="cursor-pointer"
          @click.stop="showAssigneePopover = !showAssigneePopover"
        >
          <Thumbnail
            v-if="props.conversation.meta?.assignee"
            :src="props.conversation.meta?.assignee?.thumbnail"
            :username="props.conversation.meta?.assignee?.name || 'Agente'"
            size="22px"
            class="shrink-0 ring-2 ring-slate-950 rounded-full"
            :title="props.conversation.meta?.assignee?.name"
          />
          <!-- Unassigned Placeholder -->
          <div
            v-else
            class="size-[22px] rounded-full bg-slate-950 flex items-center justify-center border border-dashed border-slate-800 shrink-0 cursor-pointer hover:border-slate-600 transition-colors"
            :title="t('KANBAN.CARD.NO_ASSIGNEE')"
          >
            <Icon icon="i-lucide-user" class="text-slate-600 size-2.5" />
          </div>
        </div>

        <!-- Assignee popover -->
        <div
          v-if="showAssigneePopover"
          class="absolute top-7 right-0 flex flex-col min-w-[140px] bg-slate-900 border border-slate-800 shadow-xl rounded-lg overflow-hidden py-1 z-30 animate-in fade-in slide-in-from-top-1"
        >
          <div
            class="px-3 py-1.5 border-b border-slate-800 text-[10px] uppercase font-bold text-slate-500"
          >
            Atribuir para
          </div>
          <button
            v-for="agent in filteredAgents"
            :key="agent.id"
            type="button"
            class="px-3 py-1.5 text-xs text-left text-slate-300 hover:bg-slate-800 transition-colors flex items-center gap-2"
            :class="{
              'bg-emerald-500/10':
                props.conversation.meta?.assignee?.id === agent.id,
            }"
            @click="handleAssign($event, agent.id)"
          >
            <Thumbnail
              :src="agent.thumbnail"
              :username="agent.name"
              size="16px"
              class="shrink-0 rounded-full"
            />
            <span class="truncate">{{ agent.name }}</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Message Snippet -->
    <p
      class="mt-3 pl-4 text-xs text-slate-400 font-normal leading-relaxed break-words line-clamp-2 min-h-[28px]"
    >
      {{ messageSnippet }}
    </p>

    <!-- Card Footer (Due Date/Priority + Timeago/Date with icons) -->
    <div
      class="flex items-center justify-between mt-3 pt-2.5 border-t border-slate-800/40 pl-4"
    >
      <!-- Left side: Due Date / Priority Badge / Inbox Badge -->
      <div class="flex items-center gap-1.5 min-w-0">
        <!-- Inbox Badge -->
        <span
          v-if="inbox && inbox.name"
          class="px-1.5 py-0.5 bg-slate-950/60 border border-slate-800/60 text-[9px] text-slate-400 font-semibold rounded truncate max-w-[120px]"
          :title="inbox.name"
        >
          {{ inbox.name }}
        </span>

        <!-- Due Date Badges -->
        <div class="relative date-editor-trigger">
          <span
            v-if="urgencyMeta"
            :class="[urgencyMeta.badgeClass]"
            class="px-2 py-0.5 rounded text-[10px] font-semibold border shrink-0 cursor-pointer hover:opacity-80 transition-opacity"
            @click.stop="startEditDate"
          >
            {{ urgencyMeta.label }}
          </span>

          <!-- Inline date editor popover -->
          <div
            v-if="showDateEditor"
            class="absolute top-6 left-0 flex flex-col gap-1.5 bg-slate-900 border border-slate-800 shadow-xl rounded-lg p-2 z-30 min-w-[180px] animate-in fade-in slide-in-from-top-1"
            @click.stop
          >
            <input
              v-model="editingDateValue"
              type="date"
              class="w-full px-2 py-1 rounded border border-slate-700 bg-slate-950 text-slate-200 text-xs outline-none"
            />
            <div class="flex gap-1.5 justify-end">
              <button
                type="button"
                class="px-2 py-0.5 rounded text-[10px] font-semibold text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition-colors"
                @click.stop="showDateEditor = false"
              >
                Cancelar
              </button>
              <button
                type="button"
                class="px-2 py-0.5 rounded text-[10px] font-semibold bg-blue-500 text-white hover:bg-blue-600 transition-colors"
                @click.stop="saveDate"
              >
                Salvar
              </button>
            </div>
          </div>
        </div>

        <!-- Priority Badge -->
        <span
          v-if="priorityMeta"
          :class="[priorityMeta.colorClass]"
          class="px-2 py-0.5 rounded text-[10px] font-semibold border flex items-center gap-1 shrink-0"
        >
          <Icon :icon="priorityMeta.icon" class="size-3 shrink-0" />
          {{ priorityMeta.label }}
        </span>
      </div>

      <!-- Right side: Clock/Calendar Timestamp (Image 1 Style) -->
      <div
        v-if="formattedTimestamp"
        class="flex items-center gap-1 text-[10px] font-semibold text-slate-500 shrink-0"
      >
        <Icon :icon="formattedTimestamp.icon" class="size-3" />
        <span>{{ formattedTimestamp.text }}</span>
      </div>
    </div>

    <!-- Hover Actions (Overlay) -->
    <div
      v-if="isHovered"
      class="absolute top-2 right-2 flex items-center gap-1.5 bg-slate-900 border border-slate-700 shadow-md px-1.5 py-1 rounded-lg z-20 transition-all duration-150"
      @click.stop
    >
      <!-- Quick Priority Selector trigger -->
      <div class="relative priority-popover-trigger">
        <button
          type="button"
          class="p-1 hover:bg-slate-800 rounded text-slate-400 hover:text-slate-200 transition-colors"
          title="Alterar Prioridade"
          @click.stop="showPriorityPopover = !showPriorityPopover"
        >
          <Icon icon="i-lucide-flag" class="size-3.5" />
        </button>

        <!-- Popover list -->
        <div
          v-if="showPriorityPopover"
          class="absolute top-7 right-0 flex flex-col min-w-[100px] bg-slate-900 border border-slate-800 shadow-xl rounded-lg overflow-hidden py-1 z-30 animate-in fade-in slide-in-from-top-1"
        >
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-rose-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('urgent')"
          >
            <Icon icon="i-lucide-alert-triangle" class="size-3" />
            Urgente
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-amber-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('high')"
          >
            <Icon icon="i-lucide-chevron-up" class="size-3" />
            Alta
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-blue-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('medium')"
          >
            <Icon icon="i-lucide-minus" class="size-3" />
            Média
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-slate-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('low')"
          >
            <Icon icon="i-lucide-chevron-down" class="size-3" />
            Baixa
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-slate-500 hover:bg-slate-800 border-t border-slate-850 transition-colors"
            @click="updatePriority(null)"
          >
            Nenhuma
          </button>
        </div>
      </div>

      <!-- "..." More options menu -->
      <div class="relative more-menu-trigger">
        <button
          type="button"
          class="p-1 hover:bg-slate-800 rounded text-slate-400 hover:text-slate-200 transition-colors"
          title="Mais opções"
          @click.stop="showMoreMenu = !showMoreMenu"
        >
          <Icon icon="i-lucide-more-horizontal" class="size-3.5" />
        </button>

        <div
          v-if="showMoreMenu"
          class="absolute top-7 right-0 flex flex-col min-w-[130px] bg-slate-900 border border-slate-800 shadow-xl rounded-lg overflow-hidden py-1 z-30 animate-in fade-in slide-in-from-top-1"
        >
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left text-slate-300 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click.stop="handleRemovePipeline"
          >
            <Icon icon="i-lucide-x-circle" class="size-3 text-rose-400" />
            Remover do funil
          </button>
        </div>
      </div>

      <!-- Quick Resolve (✔) Button -->
      <button
        type="button"
        class="p-1 hover:bg-emerald-500/10 rounded text-slate-400 hover:text-emerald-400 transition-colors"
        title="Resolver Conversa"
        @click.stop="handleResolve"
      >
        <Icon icon="i-lucide-check" class="size-3.5" />
      </button>
    </div>
  </div>
</template>

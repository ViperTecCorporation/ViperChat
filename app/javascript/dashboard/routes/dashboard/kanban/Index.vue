<script setup>
/* eslint-disable no-console, no-restricted-globals, no-alert */
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

// Custom Kanban Components
import KanbanCard from './components/KanbanCard.vue';
import PipelineSettingsModal from './components/PipelineSettingsModal.vue';

// Config Storage Helper
import ConversationApi from 'dashboard/api/conversations';
import { KanbanConfigHelper } from './helpers/kanbanConfig';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();

// State fields
const fullConfig = ref({ pipelines: [] });
const activePipelineId = ref(null);
const configLabelId = ref(null);
const searchQuery = ref('');
const pipelineSearchQuery = ref('');
const filterAgentId = ref('');
const filterInboxId = ref('');
const sortBy = ref('newest');
const showSortDropdown = ref(false);
const showSortLabel = ref('Mais recente');

// Modals
const showSettingsModal = ref(false);
const activeEditingPipeline = ref(null);
const showAddCardPopoverId = ref(null); // ID of the column where "+ Adicionar tarefa" is open

// Load core Chatwoot resources
const allAgents = computed(() => store.getters['agents/getAgents'] || []);
const allInboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const allConversations = computed(
  () => store.getters.getAllConversations || []
);

// Active pipeline
const activePipeline = computed(() => {
  return (
    fullConfig.value.pipelines.find(p => p.id === activePipelineId.value) ||
    null
  );
});

// Load configs from special Label
const loadKanbanConfig = async () => {
  try {
    const { labelId, config } = await KanbanConfigHelper.loadConfig(store);
    fullConfig.value = config;
    configLabelId.value = labelId;

    const queryPipelineId = Number(route.query.pipeline_id);
    if (
      queryPipelineId &&
      config.pipelines.some(p => p.id === queryPipelineId)
    ) {
      activePipelineId.value = queryPipelineId;
    } else {
      activePipelineId.value = null;
    }
  } catch (err) {
    console.error('Failed to load Kanban configurations:', err);
  }
};

watch(
  () => route.query.pipeline_id,
  newId => {
    const parsedId = Number(newId);
    if (parsedId && fullConfig.value.pipelines.some(p => p.id === parsedId)) {
      activePipelineId.value = parsedId;
    } else {
      activePipelineId.value = null;
    }
  }
);

// Overview Helper Methods
const selectPipeline = pipeline => {
  router.push({
    name: 'kanban_dashboard',
    query: { pipeline_id: pipeline.id },
  });
};

const getStageLeadsCount = stage => {
  return allConversations.value.filter(c => c.kanban_stage === stage.id).length;
};

const getPipelineTotalLeads = pipeline => {
  let count = 0;
  pipeline.stages.forEach(stage => {
    count += getStageLeadsCount(stage);
  });
  return count;
};

const filteredPipelines = computed(() => {
  if (!pipelineSearchQuery.value.trim()) return fullConfig.value.pipelines;
  const q = pipelineSearchQuery.value.toLowerCase().trim();
  return fullConfig.value.pipelines.filter(
    p =>
      p.name.toLowerCase().includes(q) ||
      (p.description || '').toLowerCase().includes(q)
  );
});

const getPipelineUniqueAgents = pipeline => {
  const stageIds = pipeline.stages.map(s => s.id);
  const pipelineConversations = allConversations.value.filter(c =>
    stageIds.includes(c.kanban_stage)
  );
  const agentsMap = new Map();
  pipelineConversations.forEach(c => {
    const assignee = c.meta?.assignee;
    if (assignee && assignee.id) {
      agentsMap.set(assignee.id, assignee);
    }
  });
  return Array.from(agentsMap.values());
};

const getPipelineUniqueInboxes = pipeline => {
  const stageIds = pipeline.stages.map(s => s.id);
  const pipelineConversations = allConversations.value.filter(c =>
    stageIds.includes(c.kanban_stage)
  );
  const inboxesMap = new Map();
  pipelineConversations.forEach(c => {
    const inboxId = c.inbox_id;
    if (inboxId) {
      const inbox = allInboxes.value.find(i => i.id === inboxId);
      if (inbox) inboxesMap.set(inboxId, inbox);
    }
  });
  return Array.from(inboxesMap.values());
};

const getInboxChannelMeta = inbox => {
  const ch = (inbox.channel_type || '').toLowerCase();
  if (ch.includes('whatsapp'))
    return {
      icon: 'i-lucide-phone',
      color: 'text-emerald-500',
      name: 'WhatsApp',
    };
  if (ch.includes('email'))
    return { icon: 'i-lucide-mail', color: 'text-cyan-500', name: 'E-mail' };
  if (ch.includes('instagram'))
    return {
      icon: 'i-lucide-instagram',
      color: 'text-pink-500',
      name: 'Instagram',
    };
  if (ch.includes('facebook'))
    return {
      icon: 'i-lucide-facebook',
      color: 'text-blue-600',
      name: 'Facebook',
    };
  if (ch.includes('twitter'))
    return { icon: 'i-lucide-twitter', color: 'text-sky-400', name: 'Twitter' };
  if (ch.includes('telegram'))
    return { icon: 'i-lucide-send', color: 'text-sky-500', name: 'Telegram' };
  return { icon: 'i-lucide-globe', color: 'text-slate-400', name: 'Web Chat' };
};

onMounted(() => {
  // Ensure Chatwoot memory is populated
  store.dispatch('conversations/fetchAllConversations');
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');

  loadKanbanConfig();
});

// Filtered conversations based on Search, Agent, and Inbox select
const filteredConversations = computed(() => {
  let chats = [...allConversations.value];

  // 1. Text Search (ID, customer name, message text)
  if (searchQuery.value.trim()) {
    const q = searchQuery.value.toLowerCase().trim();
    chats = chats.filter(c => {
      const name = (c.meta?.sender?.name || '').toLowerCase();
      const lastMsg = (
        c.last_non_activity_message?.content || ''
      ).toLowerCase();
      const dispId = String(c.display_id || c.id);
      return name.includes(q) || lastMsg.includes(q) || dispId.includes(q);
    });
  }

  // 2. Agent Filter
  if (filterAgentId.value) {
    const agentIdNum = Number(filterAgentId.value);
    chats = chats.filter(c => c.meta?.assignee?.id === agentIdNum);
  }

  // 3. Inbox Filter
  if (filterInboxId.value) {
    const inboxIdNum = Number(filterInboxId.value);
    chats = chats.filter(c => c.inbox_id === inboxIdNum);
  }

  return chats;
});

// Vue Draggable lists map
const columnsCardsMap = ref({});

const syncColumns = () => {
  if (!activePipeline.value) return;

  const newMap = {};
  activePipeline.value.stages.forEach(stage => {
    newMap[stage.id] = [];
  });

  let chats = [...filteredConversations.value];

  // Apply sort
  if (sortBy.value === 'priority') {
    const priorityOrder = { urgent: 0, high: 1, medium: 2, low: 3 };
    chats.sort((a, b) => {
      const pa = priorityOrder[a.priority] ?? 4;
      const pb = priorityOrder[b.priority] ?? 4;
      return pa - pb;
    });
  } else if (sortBy.value === 'due_date') {
    chats.sort((a, b) => {
      const da = a.custom_attributes?.due_date
        ? new Date(a.custom_attributes.due_date)
        : null;
      const db = b.custom_attributes?.due_date
        ? new Date(b.custom_attributes.due_date)
        : null;
      if (!da && !db) return 0;
      if (!da) return 1;
      if (!db) return -1;
      return da - db;
    });
  } else {
    // 'newest' — most recent first
    chats.sort((a, b) => {
      const ta = a.created_at || a.timestamp || 0;
      const tb = b.created_at || b.timestamp || 0;
      return tb - ta;
    });
  }

  // Distribute sorted conversations into stages
  chats.forEach(conversation => {
    const matchedStage = activePipeline.value.stages.find(
      s => s.id === conversation.kanban_stage
    );
    if (matchedStage) {
      newMap[matchedStage.id].push(conversation);
    }
  });

  columnsCardsMap.value = newMap;
};

let skipColumnSync = false;

// Sync lists when chats or active pipeline modifies
watch(
  [filteredConversations, activePipeline],
  () => {
    if (skipColumnSync) return;
    syncColumns();
  },
  { deep: true, immediate: true }
);

// Drag and drop changes handler
const onCardDragChange = async (event, targetStage) => {
  if (event.added) {
    const conversation = event.added.element;

    skipColumnSync = true;
    try {
      await ConversationApi.update(conversation.id, {
        kanban_stage: targetStage.id,
      });
      store.dispatch('updateConversation', {
        id: conversation.id,
        kanban_stage: targetStage.id,
      });

      if (
        activePipeline.value.automations?.auto_resolve_on_won_lost &&
        (targetStage.is_won || targetStage.is_lost)
      ) {
        await store.dispatch('conversations/toggleStatus', {
          conversationId: conversation.id,
          status: 'resolved',
        });
      }
    } catch (err) {
      console.error('Failed to update stage via drag:', err);
    } finally {
      skipColumnSync = false;
    }
  }
};

// Navigation to conversation detail
const openConversation = conversationId => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: store.getters.getCurrentAccountId,
      conversationId: conversationId,
    },
  });
};

// Quick Resolve action inside the card
const resolveConversation = async conversationId => {
  try {
    await store.dispatch('conversations/toggleStatus', {
      conversationId,
      status: 'resolved',
    });
  } catch (err) {
    console.error('Failed to resolve conversation:', err);
  }
};

// Open Modals for Pipeline management
const openAddPipeline = () => {
  activeEditingPipeline.value = null;
  showSettingsModal.value = true;
};

const openEditPipeline = () => {
  activeEditingPipeline.value = activePipeline.value;
  showSettingsModal.value = true;
};

const closeSettingsModal = () => {
  showSettingsModal.value = false;
  activeEditingPipeline.value = null;
};

// Save edited pipeline
const savePipelineConfig = async updatedPipeline => {
  showSettingsModal.value = false;

  const pipelines = [...fullConfig.value.pipelines];
  const existingIndex = pipelines.findIndex(p => p.id === updatedPipeline.id);

  if (existingIndex > -1) {
    pipelines[existingIndex] = updatedPipeline;
  } else {
    pipelines.push(updatedPipeline);
  }

  const newConfig = { pipelines };

  try {
    // 1. Save serialized JSON into hidden label description
    await KanbanConfigHelper.saveConfig(store, configLabelId.value, newConfig);

    // Re-fetch config to refresh states
    await loadKanbanConfig();
    activePipelineId.value = updatedPipeline.id;
  } catch (err) {
    console.error('Failed to save pipeline configuration:', err);
  }
};

// Delete active pipeline
const deleteActivePipeline = async () => {
  if (!activePipeline.value) return;

  const isConfirmed = confirm(t('KANBAN.SETTINGS.DELETE_CONFIRM'));
  if (!isConfirmed) return;

  showSettingsModal.value = false;

  const remainingPipelines = fullConfig.value.pipelines.filter(
    p => p.id !== activePipeline.value.id
  );
  const newConfig = { pipelines: remainingPipelines };

  try {
    await KanbanConfigHelper.saveConfig(store, configLabelId.value, newConfig);
    await loadKanbanConfig();

    if (fullConfig.value.pipelines.length > 0) {
      activePipelineId.value = fullConfig.value.pipelines[0].id;
    } else {
      activePipelineId.value = null;
    }
  } catch (err) {
    console.error('Failed to delete pipeline:', err);
  }
};

// Filter recent conversations that have NO label belonging to this pipeline stages
const eligibleConversationsForInclusion = computed(() => {
  if (!activePipeline.value) return [];

  const stageIds = activePipeline.value.stages.map(s => s.id);
  return allConversations.value.filter(c => {
    const hasPipelineStage =
      c.kanban_stage && stageIds.includes(c.kanban_stage);
    const isOpen = c.status !== 'resolved';
    return !hasPipelineStage && isOpen;
  });
});

// Add task quick action: immediately assigns the conversation to the first stage
const addConversationToStage = async (conversation, stage) => {
  showAddCardPopoverId.value = null;

  try {
    await ConversationApi.update(conversation.id, {
      kanban_stage: stage.id,
    });
    store.dispatch('updateConversation', {
      id: conversation.id,
      kanban_stage: stage.id,
    });
  } catch (err) {
    console.error('Failed to add conversation to stage:', err);
  }
};

// Sort handlers
const sortOptions = [
  { value: 'newest', label: 'Mais recente' },
  { value: 'priority', label: 'Prioridade' },
  { value: 'due_date', label: 'Data de vencimento' },
];

const setSort = option => {
  sortBy.value = option.value;
  showSortLabel.value = option.label;
  showSortDropdown.value = false;
};

const handleAssign = ({ conversationId, agentId }) => {
  store.dispatch('conversations/assignAgent', {
    conversationId,
    agentId,
  });
};

const handleRemovePipeline = async conversationId => {
  try {
    await ConversationApi.update(conversationId, {
      kanban_stage: null,
    });
    store.dispatch('updateConversation', {
      id: conversationId,
      kanban_stage: null,
    });
  } catch (err) {
    console.error('Failed to remove from pipeline:', err);
  }
};

const importOpenConversations = async () => {
  if (!activePipeline.value) return;

  const stageIds = activePipeline.value.stages.map(s => s.id);
  const inboxFilter = activePipeline.value.inboxes || [];

  const eligible = allConversations.value.filter(c => {
    if (c.status === 'resolved') return false;
    if (c.kanban_stage && stageIds.includes(c.kanban_stage)) return false;
    if (inboxFilter.length > 0 && !inboxFilter.includes(c.inbox_id))
      return false;
    return true;
  });

  if (eligible.length === 0) {
    alert('Nenhuma conversa aberta elegível para importar.');
    return;
  }

  const firstStage = activePipeline.value.stages[0];
  if (!firstStage) return;

  const batchSize = 20;
  for (let i = 0; i < eligible.length; i += batchSize) {
    const batch = eligible.slice(i, i + batchSize);
    await Promise.all(
      batch.map(c =>
        ConversationApi.update(c.id, { kanban_stage: firstStage.id }).then(() =>
          store.dispatch('updateConversation', {
            id: c.id,
            kanban_stage: firstStage.id,
          })
        )
      )
    );
  }
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <div
    class="flex flex-col w-full h-full bg-slate-950 font-sans overflow-hidden"
  >
    <!-- 1. Funis Overview (Visão geral) when activePipelineId is null -->
    <div
      v-if="activePipelineId === null"
      class="flex-grow flex flex-col h-full bg-slate-950 p-8 overflow-y-auto"
    >
      <!-- Overview Header -->
      <div
        class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4 mb-8 shrink-0"
      >
        <h2 class="text-2xl font-bold tracking-tight text-slate-100 shrink-0">
          Funis
        </h2>

        <div class="flex items-center gap-2.5">
          <!-- Sleek Filter Icon (Image 1 Style) -->
          <button
            type="button"
            class="p-2 border border-slate-850 hover:border-slate-800 hover:bg-slate-900/50 rounded-xl text-slate-400 hover:text-slate-200 transition-all"
            title="Ordenar / Filtrar"
          >
            <Icon icon="i-lucide-sliders-horizontal" class="size-4 shrink-0" />
          </button>

          <Button
            blue
            class="flex items-center gap-1.5 px-4 py-2 text-sm font-semibold rounded-xl shrink-0"
            @click="openAddPipeline"
          >
            <Icon icon="i-lucide-plus" class="size-4" />
            Adicionar Funil
          </Button>
        </div>
      </div>

      <!-- Funnels List -->
      <div class="flex flex-col gap-5 max-w-5xl">
        <div
          v-for="p in filteredPipelines"
          :key="p.id"
          class="bg-slate-900/60 hover:bg-slate-900 border border-slate-850 hover:border-slate-800 rounded-2xl p-6 transition-all cursor-pointer flex flex-col gap-4 shadow-lg hover:shadow-2xl"
          @click="selectPipeline(p)"
        >
          <!-- Pipeline Header Info -->
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <span class="text-lg font-bold text-slate-200">{{ p.name }}</span>
              <span
                class="px-2.5 py-0.5 rounded-full bg-slate-950 text-xs font-semibold text-slate-400 border border-slate-800"
              >
                {{ getPipelineTotalLeads(p) }}
              </span>
            </div>

            <div class="flex items-center gap-3">
              <!-- Agent placeholder avatars (from the pipeline active leads) -->
              <div class="flex items-center -space-x-2">
                <Thumbnail
                  v-for="agent in getPipelineUniqueAgents(p).slice(0, 4)"
                  :key="agent.id"
                  :src="agent.thumbnail"
                  :username="agent.name"
                  size="26px"
                  class="border-2 border-slate-900 rounded-full shrink-0"
                />
                <span
                  v-if="getPipelineUniqueAgents(p).length > 4"
                  class="size-[26px] rounded-full border-2 border-slate-900 bg-slate-950 text-[10px] font-bold text-slate-400 flex items-center justify-center shrink-0 z-10"
                >
                  +{{ getPipelineUniqueAgents(p).length - 4 }}
                </span>
              </div>

              <!-- Inbox / Channel icons -->
              <div class="flex items-center gap-1">
                <span
                  v-for="inbox in getPipelineUniqueInboxes(p).slice(0, 4)"
                  :key="inbox.id"
                  :class="getInboxChannelMeta(inbox).color"
                  :title="inbox.name"
                  class="shrink-0 p-1 bg-slate-950/60 border border-slate-800 rounded-lg"
                >
                  <Icon
                    :icon="getInboxChannelMeta(inbox).icon"
                    class="size-3.5"
                  />
                </span>
                <span
                  v-if="getPipelineUniqueInboxes(p).length > 4"
                  class="text-[10px] font-bold text-slate-500 ml-1"
                >
                  +{{ getPipelineUniqueInboxes(p).length - 4 }}
                </span>
              </div>
            </div>
          </div>

          <!-- Stages Summary Horizontal Bar -->
          <div class="flex flex-wrap gap-2.5">
            <div
              v-for="stage in p.stages"
              :key="stage.id"
              class="bg-slate-950/70 px-3.5 py-1.5 rounded-full text-xs font-semibold text-slate-300 flex items-center gap-2 border border-slate-850"
            >
              <span
                class="size-2 rounded-full"
                :style="{ backgroundColor: stage.color || '#3b82f6' }"
              />
              <span>{{ stage.title }}</span>
              <span class="text-slate-500 font-bold ml-0.5">{{
                getStageLeadsCount(stage)
              }}</span>
            </div>
          </div>
        </div>

        <div
          v-if="filteredPipelines.length === 0"
          class="flex flex-col items-center justify-center py-20 text-center gap-4 bg-slate-900/20 border border-dashed border-slate-850 rounded-2xl"
        >
          <div class="p-4 bg-slate-900/60 rounded-full text-slate-500">
            <Icon icon="i-lucide-folder-open" class="size-8" />
          </div>
          <div class="flex flex-col gap-1 max-w-sm">
            <h3 class="text-sm font-bold text-slate-300">
              Nenhum funil configurado
            </h3>
            <p class="text-xs text-slate-500 font-medium">
              Crie seu primeiro funil para gerenciar leads, propostas e
              fechamento comercial de forma visual.
            </p>
          </div>
          <Button blue small class="mt-2" @click="openAddPipeline">
            <Icon icon="i-lucide-plus" class="size-3.5" />
            Adicionar Funil
          </Button>
        </div>
      </div>
    </div>

    <!-- 2. Kanban Board (when activePipelineId is NOT null) -->
    <template v-else>
      <!-- Header Top Section (Sleek & Aligned as in Image 1) -->
      <header
        class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4 px-6 py-3 border-b border-slate-900 bg-slate-950 shrink-0"
      >
        <!-- Title & Total Leads count badge (Image 1 Left Side) -->
        <div class="flex items-center gap-2.5">
          <!-- Back button to return to Overview -->
          <button
            type="button"
            class="p-1.5 -ml-1 text-slate-400 hover:text-slate-200 transition-colors bg-slate-900 border border-slate-850 hover:border-slate-800 rounded-xl"
            title="Voltar para Funis"
            @click="activePipelineId = null"
          >
            <Icon icon="i-lucide-chevron-left" class="size-4.5" />
          </button>

          <h2
            class="text-base font-bold tracking-tight text-slate-100 shrink-0"
          >
            {{ activePipeline?.name }}
          </h2>

          <span
            class="px-2 py-0.5 rounded-full bg-slate-900 text-[10px] font-bold text-slate-400 border border-slate-800"
          >
            {{ getPipelineTotalLeads(activePipeline) }}
          </span>
        </div>

        <!-- Filters & Action Buttons (Image 1 Right Side) -->
        <div class="flex flex-wrap items-center gap-2">
          <!-- Live Search Bar (Compact & Sleek with Perfect Centering) -->
          <div class="relative w-44">
            <input
              v-model="searchQuery"
              type="text"
              placeholder="Pesquisar..."
              class="w-full pl-9 pr-3 py-1.5 rounded-xl border border-slate-850 bg-slate-900 text-slate-200 text-xs focus:border-blue-500 outline-none placeholder:text-slate-500"
            />
            <span
              class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none flex items-center"
            >
              <Icon icon="i-lucide-search" class="size-3.5" />
            </span>
          </div>

          <!-- Filter Agents (Compact & Premium) -->
          <div class="relative">
            <select
              v-model="filterAgentId"
              class="pl-7 pr-7 py-1.5 rounded-xl border border-slate-850 bg-slate-900 text-slate-300 text-xs font-semibold outline-none cursor-pointer focus:border-blue-500 appearance-none min-w-[130px]"
            >
              <option value="">Todos os agentes</option>
              <option
                v-for="agent in allAgents"
                :key="agent.id"
                :value="agent.id"
              >
                {{ agent.name }}
              </option>
            </select>
            <span
              class="absolute left-2.5 top-2 text-slate-500 pointer-events-none"
            >
              <Icon icon="i-lucide-user" class="size-3.5" />
            </span>
            <span
              class="absolute right-2.5 top-2.5 text-slate-500 pointer-events-none"
            >
              <Icon icon="i-lucide-chevron-down" class="size-3" />
            </span>
          </div>

          <!-- Filter Inboxes (Compact & Premium) -->
          <div class="relative">
            <select
              v-model="filterInboxId"
              class="pl-7 pr-7 py-1.5 rounded-xl border border-slate-850 bg-slate-900 text-slate-300 text-xs font-semibold outline-none cursor-pointer focus:border-blue-500 appearance-none min-w-[130px]"
            >
              <option value="">Todas as caixas</option>
              <option
                v-for="inbox in allInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
            <span
              class="absolute left-2.5 top-2 text-slate-500 pointer-events-none"
            >
              <Icon icon="i-lucide-inbox" class="size-3.5" />
            </span>
            <span
              class="absolute right-2.5 top-2.5 text-slate-500 pointer-events-none"
            >
              <Icon icon="i-lucide-chevron-down" class="size-3" />
            </span>
          </div>

          <!-- Order Icon with dropdown -->
          <div class="relative">
            <button
              type="button"
              class="p-1.5 border border-slate-850 hover:border-slate-800 hover:bg-slate-900/50 rounded-xl text-slate-400 hover:text-slate-200 transition-all flex items-center gap-1"
              title="Ordenar"
              @click="showSortDropdown = !showSortDropdown"
            >
              <Icon icon="i-lucide-arrow-up-down" class="size-3.5 shrink-0" />
              <span class="text-[10px] font-semibold hidden sm:inline">{{
                showSortLabel
              }}</span>
            </button>
            <div
              v-if="showSortDropdown"
              class="absolute top-9 right-0 flex flex-col min-w-[150px] bg-slate-900 border border-slate-800 shadow-xl rounded-lg overflow-hidden py-1 z-30 animate-in fade-in slide-in-from-top-1"
            >
              <button
                v-for="opt in sortOptions"
                :key="opt.value"
                type="button"
                class="px-3 py-1.5 text-xs text-left font-medium text-slate-300 hover:bg-slate-800 transition-colors"
                :class="{ 'text-blue-400': sortBy === opt.value }"
                @click="setSort(opt)"
              >
                {{ opt.label }}
              </button>
            </div>
          </div>

          <!-- Import conversations button -->
          <button
            type="button"
            class="p-1.5 border border-slate-850 hover:border-slate-800 hover:bg-slate-900/50 rounded-xl text-slate-400 hover:text-slate-200 transition-all"
            title="Importar conversas abertas"
            @click="importOpenConversations"
          >
            <Icon icon="i-lucide-download" class="size-3.5 shrink-0" />
          </button>

          <!-- Edit pipeline settings gear -->
          <button
            type="button"
            class="p-1.5 border border-slate-850 hover:border-slate-800 hover:bg-slate-900/50 rounded-xl text-slate-400 hover:text-slate-200 transition-all"
            title="Configurações do Funil"
            @click="openEditPipeline"
          >
            <Icon icon="i-lucide-settings" class="size-3.5 shrink-0" />
          </button>

          <!-- Add Task Button (Blue block) -->
          <Button
            blue
            class="flex items-center gap-1 px-3 py-1.5 text-xs font-bold rounded-xl shrink-0"
            @click="
              showAddCardPopoverId = activePipeline?.stages[0]?.id || null
            "
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
            Adicionar tarefa
          </Button>
        </div>
      </header>

      <!-- Draggable Stage Board Columns -->
      <main class="flex-grow flex gap-4 p-5 overflow-x-auto overflow-y-hidden">
        <!-- Stage Column -->
        <div
          v-for="stage in activePipeline?.stages"
          :key="stage.id"
          class="group/col flex flex-col flex-1 min-w-[280px] max-w-[550px] shrink-0 bg-slate-900/40 border border-slate-900 rounded-2xl overflow-hidden hover:border-slate-850 transition"
        >
          <!-- Column Header Info (Vibrant Full-Width Solid Colored Header as in Image 1) -->
          <div
            class="flex items-center justify-between px-4 py-3 shrink-0 text-white rounded-t-2xl border-b border-slate-950/40"
            :style="{ backgroundColor: stage.color || '#3b82f6' }"
          >
            <div class="flex items-center gap-2 min-w-0">
              <span class="text-xs font-bold text-white truncate">{{
                stage.title
              }}</span>

              <!-- Total Leads Counter Badge -->
              <span
                class="px-1.5 py-0.5 rounded-full bg-black/25 text-[10px] font-bold text-white/95"
              >
                {{ columnsCardsMap[stage.id]?.length || 0 }}
              </span>
            </div>

            <div class="flex items-center gap-2">
              <!-- Stage Add Card Button -->
              <button
                type="button"
                class="text-white/80 hover:text-white transition-colors"
                title="Adicionar tarefa"
                @click="showAddCardPopoverId = stage.id"
              >
                <Icon icon="i-lucide-plus" class="size-4" />
              </button>
            </div>
          </div>

          <!-- Draggable Cards Container -->
          <div
            class="flex-1 overflow-y-auto px-3.5 py-4 scrollbar-thin scrollbar-thumb-slate-800 scrollbar-track-transparent"
          >
            <Draggable
              v-model="columnsCardsMap[stage.id]"
              group="kanban-conversations"
              item-key="id"
              animation="200"
              ghost-class="bg-slate-950/40 border-dashed border-slate-700 opacity-60 scale-[0.98] rounded-xl"
              drag-class="scale-105 rotate-1 opacity-90 shadow-2xl rounded-xl z-50 cursor-grabbing"
              class="flex flex-col gap-3.5 min-h-[300px] h-full"
              @change="onCardDragChange($event, stage)"
            >
              <template #item="{ element }">
                <KanbanCard
                  :conversation="element"
                  :pipeline-agents="activePipeline?.agents || []"
                  @click="openConversation"
                  @resolve="resolveConversation"
                  @assign="handleAssign"
                  @remove-pipeline="handleRemovePipeline"
                />
              </template>
            </Draggable>
          </div>

          <!-- "+ Adicionar tarefa" Button & Popover -->
          <div class="p-3 border-t border-slate-900/40 shrink-0 relative">
            <button
              type="button"
              class="w-full py-2 px-3 hover:bg-slate-900/50 rounded-lg text-slate-400 hover:text-slate-200 text-xs font-semibold flex items-center justify-center gap-1.5 transition-colors border border-slate-900"
              @click="
                showAddCardPopoverId =
                  showAddCardPopoverId === stage.id ? null : stage.id
              "
            >
              <Icon icon="i-lucide-plus" class="size-4 shrink-0" />
              {{ t('KANBAN.HEADER.ADD_TASK') }}
            </button>

            <!-- Add lead popover drop list -->
            <div
              v-if="showAddCardPopoverId === stage.id"
              class="absolute bottom-12 left-2 right-2 flex flex-col max-h-56 bg-slate-900 border border-slate-800 rounded-xl shadow-2xl overflow-y-auto py-1.5 z-40 animate-in fade-in slide-in-from-bottom-2"
            >
              <div
                class="px-3 py-1.5 border-b border-slate-800 text-[10px] uppercase font-bold text-slate-500"
              >
                Chats recentes sem funil
              </div>

              <button
                v-for="conv in eligibleConversationsForInclusion"
                :key="conv.id"
                type="button"
                class="px-3 py-2 text-left hover:bg-slate-800 text-slate-200 transition-colors flex items-center gap-2"
                @click="addConversationToStage(conv, stage)"
              >
                <Thumbnail
                  :src="conv.meta?.sender?.thumbnail"
                  :username="conv.meta?.sender?.name || 'Cliente'"
                  size="20px"
                  class="shrink-0"
                />
                <div class="flex flex-col min-w-0">
                  <span class="text-xs font-semibold truncate">{{
                    conv.meta?.sender?.name || 'Cliente'
                  }}</span>
                  <span class="text-[9px] text-slate-500 font-mono"
                    >#{{ conv.display_id || conv.id }}</span
                  >
                </div>
              </button>

              <div
                v-if="eligibleConversationsForInclusion.length === 0"
                class="px-4 py-6 text-center text-xs text-slate-500 font-medium leading-relaxed"
              >
                Nenhuma conversa recente elegível encontrada.
              </div>
            </div>
          </div>
        </div>
      </main>
    </template>

    <!-- Pipeline Configurations Settings Modal -->
    <PipelineSettingsModal
      v-if="showSettingsModal"
      :is-open="showSettingsModal"
      :pipeline="activeEditingPipeline"
      :label-id="configLabelId"
      :full-config="fullConfig"
      @close="closeSettingsModal"
      @save="savePipelineConfig"
      @delete="deleteActivePipeline"
    />
  </div>
</template>

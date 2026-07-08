<script setup>
/* eslint-disable no-console, no-use-before-define, no-restricted-syntax */
import { computed, ref, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { KanbanConfigHelper } from '../../../routes/dashboard/kanban/helpers/kanbanConfig';
import ConversationApi from '../../../api/conversations';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = ref(useStore());

const fullConfig = ref({ pipelines: [] });
const activePipelineId = ref(null);
const activeStageId = ref(null);
const stageDropdownOpen = ref(false);

const conversation = computed(() => {
  return store.value.getters.getConversationById(props.conversationId) || {};
});

const detectConversationPipeline = () => {
  const kanbanStage = conversation.value.kanban_stage;

  for (const pipeline of fullConfig.value.pipelines) {
    const match = pipeline.stages.find(s => s.id === kanbanStage);
    if (match) {
      activePipelineId.value = pipeline.id;
      activeStageId.value = match.id;
      return;
    }
  }

  if (fullConfig.value.pipelines.length > 0) {
    activePipelineId.value = fullConfig.value.pipelines[0].id;
  }
  activeStageId.value = null;
};

const activePipeline = computed(() => {
  return (
    fullConfig.value.pipelines.find(p => p.id === activePipelineId.value) ||
    null
  );
});

const currentStage = computed(() => {
  if (!activePipeline.value || !activeStageId.value) return null;
  return (
    activePipeline.value.stages.find(s => s.id === activeStageId.value) || null
  );
});

const loadPipelineConfig = async () => {
  try {
    const { config } = await KanbanConfigHelper.loadConfig(store.value);
    fullConfig.value = config;
    detectConversationPipeline();
  } catch (err) {
    console.error('Failed to load Kanban config for sidebar:', err);
  }
};

onMounted(() => {
  loadPipelineConfig();
});

watch(
  () => props.conversationId,
  () => {
    detectConversationPipeline();
  }
);

const onPipelineChange = () => {
  activeStageId.value = null;
};

const selectStage = async stage => {
  if (!activePipeline.value) return;

  activeStageId.value = stage ? stage.id : null;

  try {
    await ConversationApi.update(props.conversationId, {
      kanban_stage: stage ? stage.id : null,
    });
    store.value.dispatch('updateConversation', {
      id: props.conversationId,
      kanban_stage: stage ? stage.id : null,
    });

    if (stage) {
      handleStageAutomations(stage);
    }
  } catch (err) {
    console.error('Failed to update stage:', err);
  }
};

const handleStageAutomations = async stage => {
  const automations = activePipeline.value.automations || {};

  if (automations.auto_resolve_on_won_lost && (stage.is_won || stage.is_lost)) {
    try {
      await store.value.dispatch('conversations/toggleStatus', {
        conversationId: props.conversationId,
        status: 'resolved',
      });
    } catch (err) {
      console.error('Failed to auto-resolve on stage change:', err);
    }
  }

  if (automations.auto_assign_agent && !conversation.value.meta?.assignee) {
    const agentsList = activePipeline.value.agents || [];
    const allAgents = store.value.getters['agents/getAgents'] || [];

    const onlineAgents = allAgents.filter(
      a => a.availability_status === 'online'
    );
    const eligibleAgents =
      agentsList.length > 0
        ? onlineAgents.filter(a => agentsList.includes(a.id))
        : onlineAgents;

    if (eligibleAgents.length > 0) {
      const agentToAssign =
        eligibleAgents[Math.floor(Math.random() * eligibleAgents.length)];
      try {
        await store.value.dispatch('conversations/assignAgent', {
          conversationId: props.conversationId,
          agentId: agentToAssign.id,
        });
      } catch (err) {
        console.error('Failed to auto-assign agent:', err);
      }
    }
  }
};
</script>

<template>
  <div class="flex flex-col gap-3 py-2 px-1 text-slate-200">
    <div class="flex flex-col gap-1">
      <label
        class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
      >
        {{ t('KANBAN.SIDEBAR.PIPELINE') }}
      </label>
      <select
        v-model="activePipelineId"
        class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
        @change="onPipelineChange"
      >
        <option
          v-for="pipeline in fullConfig.pipelines"
          :key="pipeline.id"
          :value="pipeline.id"
        >
          {{ pipeline.name }}
        </option>
      </select>
    </div>

    <div v-if="activePipeline" class="flex flex-col gap-1">
      <label
        class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
      >
        {{ t('KANBAN.SIDEBAR.STAGE') }}
      </label>
      <div v-on-click-outside="(stageDropdownOpen = false)" class="relative">
        <button
          type="button"
          class="w-full flex items-center gap-2 px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-xs text-slate-200 hover:border-slate-700 transition-all"
          @click="stageDropdownOpen = !stageDropdownOpen"
        >
          <span
            v-if="currentStage"
            class="size-2 rounded-full shrink-0"
            :style="{ backgroundColor: currentStage.color || '#3b82f6' }"
          />
          <span class="flex-1 text-left truncate">
            {{
              currentStage
                ? currentStage.title
                : t('KANBAN.SIDEBAR.NOT_IN_PIPELINE')
            }}
          </span>
          <div class="i-lucide-chevron-down size-3 text-slate-400 shrink-0" />
        </button>
        <div
          v-if="stageDropdownOpen"
          class="absolute z-50 mt-1 w-full rounded-lg border border-slate-700 bg-slate-900 shadow-xl overflow-hidden"
        >
          <button
            type="button"
            class="w-full flex items-center gap-2 px-3 py-2 text-xs text-slate-400 hover:bg-slate-800 transition-colors"
            :class="{ 'bg-slate-800 text-slate-200': activeStageId === null }"
            @click="
              selectStage(null);
              stageDropdownOpen = false;
            "
          >
            {{ t('KANBAN.SIDEBAR.NOT_IN_PIPELINE') }}
          </button>
          <button
            v-for="stage in activePipeline.stages"
            :key="stage.id"
            type="button"
            class="w-full flex items-center gap-2 px-3 py-2 text-xs text-slate-200 hover:bg-slate-800 transition-colors"
            :class="{ 'bg-slate-800': activeStageId === stage.id }"
            @click="
              selectStage(stage);
              stageDropdownOpen = false;
            "
          >
            <span
              class="size-2 rounded-full shrink-0"
              :style="{ backgroundColor: stage.color || '#3b82f6' }"
            />
            {{ stage.title }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

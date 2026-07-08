<script setup>
/* eslint-disable vue/no-unused-properties */
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

const props = defineProps({
  isOpen: {
    type: Boolean,
    required: true,
  },
  pipeline: {
    type: Object,
    default: null,
  },
  labelId: {
    type: [Number, String],
    default: null,
  },
  fullConfig: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close', 'save', 'delete']);

const { t } = useI18n();
const store = useStore();

// Form states
const pipelineId = ref(null);
const name = ref('');
const description = ref('');
const stages = ref([]);
const inboxes = ref([]);
const agents = ref([]);
const automations = ref({
  auto_create: false,
  auto_create_skip_agent: false,
  auto_assign_agent: false,
  auto_assign_conversation: false,
  auto_resolve_on_won_lost: false,
  auto_win_on_resolve: false,
});

const currentStep = ref(props.pipeline ? 'form' : 'select_model');

// Load lists from store
const allInboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const allAgents = computed(() => store.getters['agents/getAgents'] || []);
onMounted(() => {
  // Fetch required dependencies
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');

  if (props.pipeline) {
    // Editing existing pipeline
    pipelineId.value = props.pipeline.id;
    name.value = props.pipeline.name || '';
    description.value = props.pipeline.description || '';
    stages.value = JSON.parse(JSON.stringify(props.pipeline.stages || []));
    inboxes.value = Array.isArray(props.pipeline.inboxes)
      ? [...props.pipeline.inboxes]
      : [];
    agents.value = Array.isArray(props.pipeline.agents)
      ? [...props.pipeline.agents]
      : [];
    automations.value = {
      auto_create: false,
      auto_create_skip_agent: false,
      auto_assign_agent: false,
      auto_assign_conversation: false,
      auto_resolve_on_won_lost: false,
      auto_win_on_resolve: false,
      ...(props.pipeline.automations || {}),
    };
  } else {
    // New pipeline
    pipelineId.value = Date.now();
    name.value = '';
    description.value = '';
    stages.value = [];
    inboxes.value = [];
    agents.value = [];
    automations.value = {
      auto_create: false,
      auto_create_skip_agent: false,
      auto_assign_agent: false,
      auto_assign_conversation: false,
      auto_resolve_on_won_lost: false,
      auto_win_on_resolve: false,
    };
  }
});

const selectModelTemplate = templateType => {
  pipelineId.value = Date.now();

  if (templateType === 'empty') {
    name.value = '';
    description.value = '';
    stages.value = [{ id: 'st_1', title: 'Novo Lead', color: '#3b82f6' }];
  } else if (templateType === 'sales') {
    name.value = t('KANBAN.SETTINGS.SALES_FUNNEL');
    description.value = t('KANBAN.SETTINGS.SALES_FUNNEL_DESC');
    stages.value = [
      { id: 'st_1', title: 'Novo Lead', color: '#3b82f6' },
      { id: 'st_2', title: 'Qualificando', color: '#f59e0b' },
      { id: 'st_3', title: 'Proposta Enviada', color: '#8b5cf6' },
      { id: 'st_4', title: 'Negociação', color: '#f97316' },
      {
        id: 'st_5',
        title: 'Oportunidade Perdida',
        color: '#ef4444',
        is_lost: true,
      },
      {
        id: 'st_6',
        title: 'Oportunidade Ganha',
        color: '#10b981',
        is_won: true,
      },
    ];
  } else if (templateType === 'support') {
    name.value = t('KANBAN.SETTINGS.SUPPORT_FUNNEL');
    description.value = t('KANBAN.SETTINGS.SUPPORT_FUNNEL_DESC');
    stages.value = [
      { id: 'st_1', title: 'Novo Ticket', color: '#3b82f6' },
      { id: 'st_2', title: 'Em Análise', color: '#f59e0b' },
      { id: 'st_3', title: 'Aguardando Cliente', color: '#8b5cf6' },
      { id: 'st_4', title: 'Cancelado', color: '#ef4444', is_lost: true },
      { id: 'st_5', title: 'Resolvido', color: '#10b981', is_won: true },
    ];
  } else if (templateType === 'recruitment') {
    name.value = t('KANBAN.SETTINGS.RECRUITMENT_FUNNEL');
    description.value = t('KANBAN.SETTINGS.RECRUITMENT_FUNNEL_DESC');
    stages.value = [
      { id: 'st_1', title: 'Candidatura', color: '#3b82f6' },
      { id: 'st_2', title: 'Triagem', color: '#f59e0b' },
      { id: 'st_3', title: 'Entrevista', color: '#8b5cf6' },
      { id: 'st_4', title: 'Proposta', color: '#f97316' },
      { id: 'st_5', title: 'Rejeitado', color: '#ef4444', is_lost: true },
      { id: 'st_6', title: 'Contratado', color: '#10b981', is_won: true },
    ];
  }

  inboxes.value = [];
  agents.value = [];
  automations.value = {
    auto_create: false,
    auto_create_skip_agent: false,
    auto_assign_agent: false,
    auto_assign_conversation: false,
    auto_resolve_on_won_lost: false,
    auto_win_on_resolve: false,
  };

  currentStep.value = 'form';
};

// Stage management actions
const addStage = () => {
  const newId = `st_${Date.now()}`;
  stages.value.push({
    id: newId,
    title: `Etapa ${stages.value.length + 1}`,
    color: '#3b82f6',
  });
};

const removeStage = index => {
  stages.value.splice(index, 1);
};

const moveStageUp = index => {
  if (index === 0) return;
  const temp = stages.value[index];
  stages.value[index] = stages.value[index - 1];
  stages.value[index - 1] = temp;
};

const moveStageDown = index => {
  if (index === stages.value.length - 1) return;
  const temp = stages.value[index];
  stages.value[index] = stages.value[index + 1];
  stages.value[index + 1] = temp;
};

const toggleWon = index => {
  stages.value[index].is_won = !stages.value[index].is_won;
  if (stages.value[index].is_won) stages.value[index].is_lost = false;
};

const toggleLost = index => {
  stages.value[index].is_lost = !stages.value[index].is_lost;
  if (stages.value[index].is_lost) stages.value[index].is_won = false;
};

// Toggle selections for inboxes & agents
const toggleInbox = id => {
  const index = inboxes.value.indexOf(id);
  if (index > -1) {
    inboxes.value.splice(index, 1);
  } else {
    inboxes.value.push(id);
  }
};

const toggleAgent = id => {
  const index = agents.value.indexOf(id);
  if (index > -1) {
    agents.value.splice(index, 1);
  } else {
    agents.value.push(id);
  }
};

const handleSave = () => {
  if (!name.value.trim()) return;

  const updatedPipeline = {
    id: pipelineId.value,
    name: name.value.trim(),
    description: description.value.trim(),
    stages: stages.value.map(s => ({
      ...s,
      title: s.title.trim(),
    })),
    inboxes: inboxes.value,
    agents: agents.value,
    automations: automations.value,
  };

  emit('save', updatedPipeline);
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <div
    v-if="isOpen"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm"
  >
    <div
      class="flex flex-col w-full max-w-4xl h-[85vh] border bg-slate-900 border-slate-800 rounded-2xl shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-200"
    >
      <!-- Header -->
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-slate-800"
      >
        <h3
          class="text-lg font-semibold text-slate-100 flex items-center gap-2"
        >
          <Icon
            :icon="
              currentStep === 'select_model'
                ? 'i-lucide-layout-template'
                : 'i-lucide-settings'
            "
            class="text-blue-500 size-5"
          />
          {{
            currentStep === 'select_model'
              ? t('KANBAN.SETTINGS.SELECT_MODEL_TITLE')
              : t('KANBAN.SETTINGS.TITLE')
          }}
        </h3>
        <button
          type="button"
          class="p-1.5 text-slate-400 hover:text-slate-200 rounded-lg hover:bg-slate-800 transition-colors"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-5" />
        </button>
      </div>

      <!-- Content Grid -->
      <div class="flex-1 overflow-y-auto px-6 py-6 space-y-8">
        <template v-if="currentStep === 'select_model'">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 py-4">
            <!-- Funil Vazio -->
            <div
              class="flex flex-col items-start text-left p-6 rounded-2xl border bg-slate-950/40 hover:bg-slate-900 border-slate-800 hover:border-blue-500/50 cursor-pointer transition-all duration-300 group shadow-lg"
              @click="selectModelTemplate('empty')"
            >
              <div
                class="p-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-400 group-hover:text-blue-500 group-hover:border-blue-500/30 group-hover:bg-blue-500/10 transition-colors mb-4"
              >
                <Icon icon="i-lucide-columns" class="size-6" />
              </div>
              <h4
                class="text-base font-semibold text-slate-100 group-hover:text-white transition-colors mb-1"
              >
                {{ t('KANBAN.SETTINGS.EMPTY_FUNNEL') }}
              </h4>
              <p class="text-xs text-slate-400 leading-relaxed">
                {{ t('KANBAN.SETTINGS.EMPTY_FUNNEL_DESC') }}
              </p>
            </div>

            <!-- Pipeline de Vendas -->
            <div
              class="flex flex-col items-start text-left p-6 rounded-2xl border bg-slate-950/40 hover:bg-slate-900 border-slate-800 hover:border-blue-500/50 cursor-pointer transition-all duration-300 group shadow-lg"
              @click="selectModelTemplate('sales')"
            >
              <div
                class="p-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-400 group-hover:text-emerald-500 group-hover:border-emerald-500/30 group-hover:bg-emerald-500/10 transition-colors mb-4"
              >
                <Icon icon="i-lucide-badge-dollar-sign" class="size-6" />
              </div>
              <h4
                class="text-base font-semibold text-slate-100 group-hover:text-white transition-colors mb-1"
              >
                {{ t('KANBAN.SETTINGS.SALES_FUNNEL') }}
              </h4>
              <p class="text-xs text-slate-400 leading-relaxed">
                {{ t('KANBAN.SETTINGS.SALES_FUNNEL_DESC') }}
              </p>
            </div>

            <!-- Suporte -->
            <div
              class="flex flex-col items-start text-left p-6 rounded-2xl border bg-slate-950/40 hover:bg-slate-900 border-slate-800 hover:border-blue-500/50 cursor-pointer transition-all duration-300 group shadow-lg"
              @click="selectModelTemplate('support')"
            >
              <div
                class="p-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-400 group-hover:text-sky-500 group-hover:border-sky-500/30 group-hover:bg-sky-500/10 transition-colors mb-4"
              >
                <Icon icon="i-lucide-headphones" class="size-6" />
              </div>
              <h4
                class="text-base font-semibold text-slate-100 group-hover:text-white transition-colors mb-1"
              >
                {{ t('KANBAN.SETTINGS.SUPPORT_FUNNEL') }}
              </h4>
              <p class="text-xs text-slate-400 leading-relaxed">
                {{ t('KANBAN.SETTINGS.SUPPORT_FUNNEL_DESC') }}
              </p>
            </div>

            <!-- Pipeline de Recrutamento -->
            <div
              class="flex flex-col items-start text-left p-6 rounded-2xl border bg-slate-950/40 hover:bg-slate-900 border-slate-800 hover:border-blue-500/50 cursor-pointer transition-all duration-300 group shadow-lg"
              @click="selectModelTemplate('recruitment')"
            >
              <div
                class="p-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-400 group-hover:text-violet-500 group-hover:border-violet-500/30 group-hover:bg-violet-500/10 transition-colors mb-4"
              >
                <Icon icon="i-lucide-users" class="size-6" />
              </div>
              <h4
                class="text-base font-semibold text-slate-100 group-hover:text-white transition-colors mb-1"
              >
                {{ t('KANBAN.SETTINGS.RECRUITMENT_FUNNEL') }}
              </h4>
              <p class="text-xs text-slate-400 leading-relaxed">
                {{ t('KANBAN.SETTINGS.RECRUITMENT_FUNNEL_DESC') }}
              </p>
            </div>
          </div>
        </template>

        <div v-else class="space-y-8">
          <!-- Basic Info Section -->
          <div class="space-y-4">
            <h4
              class="text-sm font-medium uppercase tracking-wider text-slate-400"
            >
              {{ t('KANBAN.SETTINGS.BASIC_INFO') }}
            </h4>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="space-y-1.5">
                <label class="text-xs font-semibold text-slate-300">
                  {{ t('KANBAN.SETTINGS.FUNNEL_NAME') }} *
                </label>
                <input
                  v-model="name"
                  type="text"
                  class="w-full px-3.5 py-2.5 rounded-lg border border-slate-700 bg-slate-950 text-slate-200 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none"
                  placeholder="Ex: Pipeline de Vendas"
                />
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-semibold text-slate-300">
                  {{ t('KANBAN.SETTINGS.FUNNEL_DESC') }}
                </label>
                <textarea
                  v-model="description"
                  rows="3"
                  class="w-full px-3.5 py-2.5 rounded-lg border border-slate-700 bg-slate-950 text-slate-200 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none resize-none"
                  placeholder="Breve descrição sobre a finalidade do funil"
                />
              </div>
            </div>
          </div>

          <hr class="border-slate-800" />

          <!-- Stages Section -->
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <h4
                class="text-sm font-medium uppercase tracking-wider text-slate-400"
              >
                {{ t('KANBAN.SETTINGS.STAGES') }}
              </h4>
              <Button
                small
                blue
                solid
                class="flex items-center gap-1.5"
                @click="addStage"
              >
                <Icon icon="i-lucide-plus" class="size-4" />
                {{ t('KANBAN.SETTINGS.ADD_STAGE') }}
              </Button>
            </div>

            <div class="space-y-3">
              <div
                v-for="(stage, index) in stages"
                :key="stage.id"
                class="flex flex-col md:flex-row items-stretch md:items-center gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/40 hover:bg-slate-950/60 transition-colors"
              >
                <!-- Order actions -->
                <div
                  class="flex items-center md:flex-col justify-between gap-1.5"
                >
                  <button
                    type="button"
                    class="p-1 text-slate-500 hover:text-slate-300 disabled:opacity-30"
                    :disabled="index === 0"
                    @click="moveStageUp(index)"
                  >
                    <Icon icon="i-lucide-chevron-up" class="size-4 md:size-5" />
                  </button>
                  <button
                    type="button"
                    class="p-1 text-slate-500 hover:text-slate-300 disabled:opacity-30"
                    :disabled="index === stages.length - 1"
                    @click="moveStageDown(index)"
                  >
                    <Icon
                      icon="i-lucide-chevron-down"
                      class="size-4 md:size-5"
                    />
                  </button>
                </div>

                <!-- Title & Mapping -->
                <div class="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div class="space-y-1">
                    <label
                      class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
                    >
                      {{ t('KANBAN.SETTINGS.STAGE_NAME') }}
                    </label>
                    <input
                      v-model="stage.title"
                      type="text"
                      class="w-full px-3 py-1.5 rounded-md border border-slate-700 bg-slate-900 text-slate-200 text-xs focus:border-blue-500 outline-none"
                    />
                  </div>
                  <!-- Color picker -->
                  <div class="space-y-1">
                    <label
                      class="text-[10px] uppercase font-bold tracking-wider text-slate-500 block"
                    >
                      {{ t('KANBAN.SETTINGS.STAGE_COLOR') }}
                    </label>
                    <div class="flex items-center gap-1.5">
                      <input
                        v-model="stage.color"
                        type="color"
                        class="w-8 h-8 rounded border border-slate-700 bg-slate-900 cursor-pointer overflow-hidden p-0"
                      />
                      <span
                        class="text-xs text-slate-400 font-mono uppercase"
                        >{{ stage.color }}</span>
                    </div>
                  </div>
                </div>

                <!-- Status configuration (Won/Lost) -->
                <div class="flex items-center gap-2 pt-4 md:pt-0">
                  <button
                    type="button"
                    class="px-2.5 py-1.5 rounded-md border text-xs font-semibold flex items-center gap-1 transition-all"
                    :class="
                      stage.is_won
                        ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                        : 'border-slate-800 bg-slate-900 text-slate-400 hover:text-slate-300'
                    "
                    @click="toggleWon(index)"
                  >
                    <Icon icon="i-lucide-check-circle" class="size-3.5" />
                    Ganha
                  </button>
                  <button
                    type="button"
                    class="px-2.5 py-1.5 rounded-md border text-xs font-semibold flex items-center gap-1 transition-all"
                    :class="
                      stage.is_lost
                        ? 'border-rose-500/30 bg-rose-500/10 text-rose-400'
                        : 'border-slate-800 bg-slate-900 text-slate-400 hover:text-slate-300'
                    "
                    @click="toggleLost(index)"
                  >
                    <Icon icon="i-lucide-x-circle" class="size-3.5" />
                    Perdida
                  </button>
                </div>

                <!-- Actions -->
                <div class="flex items-center justify-end md:justify-center">
                  <button
                    type="button"
                    class="p-2 text-rose-400 hover:text-rose-300 rounded-lg hover:bg-rose-500/10 transition-colors"
                    @click="removeStage(index)"
                  >
                    <Icon icon="i-lucide-trash-2" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <hr class="border-slate-800" />

          <!-- Automations Section -->
          <div class="space-y-4">
            <div class="space-y-1">
              <h4
                class="text-sm font-medium uppercase tracking-wider text-slate-400"
              >
                {{ t('KANBAN.SETTINGS.AUTOMATIONS') }}
              </h4>
              <p class="text-xs text-slate-500">
                {{ t('KANBAN.SETTINGS.AUTOMATIONS_HELP') }}
              </p>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <!-- Automation Toggle Cards -->
              <div
                class="flex items-start gap-4 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
              >
                <!-- Toggle Switch -->
                <label
                  class="relative inline-flex items-center cursor-pointer mt-0.5 shrink-0"
                >
                  <input
                    v-model="automations.auto_create"
                    type="checkbox"
                    class="sr-only peer"
                  />
                  <div
                    class="w-9 h-5 bg-slate-700 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full"
                  />
                </label>
                <div class="space-y-1.5 flex-1 min-w-0">
                  <label
                    class="text-sm font-medium text-slate-200 cursor-pointer block"
                  >
                    {{ t('KANBAN.SETTINGS.AUTO_CREATE') }}
                  </label>
                  <p class="text-xs text-slate-500">
                    Novas conversas serão colocadas automaticamente na primeira
                    etapa do funil.
                  </p>

                  <!-- Inbox Selector as Chips -->
                  <div v-if="automations.auto_create" class="space-y-2 pt-2">
                    <label
                      class="text-[10px] uppercase font-bold tracking-wider text-slate-500 block"
                    >
                      Filtrar por caixas de entrada (todas se vazio):
                    </label>
                    <!-- Selected inbox chips -->
                    <div
                      v-if="inboxes.length > 0"
                      class="flex flex-wrap gap-1.5 mb-2"
                    >
                      <div
                        v-for="inboxId in inboxes"
                        :key="inboxId"
                        class="flex items-center gap-1 px-2 py-1 rounded-md bg-blue-500/10 border border-blue-500/20 text-blue-400 text-[10px] font-semibold"
                      >
                        <Icon icon="i-lucide-inbox" class="size-3 shrink-0" />
                        <span class="truncate max-w-[80px]">{{
                          allInboxes.find(i => i.id === inboxId)?.name ||
                          inboxId
                        }}</span>
                        <button
                          type="button"
                          class="ml-0.5 hover:text-blue-300 transition-colors"
                          @click="toggleInbox(inboxId)"
                        >
                          <Icon icon="i-lucide-x" class="size-3" />
                        </button>
                      </div>
                    </div>
                    <!-- Inbox selector buttons -->
                    <div
                      class="flex flex-wrap gap-1.5 max-h-32 overflow-y-auto p-1 border border-slate-850 rounded bg-slate-900"
                    >
                      <button
                        v-for="inbox in allInboxes"
                        :key="inbox.id"
                        type="button"
                        class="px-2 py-0.5 rounded text-[10px] font-semibold border transition-all"
                        :class="
                          inboxes.includes(inbox.id)
                            ? 'border-blue-500/30 bg-blue-500/10 text-blue-400'
                            : 'border-slate-800 bg-slate-950 text-slate-400 hover:border-slate-700'
                        "
                        @click="toggleInbox(inbox.id)"
                      >
                        {{ inbox.name }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <div
                class="flex items-start gap-4 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
              >
                <label
                  class="relative inline-flex items-center cursor-pointer mt-0.5 shrink-0"
                >
                  <input
                    v-model="automations.auto_create_skip_agent"
                    type="checkbox"
                    class="sr-only peer"
                  />
                  <div
                    class="w-9 h-5 bg-slate-700 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full"
                  />
                </label>
                <div class="space-y-1.5 flex-1 min-w-0">
                  <label
                    class="text-sm font-medium text-slate-200 cursor-pointer block"
                  >
                    Ignorar se primeira mensagem foi do agente
                  </label>
                  <p class="text-xs text-slate-500">
                    Conversas iniciadas pelo atendente (disparo manual ou
                    campanha) não serão automaticamente adicionadas ao funil.
                  </p>
                </div>
              </div>

              <div
                class="flex items-start gap-4 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
              >
                <label
                  class="relative inline-flex items-center cursor-pointer mt-0.5 shrink-0"
                >
                  <input
                    v-model="automations.auto_assign_agent"
                    type="checkbox"
                    class="sr-only peer"
                  />
                  <div
                    class="w-9 h-5 bg-slate-700 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full"
                  />
                </label>
                <div class="space-y-1.5 flex-1 min-w-0">
                  <label
                    class="text-sm font-medium text-slate-200 cursor-pointer block"
                  >
                    {{ t('KANBAN.SETTINGS.AUTO_ASSIGN_AGENT') }}
                  </label>
                  <p class="text-xs text-slate-500">
                    Cards novos ou sem responsável serão distribuídos entre os
                    agentes selecionados.
                  </p>

                  <!-- Agent Selector as Chips with Avatars -->
                  <div
                    v-if="automations.auto_assign_agent"
                    class="space-y-2 pt-2"
                  >
                    <label
                      class="text-[10px] uppercase font-bold tracking-wider text-slate-500 block"
                    >
                      Agentes elegíveis (todos se vazio):
                    </label>
                    <!-- Selected agent chips -->
                    <div
                      v-if="agents.length > 0"
                      class="flex flex-wrap gap-1.5 mb-2"
                    >
                      <div
                        v-for="agentId in agents"
                        :key="agentId"
                        class="flex items-center gap-1.5 px-2 py-1 rounded-md bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[10px] font-semibold"
                      >
                        <Thumbnail
                          :src="
                            allAgents.find(a => a.id === agentId)?.thumbnail
                          "
                          :username="
                            allAgents.find(a => a.id === agentId)?.name || ''
                          "
                          size="14px"
                          class="shrink-0 rounded-full"
                        />
                        <span class="truncate max-w-[60px]">{{
                          allAgents.find(a => a.id === agentId)?.name || agentId
                        }}</span>
                        <button
                          type="button"
                          class="ml-0.5 hover:text-emerald-300 transition-colors"
                          @click="toggleAgent(agentId)"
                        >
                          <Icon icon="i-lucide-x" class="size-3" />
                        </button>
                      </div>
                    </div>
                    <!-- Agent selector buttons -->
                    <div
                      class="flex flex-wrap gap-1.5 max-h-32 overflow-y-auto p-1 border border-slate-850 rounded bg-slate-900"
                    >
                      <button
                        v-for="agent in allAgents"
                        :key="agent.id"
                        type="button"
                        class="px-2 py-0.5 rounded text-[10px] font-semibold border transition-all flex items-center gap-1"
                        :class="
                          agents.includes(agent.id)
                            ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                            : 'border-slate-800 bg-slate-950 text-slate-400 hover:border-slate-700'
                        "
                        @click="toggleAgent(agent.id)"
                      >
                        <Thumbnail
                          :src="agent.thumbnail"
                          :username="agent.name"
                          size="12px"
                          class="shrink-0 rounded-full"
                        />
                        {{ agent.name }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <div
                class="flex items-start gap-4 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
              >
                <!-- Toggle Switch -->
                <label
                  class="relative inline-flex items-center cursor-pointer mt-0.5 shrink-0"
                >
                  <input
                    v-model="automations.auto_assign_conversation"
                    type="checkbox"
                    class="sr-only peer"
                  />
                  <div
                    class="w-9 h-5 bg-slate-700 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full"
                  />
                </label>
                <div class="space-y-1.5 flex-1 min-w-0">
                  <label
                    class="text-sm font-medium text-slate-200 cursor-pointer block"
                  >
                    {{ t('KANBAN.SETTINGS.AUTO_ASSIGN_CONV') }}
                  </label>
                  <p class="text-xs text-slate-500">
                    Ao alterar o atendente do card no Kanban, a conversa no
                    Chatwoot será atribuída automaticamente a ele.
                  </p>
                </div>
              </div>

              <div
                class="flex items-start gap-4 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
              >
                <!-- Toggle Switch -->
                <label
                  class="relative inline-flex items-center cursor-pointer mt-0.5 shrink-0"
                >
                  <input
                    v-model="automations.auto_resolve_on_won_lost"
                    type="checkbox"
                    class="sr-only peer"
                  />
                  <div
                    class="w-9 h-5 bg-slate-700 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full"
                  />
                </label>
                <div class="space-y-1.5 flex-1 min-w-0">
                  <label
                    class="text-sm font-medium text-slate-200 cursor-pointer block"
                  >
                    {{ t('KANBAN.SETTINGS.AUTO_RESOLVE') }}
                  </label>
                  <p class="text-xs text-slate-500">
                    Mover o card para uma coluna de Ganho/Perda resolverá a
                    conversa correspondente no Chatwoot.
                  </p>
                </div>
              </div>

              <div
                class="flex items-start gap-4 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
              >
                <!-- Toggle Switch -->
                <label
                  class="relative inline-flex items-center cursor-pointer mt-0.5 shrink-0"
                >
                  <input
                    v-model="automations.auto_win_on_resolve"
                    type="checkbox"
                    class="sr-only peer"
                  />
                  <div
                    class="w-9 h-5 bg-slate-700 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-full"
                  />
                </label>
                <div class="space-y-1.5 flex-1 min-w-0">
                  <label
                    class="text-sm font-medium text-slate-200 cursor-pointer block"
                  >
                    {{ t('KANBAN.SETTINGS.AUTO_WIN') }}
                  </label>
                  <p class="text-xs text-slate-500">
                    Quando um atendente marcar a conversa como resolvida no chat
                    convencional, o card será movido para a etapa de "Ganho".
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Footer Actions -->
      <div
        class="flex items-center justify-between px-6 py-4 border-t border-slate-800 bg-slate-950/40"
      >
        <div>
          <Button
            v-if="props.pipeline && currentStep === 'form'"
            small
            red
            class="flex items-center gap-1.5"
            @click="emit('delete')"
          >
            <Icon icon="i-lucide-trash-2" class="size-4" />
            {{ t('KANBAN.SETTINGS.DELETE') }}
          </Button>
        </div>
        <div class="flex items-center gap-3">
          <Button
            md
            class="border border-slate-700 hover:bg-slate-800 text-slate-300"
            @click="
              currentStep === 'form' && !props.pipeline
                ? (currentStep = 'select_model')
                : emit('close')
            "
          >
            <Icon
              v-if="currentStep === 'form' && !props.pipeline"
              icon="i-lucide-arrow-left"
              class="size-4"
            />
            {{
              currentStep === 'form' && !props.pipeline ? 'Voltar' : 'Cancelar'
            }}
          </Button>
          <Button
            v-if="currentStep === 'form'"
            md
            blue
            solid
            :disabled="!name.trim()"
            @click="handleSave"
          >
            <Icon icon="i-lucide-check" class="size-4" />
            {{ t('KANBAN.SETTINGS.SAVE') }}
          </Button>
        </div>
      </div>
    </div>
  </div>
</template>

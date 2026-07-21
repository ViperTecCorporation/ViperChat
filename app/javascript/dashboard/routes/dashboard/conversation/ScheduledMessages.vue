<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { DirectUpload } from 'activestorage';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';

import scheduledMessagesApi from 'dashboard/api/scheduledMessages';
import SearchAPI from 'dashboard/api/search';
import { useAlert } from 'dashboard/composables';
import { setDirectUploadAuthHeaders } from 'dashboard/helper/directUploadsHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import ScheduledMessageCard from './components/ScheduledMessageCard.vue';
import ScheduledMessageSequenceEditor from './components/ScheduledMessageSequenceEditor.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();

const copy = Object.freeze({
  title: 'Agendamentos',
  description: 'Acompanhe e gerencie os próximos envios de WhatsApp.',
  daySummary: 'Resumo do dia',
  filters: 'Filtros',
  board: 'Quadro diário',
  weeklyBoard: 'Quadro semanal',
  automaticRefresh: 'Atualização automática a cada 15 segundos',
  emptyTitle: 'Nenhum agendamento neste dia',
  emptyDescription: 'Altere os filtros ou escolha outra data no calendário.',
  time: 'Hora',
  label: 'Etiqueta',
  agent: 'Operador',
  attachments: 'Anexos',
  deleteTitle: 'Cancelar agendamento?',
  conversation: 'Conversa e contato',
});

const pad = value => String(value).padStart(2, '0');
const toDateKey = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const fromDateKey = value => new Date(`${value}T12:00:00`);
const toDatetimeLocal = date => {
  const timezoneOffset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - timezoneOffset).toISOString().slice(0, 16);
};
const startOfLocalDay = value => new Date(`${value}T00:00:00`);
const startOfWeek = date => {
  const start = new Date(date);
  const offset = (start.getDay() + 6) % 7;
  start.setDate(start.getDate() - offset);
  start.setHours(0, 0, 0, 0);
  return start;
};

const todayKey = toDateKey(new Date());
const selectedDate = ref(todayKey);
const visibleMonth = ref(fromDateKey(todayKey));
const dayItems = ref([]);
const weekItems = ref([]);
const monthItems = ref([]);
const isLoadingDay = ref(false);
const isLoadingWeek = ref(false);
const isLoadingMonth = ref(false);
const isSaving = ref(false);
const isUploading = ref(false);
const editMode = ref('edit');
const boardMode = ref('day');
const editingItem = ref(null);
const deletingItem = ref(null);
const editDialog = ref(null);
const deleteDialog = ref(null);
const selectedConversation = ref(null);
const conversationResults = ref([]);
const conversationPickerOpen = ref(false);
const isSearchingConversation = ref(false);
const isFiltersVisible = ref(false);

const filters = reactive({
  inboxId: '',
  senderId: '',
  labelId: '',
  status: '',
});

const editForm = reactive({
  scheduledAt: '',
  labelId: '',
  reason: '',
  senderId: '',
  messages: [],
});

const currentUser = computed(() => store.getters.getCurrentUser || {});
const accountId = computed(() => Number(route.params.accountId));
const isAdministrator = computed(() => {
  const account = currentUser.value.accounts?.find(
    item => item.id === accountId.value
  );
  return account?.role === 'administrator';
});
const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const agents = computed(() => store.getters['agents/getAgents'] || []);
const labels = computed(() => store.getters['labels/getLabels'] || []);
const activeInbox = computed(() => {
  const inboxId =
    selectedConversation.value?.inbox?.id || editingItem.value?.inbox?.id;
  return inboxes.value.find(inbox => inbox.id === inboxId) || {};
});
const scheduleAudioFormat = computed(() =>
  activeInbox.value.provider === 'whatsapp_cloud'
    ? AUDIO_FORMATS.OGG
    : AUDIO_FORMATS.MP3
);
const scheduleAllowedFileTypes = computed(() =>
  getAllowedFileTypesByChannel({
    channelType: activeInbox.value.channel_type || 'Channel::Whatsapp',
    medium: activeInbox.value.medium,
  })
);
const messagesValid = computed(
  () =>
    editForm.messages.length >= 1 &&
    editForm.messages.length <= 5 &&
    editForm.messages.every(
      message => message.content?.trim() || message.attachments?.length
    )
);

const inboxOptions = computed(() => [
  { value: '', label: 'Todas as caixas' },
  ...inboxes.value
    .filter(inbox => inbox.channel_type === 'Channel::Whatsapp')
    .map(inbox => ({ value: inbox.id, label: inbox.name })),
]);
const agentOptions = computed(() => [
  { value: '', label: 'Todos os operadores' },
  ...agents.value.map(agent => ({ value: agent.id, label: agent.name })),
]);
const labelOptions = computed(() => [
  { value: '', label: 'Todas as etiquetas' },
  ...labels.value.map(label => ({ value: label.id, label: label.title })),
]);
const statusOptions = [
  { value: '', label: 'Todos os estados' },
  { value: 'scheduled', label: 'Agendado' },
  { value: 'sending', label: 'Enviando' },
  { value: 'failed', label: 'Falhou' },
  { value: 'sent', label: 'Enviado' },
  { value: 'cancelled', label: 'Cancelado' },
];

const editLabelOptions = computed(() =>
  labels.value.map(label => ({ value: label.id, label: label.title }))
);
const editAgentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);

const selectedDateLabel = computed(() =>
  new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(fromDateKey(selectedDate.value))
);
const monthLabel = computed(() =>
  new Intl.DateTimeFormat('pt-BR', {
    month: 'long',
    year: 'numeric',
  }).format(visibleMonth.value)
);

const calendarCounts = computed(() =>
  monthItems.value.reduce((counts, item) => {
    const key = toDateKey(new Date(item.scheduled_at));
    counts[key] = (counts[key] || 0) + 1;
    return counts;
  }, {})
);

const calendarDays = computed(() => {
  const year = visibleMonth.value.getFullYear();
  const month = visibleMonth.value.getMonth();
  const firstDay = new Date(year, month, 1);
  const mondayOffset = (firstDay.getDay() + 6) % 7;
  const firstCell = new Date(year, month, 1 - mondayOffset);

  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(firstCell);
    date.setDate(firstCell.getDate() + index);
    const key = toDateKey(date);
    return {
      key,
      day: date.getDate(),
      currentMonth: date.getMonth() === month,
      today: key === todayKey,
      selected: key === selectedDate.value,
      count: calendarCounts.value[key] || 0,
    };
  });
});

const selectedWeekStart = computed(() =>
  startOfWeek(fromDateKey(selectedDate.value))
);
const weekDays = computed(() =>
  Array.from({ length: 7 }, (_, index) => {
    const date = new Date(selectedWeekStart.value);
    date.setDate(date.getDate() + index);
    const key = toDateKey(date);
    return {
      key,
      date,
      day: new Intl.DateTimeFormat('pt-BR', { weekday: 'short' })
        .format(date)
        .replace('.', ''),
      dateLabel: new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      }).format(date),
      today: key === todayKey,
      count: weekItems.value.filter(
        item => toDateKey(new Date(item.scheduled_at)) === key
      ).length,
    };
  })
);
const weekLabel = computed(() => {
  const start = selectedWeekStart.value;
  const end = new Date(start);
  end.setDate(end.getDate() + 6);
  const formatter = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: 'short',
  });
  return `${formatter.format(start)} – ${formatter.format(end)}`;
});

const columns = computed(() => {
  const map = new Map();
  dayItems.value.forEach(item => {
    const label = item.label || { id: 'none', title: 'Sem etiqueta', color: '#6366f1' };
    map.set(label.id, label);
  });
  return [...map.values()];
});

const rows = computed(() => {
  const map = new Map();
  dayItems.value.forEach(item => {
    const date = new Date(item.scheduled_at);
    const key = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    map.set(key, date.getTime());
  });
  return [...map.entries()].sort((left, right) => left[1] - right[1]);
});

const conversationMenuItems = computed(() =>
  conversationResults.value
    .filter(result => result.inbox?.channel_type === 'Channel::Whatsapp')
    .map(result => ({
      value: result.id,
      action: 'select-conversation',
      label: `#${result.id} · ${result.contact?.name || 'Contato'} · ${result.inbox?.name || 'WhatsApp'}`,
      thumbnail: {
        name: result.contact?.name || 'Contato',
        src: result.contact?.thumbnail || '',
      },
      conversation: result,
    }))
);

const summary = computed(() => ({
  total: dayItems.value.length,
  scheduled: dayItems.value.filter(item => item.status === 'scheduled').length,
  sent: dayItems.value.filter(item => item.status === 'sent').length,
  failed: dayItems.value.filter(item => item.status === 'failed').length,
}));

const filterParams = () => ({
  inbox_id: filters.inboxId || undefined,
  sender_id: filters.senderId || undefined,
  label_id: filters.labelId || undefined,
  status: filters.status || undefined,
});

const fetchDay = async () => {
  isLoadingDay.value = true;
  const startAt = startOfLocalDay(selectedDate.value);
  const endAt = new Date(startAt);
  endAt.setDate(endAt.getDate() + 1);
  try {
    const { data } = await scheduledMessagesApi.getForRange({
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      ...filterParams(),
    });
    dayItems.value = data;
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não foi possível carregar a agenda'
    );
  } finally {
    isLoadingDay.value = false;
  }
};

const fetchWeek = async () => {
  isLoadingWeek.value = true;
  const startAt = selectedWeekStart.value;
  const endAt = new Date(startAt);
  endAt.setDate(endAt.getDate() + 7);
  try {
    const { data } = await scheduledMessagesApi.getForRange({
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      ...filterParams(),
    });
    weekItems.value = data;
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não foi possível carregar a semana'
    );
  } finally {
    isLoadingWeek.value = false;
  }
};

const fetchMonth = async () => {
  isLoadingMonth.value = true;
  const startAt = new Date(
    visibleMonth.value.getFullYear(),
    visibleMonth.value.getMonth(),
    1
  );
  const endAt = new Date(startAt.getFullYear(), startAt.getMonth() + 1, 1);
  try {
    const { data } = await scheduledMessagesApi.getForRange({
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      ...filterParams(),
    });
    monthItems.value = data;
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não foi possível carregar o calendário'
    );
  } finally {
    isLoadingMonth.value = false;
  }
};

const refresh = () => Promise.all([fetchDay(), fetchWeek(), fetchMonth()]);
const applyFilters = async () => {
  isFiltersVisible.value = false;
  await refresh();
};

const moveMonth = offset => {
  visibleMonth.value = new Date(
    visibleMonth.value.getFullYear(),
    visibleMonth.value.getMonth() + offset,
    1
  );
  fetchMonth();
};

const selectDay = day => {
  selectedDate.value = day.key;
  const date = fromDateKey(day.key);
  if (
    date.getMonth() !== visibleMonth.value.getMonth() ||
    date.getFullYear() !== visibleMonth.value.getFullYear()
  ) {
    visibleMonth.value = new Date(date.getFullYear(), date.getMonth(), 1);
    fetchMonth();
  }
  fetchDay();
  fetchWeek();
};

const goToday = () => {
  selectedDate.value = todayKey;
  visibleMonth.value = new Date(
    new Date().getFullYear(),
    new Date().getMonth(),
    1
  );
  refresh();
};

const moveWeek = offset => {
  const nextDate = fromDateKey(selectedDate.value);
  nextDate.setDate(nextDate.getDate() + offset * 7);
  selectedDate.value = toDateKey(nextDate);
  visibleMonth.value = new Date(nextDate.getFullYear(), nextDate.getMonth(), 1);
  refresh();
};

const itemsAt = (time, labelId) =>
  dayItems.value.filter(item => {
    const date = new Date(item.scheduled_at);
    const itemLabelId = item.label?.id || 'none';
    return (
      `${pad(date.getHours())}:${pad(date.getMinutes())}` === time &&
      itemLabelId === labelId
    );
  });

const weekItemsForDay = dayKey =>
  weekItems.value
    .filter(item => toDateKey(new Date(item.scheduled_at)) === dayKey)
    .sort(
      (left, right) =>
        new Date(left.scheduled_at).getTime() -
        new Date(right.scheduled_at).getTime()
    );

const scheduledTime = item => {
  const date = new Date(item.scheduled_at);
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const openConversation = item =>
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: item.target_conversation_id || item.conversation_id,
    },
  });

const resetEditForm = (item, retry = false) => {
  const minimumDate = new Date(Date.now() + 300000);
  const currentSchedule = new Date(item.scheduled_at);
  const scheduledDate =
    retry || currentSchedule <= new Date() ? minimumDate : currentSchedule;
  editForm.scheduledAt = toDatetimeLocal(scheduledDate);
  editForm.labelId = item.label?.id || '';
  editForm.reason = item.reason || '';
  editForm.senderId = item.sender.id;
  editForm.messages = (
    item.messages?.length
      ? item.messages
      : [
          {
            content: item.content || '',
            content_type: item.content_type || 'text',
            content_attributes: item.content_attributes || {},
            voice_message: false,
            attachment_blob_ids: item.attachment_blob_ids || [],
          },
        ]
  ).map(message => ({
    id: message.id,
    content: message.content || '',
    content_type: message.content_type || 'text',
    content_attributes: message.content_attributes || {},
    voice_message: Boolean(message.voice_message),
    attachments: (message.attachment_blob_ids || []).map((signedId, index) => ({
      signedId,
      name: `Anexo ${index + 1}`,
      voiceMessage: Boolean(message.voice_message),
    })),
  }));
};

const openEdit = async (item, retry = false) => {
  editingItem.value = item;
  editMode.value = retry ? 'retry' : 'edit';
  resetEditForm(item, retry);
  await nextTick();
  editDialog.value?.open();
};

const openCreate = async () => {
  editingItem.value = null;
  selectedConversation.value = null;
  conversationResults.value = [];
  conversationPickerOpen.value = false;
  editMode.value = 'create';
  editForm.scheduledAt = toDatetimeLocal(new Date(Date.now() + 300000));
  editForm.labelId = labels.value[0]?.id || '';
  editForm.reason = '';
  editForm.senderId = currentUser.value.id;
  editForm.messages = [
    {
      content: '',
      content_type: 'text',
      content_attributes: {},
      voice_message: false,
      attachments: [],
    },
  ];
  await nextTick();
  editDialog.value?.open();
};

let conversationSearchTimer;
const searchConversations = query => {
  window.clearTimeout(conversationSearchTimer);
  if (!query?.trim()) {
    conversationResults.value = [];
    return;
  }
  isSearchingConversation.value = true;
  conversationSearchTimer = window.setTimeout(async () => {
    try {
      const { data } = await SearchAPI.conversations({ q: query.trim() });
      conversationResults.value = data.payload?.conversations || [];
    } catch (error) {
      useAlert(
        error?.response?.data?.error || 'Não foi possível buscar conversas'
      );
    } finally {
      isSearchingConversation.value = false;
    }
  }, 300);
};

const selectConversation = ({ conversation }) => {
  selectedConversation.value = conversation;
  conversationPickerOpen.value = false;
};

const saveEdit = async () => {
  if (!editForm.scheduledAt || !editForm.labelId) return;
  if (editMode.value === 'create' && !selectedConversation.value) return;
  isSaving.value = true;
  try {
    const scheduledMessage = {
      scheduled_at: new Date(editForm.scheduledAt).toISOString(),
      label_id: editForm.labelId,
      reason: editForm.reason,
      sender_id: editForm.senderId,
      messages: editForm.messages.map(message => ({
        content: message.content,
        content_type: message.content_type || 'text',
        content_attributes: message.content_attributes || {},
        voice_message: Boolean(message.voice_message),
        attachment_blob_ids: message.attachments.map(
          attachment => attachment.signedId
        ),
      })),
    };
    if (editMode.value === 'create') {
      await scheduledMessagesApi.create({
        scheduled_message: scheduledMessage,
        conversation_id: selectedConversation.value.id,
      });
      const scheduledDate = new Date(editForm.scheduledAt);
      selectedDate.value = toDateKey(scheduledDate);
      visibleMonth.value = new Date(
        scheduledDate.getFullYear(),
        scheduledDate.getMonth(),
        1
      );
    } else {
      await scheduledMessagesApi.update(editingItem.value.id, {
        scheduled_message: scheduledMessage,
      });
    }
    editDialog.value?.close();
    let successMessage = 'Agendamento atualizado';
    if (editMode.value === 'create') successMessage = 'Mensagem agendada';
    if (editMode.value === 'retry') successMessage = 'Mensagem reagendada';
    useAlert(successMessage);
    await refresh();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não foi possível atualizar o agendamento'
    );
  } finally {
    isSaving.value = false;
  }
};

const askDelete = async item => {
  deletingItem.value = item;
  await nextTick();
  deleteDialog.value?.open();
};

const remove = async () => {
  if (!deletingItem.value) return;
  isSaving.value = true;
  try {
    await scheduledMessagesApi.delete(deletingItem.value.id);
    deleteDialog.value?.close();
    useAlert('Agendamento cancelado');
    await refresh();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não foi possível cancelar o agendamento'
    );
  } finally {
    isSaving.value = false;
  }
};

const uploadAttachment = ({ file, index, voiceMessage }) => {
  if (!file?.file) return;
  isUploading.value = true;
  const upload = new DirectUpload(
    file.file,
    '/rails/active_storage/direct_uploads',
    {
      directUploadWillCreateBlobWithXHR: xhr => {
        if (currentUser.value.access_token) {
          xhr.setRequestHeader(
            'api_access_token',
            currentUser.value.access_token
          );
        } else {
          setDirectUploadAuthHeaders(xhr);
        }
      },
    }
  );

  upload.create((error, blob) => {
    isUploading.value = false;
    if (error) {
      useAlert(error);
      return;
    }
    const message = editForm.messages[index];
    if (!message) return;
    message.attachments.push({
      signedId: blob.signed_id,
      name: blob.filename,
      voiceMessage,
    });
    message.voice_message = message.voice_message || Boolean(voiceMessage);
  });
};

let pollingTimer;
onMounted(async () => {
  await Promise.all([
    store.dispatch('inboxes/get'),
    store.dispatch('agents/get'),
    store.dispatch('labels/get'),
  ]);
  await refresh();
  pollingTimer = window.setInterval(refresh, 15000);
});
onBeforeUnmount(() => {
  isFiltersVisible.value = false;
  window.clearInterval(pollingTimer);
  window.clearTimeout(conversationSearchTimer);
});
</script>

<template>
  <main
    class="flex flex-col flex-1 w-full min-w-0 h-full overflow-auto bg-n-background"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-4 px-6 py-5 border-b border-n-weak bg-n-alpha-3"
    >
      <div class="flex items-center gap-3">
        <div
          class="flex items-center justify-center rounded-xl size-10 bg-n-blue-3 text-n-blue-11"
        >
          <Icon icon="i-lucide-calendar-clock" class="size-5" />
        </div>
        <div>
          <h1 class="mb-0 text-xl font-medium text-n-slate-12">
            {{ copy.title }}
          </h1>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ copy.description }}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <Button
          label="Filtros"
          icon="i-lucide-list-filter"
          color="slate"
          :variant="isFiltersVisible ? 'faded' : 'outline'"
          :aria-expanded="isFiltersVisible"
          @click="isFiltersVisible = !isFiltersVisible"
        />
        <Button
          label="Atualizar"
          icon="i-lucide-refresh-cw"
          color="slate"
          variant="outline"
          :is-loading="isLoadingDay || isLoadingWeek || isLoadingMonth"
          @click="refresh"
        />
        <Button
          label="Novo agendamento"
          icon="i-lucide-plus"
          color="blue"
          @click="openCreate"
        />
      </div>
    </header>

    <div class="flex flex-col w-full min-w-0 gap-5 p-6">
      <section
        v-if="isFiltersVisible"
        class="flex flex-wrap items-center gap-3 p-3 border bg-n-alpha-3 border-n-weak rounded-xl"
      >
        <div
          class="flex items-center gap-2 me-1 text-sm font-medium text-n-slate-12"
        >
          <Icon icon="i-lucide-list-filter" class="size-4" />
          {{ copy.filters }}
        </div>
        <Select v-model="filters.inboxId" :options="inboxOptions" />
        <Select v-model="filters.senderId" :options="agentOptions" />
        <Select v-model="filters.labelId" :options="labelOptions" />
        <Select v-model="filters.status" :options="statusOptions" />
        <Button
          label="Aplicar"
          color="blue"
          variant="faded"
          size="sm"
          @click="applyFilters"
        />
      </section>

      <section
        class="grid grid-cols-1 overflow-hidden border bg-n-alpha-3 border-n-weak rounded-xl xl:grid-cols-[minmax(560px,1fr)_280px]"
      >
        <div class="p-5 border-b border-n-weak xl:border-b-0 xl:border-e">
          <div class="flex items-center justify-between gap-3 mb-4">
            <div class="flex items-center gap-1">
              <Button
                icon="i-lucide-chevron-left"
                color="slate"
                variant="ghost"
                size="sm"
                @click="moveMonth(-1)"
              />
              <Button
                icon="i-lucide-chevron-right"
                color="slate"
                variant="ghost"
                size="sm"
                @click="moveMonth(1)"
              />
              <h2
                class="mb-0 ms-2 text-base font-medium capitalize text-n-slate-12"
              >
                {{ monthLabel }}
              </h2>
            </div>
            <Button
              label="Hoje"
              color="slate"
              variant="outline"
              size="sm"
              @click="goToday"
            />
          </div>

          <div class="grid grid-cols-7 mb-1">
            <span
              v-for="weekday in [
                'Seg',
                'Ter',
                'Qua',
                'Qui',
                'Sex',
                'Sáb',
                'Dom',
              ]"
              :key="weekday"
              class="py-2 text-xs font-medium text-center text-n-slate-10"
            >
              {{ weekday }}
            </span>
          </div>
          <div class="relative grid grid-cols-7 gap-1">
            <button
              v-for="day in calendarDays"
              :key="day.key"
              type="button"
              class="relative flex flex-col items-center justify-center min-h-14 gap-0.5 rounded-lg border transition-colors"
              :class="[
                day.selected
                  ? 'border-n-brand bg-n-blue-3 text-n-blue-11'
                  : 'border-transparent hover:bg-n-alpha-2 text-n-slate-12',
                { 'opacity-35': !day.currentMonth },
              ]"
              @click="selectDay(day)"
            >
              <span
                class="flex items-center justify-center text-sm rounded-full size-7"
                :class="{ 'font-semibold ring-1 ring-n-brand': day.today }"
              >
                {{ day.day }}
              </span>
              <span
                v-if="day.count"
                class="px-1.5 text-[10px] font-medium rounded-full bg-n-blue-4 text-n-blue-11"
              >
                {{ day.count }}
              </span>
            </button>
            <div
              v-if="isLoadingMonth"
              class="absolute inset-0 flex items-center justify-center rounded-lg bg-n-alpha-3/70"
            >
              <Spinner :size="24" />
            </div>
          </div>
        </div>

        <aside class="flex flex-col p-5">
          <p class="mb-1 text-xs font-medium uppercase text-n-slate-10">
            {{ copy.daySummary }}
          </p>
          <h3 class="mb-5 text-base font-medium capitalize text-n-slate-12">
            {{ selectedDateLabel }}
          </h3>
          <div class="grid grid-cols-2 gap-3 xl:grid-cols-1">
            <div
              v-for="metric in [
                {
                  label: 'Total',
                  value: summary.total,
                  icon: 'i-lucide-calendar-days',
                },
                {
                  label: 'Agendados',
                  value: summary.scheduled,
                  icon: 'i-lucide-clock-3',
                },
                {
                  label: 'Enviados',
                  value: summary.sent,
                  icon: 'i-lucide-circle-check',
                },
                {
                  label: 'Falhos',
                  value: summary.failed,
                  icon: 'i-lucide-circle-alert',
                },
              ]"
              :key="metric.label"
              class="flex items-center justify-between gap-3 p-3 rounded-lg bg-n-alpha-2"
            >
              <span class="flex items-center gap-2 text-sm text-n-slate-11">
                <Icon :icon="metric.icon" class="size-4" />
                {{ metric.label }}
              </span>
              <strong class="text-base font-medium text-n-slate-12">
                {{ metric.value }}
              </strong>
            </div>
          </div>
        </aside>
      </section>

      <section class="flex flex-col w-full min-w-0 gap-3">
        <div class="flex items-center justify-between gap-3">
          <div>
            <h2 class="mb-0 text-base font-medium text-n-slate-12">
              {{ boardMode === 'day' ? copy.board : copy.weeklyBoard }}
            </h2>
            <p class="mb-0 text-sm capitalize text-n-slate-11">
              {{ boardMode === 'day' ? selectedDateLabel : weekLabel }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-2">
            <div class="flex items-center p-1 rounded-lg bg-n-alpha-2">
              <Button
                label="Dia"
                color="slate"
                size="xs"
                :variant="boardMode === 'day' ? 'solid' : 'ghost'"
                @click="boardMode = 'day'"
              />
              <Button
                label="Semana"
                color="slate"
                size="xs"
                :variant="boardMode === 'week' ? 'solid' : 'ghost'"
                @click="boardMode = 'week'"
              />
            </div>
            <template v-if="boardMode === 'week'">
              <Button
                icon="i-lucide-chevron-left"
                color="slate"
                variant="outline"
                size="xs"
                @click="moveWeek(-1)"
              />
              <Button
                icon="i-lucide-chevron-right"
                color="slate"
                variant="outline"
                size="xs"
                @click="moveWeek(1)"
              />
            </template>
            <span class="text-xs text-n-slate-10">
              {{ copy.automaticRefresh }}
            </span>
          </div>
        </div>

        <div
          v-if="
            (boardMode === 'day' ? isLoadingDay : isLoadingWeek) &&
            !(boardMode === 'day' ? dayItems.length : weekItems.length)
          "
          class="flex items-center justify-center h-56 border bg-n-alpha-3 border-n-weak rounded-xl"
        >
          <Spinner :size="28" />
        </div>
        <div
          v-else-if="
            !(boardMode === 'day' ? dayItems.length : weekItems.length)
          "
          class="flex flex-col items-center justify-center h-56 gap-3 border bg-n-alpha-3 border-n-weak rounded-xl"
        >
          <div
            class="flex items-center justify-center rounded-full size-12 bg-n-alpha-2 text-n-slate-10"
          >
            <Icon icon="i-lucide-calendar-x-2" class="size-6" />
          </div>
          <div class="text-center">
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ copy.emptyTitle }}
            </p>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ copy.emptyDescription }}
            </p>
          </div>
        </div>
        <div
          v-else-if="boardMode === 'day'"
          class="overflow-auto border bg-n-alpha-3 border-n-weak rounded-xl"
        >
          <div
            class="grid min-w-max"
            :style="{
              gridTemplateColumns: `88px repeat(${columns.length}, minmax(280px, 1fr))`,
            }"
          >
            <div
              class="sticky top-0 z-20 flex items-center px-3 py-3 text-xs font-medium border-b bg-n-alpha-3 border-n-weak text-n-slate-10"
            >
              {{ copy.time }}
            </div>
            <div
              v-for="label in columns"
              :key="label.id"
              class="sticky top-0 z-20 flex items-center gap-2 px-4 py-3 text-sm font-medium border-b border-s bg-n-alpha-3 border-n-weak text-n-slate-12"
              :style="{ boxShadow: `inset 0 3px 0 ${label.color}` }"
            >
              <span
                class="rounded-sm size-2.5"
                :style="{ backgroundColor: label.color }"
              />
              {{ label.title }}
            </div>

            <template v-for="[time] in rows" :key="time">
              <div
                class="px-3 py-4 text-sm font-medium border-b border-n-weak text-n-slate-11"
              >
                {{ time }}
              </div>
              <div
                v-for="label in columns"
                :key="`${time}-${label.id}`"
                class="flex flex-col gap-3 min-h-32 p-3 border-b border-s border-n-weak"
                :style="{ backgroundColor: `${label.color}0A` }"
              >
                <ScheduledMessageCard
                  v-for="item in itemsAt(time, label.id)"
                  :key="item.id"
                  :item="item"
                  @open="openConversation"
                  @edit="openEdit($event)"
                  @retry="openEdit($event, true)"
                  @delete="askDelete"
                />
              </div>
            </template>
          </div>
        </div>
        <div
          v-else
          class="grid w-full min-w-0 grid-cols-1 gap-3 md:grid-cols-2 2xl:grid-cols-4"
        >
          <section
            v-for="day in weekDays"
            :key="day.key"
            class="flex flex-col min-w-0 overflow-hidden border bg-n-alpha-3 border-n-weak rounded-xl"
          >
            <button
              type="button"
              class="flex items-center justify-between gap-3 px-4 py-3 text-start border-b border-n-weak"
              :class="day.today ? 'bg-n-blue-3' : 'bg-n-alpha-2'"
              @click="selectDay({ ...day, currentMonth: true })"
            >
              <span class="flex flex-col">
                <strong class="text-sm font-medium capitalize text-n-slate-12">
                  {{ day.day }}
                </strong>
                <span class="text-xs text-n-slate-11">{{ day.dateLabel }}</span>
              </span>
              <span
                class="px-2 py-1 text-xs font-medium rounded-full bg-n-blue-4 text-n-blue-11"
              >
                {{ day.count }}
              </span>
            </button>

            <div
              v-if="!weekItemsForDay(day.key).length"
              class="flex items-center justify-center flex-1 min-h-28 p-4 text-xs text-center text-n-slate-10"
            >
              {{ copy.emptyTitle }}
            </div>
            <div v-else class="flex flex-col gap-3 p-3">
              <div
                v-for="item in weekItemsForDay(day.key)"
                :key="item.id"
                class="flex flex-col gap-1.5"
              >
                <span
                  class="inline-flex items-center self-start gap-1 px-2 py-1 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
                >
                  <Icon icon="i-lucide-clock-3" class="size-3.5" />
                  {{ scheduledTime(item) }}
                </span>
                <ScheduledMessageCard
                  :item="item"
                  @open="openConversation"
                  @edit="openEdit($event)"
                  @retry="openEdit($event, true)"
                  @delete="askDelete"
                />
              </div>
            </div>
          </section>
        </div>
      </section>
    </div>

    <Dialog
      ref="editDialog"
      :title="
        editMode === 'create'
          ? 'Novo agendamento'
          : editMode === 'retry'
            ? 'Reagendar mensagem'
            : 'Editar agendamento'
      "
      :description="
        editMode === 'create'
          ? 'Escolha a conversa e prepare a mensagem para envio futuro.'
          : 'Atualize a data, a etiqueta e o conteúdo que será enviado.'
      "
      :confirm-button-label="
        editMode === 'create'
          ? 'Agendar mensagem'
          : editMode === 'retry'
            ? 'Reagendar'
            : 'Salvar alterações'
      "
      cancel-button-label="Cancelar"
      width="xl"
      overflow-y-auto
      :is-loading="isSaving"
      :disable-confirm-button="
        !editForm.scheduledAt ||
        !editForm.labelId ||
        isUploading ||
        !messagesValid ||
        (editMode === 'create' && !selectedConversation)
      "
      @confirm="saveEdit"
    >
      <div v-if="editMode === 'create'" class="flex flex-col gap-1">
        <label class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ copy.conversation }}
        </label>
        <div
          v-if="selectedConversation"
          class="flex items-center justify-between gap-3 p-3 rounded-lg bg-n-alpha-2"
        >
          <div class="flex items-center min-w-0 gap-3">
            <Avatar
              :name="selectedConversation.contact?.name || 'Contato'"
              :size="36"
              rounded-full
            />
            <div class="min-w-0">
              <p class="mb-0 text-sm font-medium truncate text-n-slate-12">
                {{ selectedConversation.contact?.name }}
              </p>
              <p class="mb-0 text-xs truncate text-n-slate-11">
                {{
                  `#${selectedConversation.id} · ${selectedConversation.inbox?.name}`
                }}
              </p>
            </div>
          </div>
          <Button
            icon="i-lucide-x"
            color="slate"
            variant="ghost"
            size="xs"
            @click="selectedConversation = null"
          />
        </div>
        <div
          v-else
          v-on-clickaway="() => (conversationPickerOpen = false)"
          class="relative"
        >
          <Button
            label="Selecionar conversa ou contato"
            icon="i-lucide-search"
            trailing-icon
            color="slate"
            variant="outline"
            justify="start"
            class="w-full"
            @click="conversationPickerOpen = !conversationPickerOpen"
          />
          <DropdownMenu
            v-if="conversationPickerOpen"
            :menu-items="conversationMenuItems"
            show-search
            disable-local-filtering
            :is-loading="isSearchingConversation"
            search-placeholder="Pesquise por nome, telefone ou número da conversa"
            class="top-full start-0 z-[100] mt-1 w-full min-w-96"
            @search="searchConversations"
            @action="selectConversation"
          />
        </div>
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="editForm.scheduledAt"
          type="datetime-local"
          label="Data e hora"
          :min="toDatetimeLocal(new Date())"
        />
        <div class="flex flex-col gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ copy.label }}
          </label>
          <Select
            v-model="editForm.labelId"
            :options="editLabelOptions"
            class="!w-full [&_select]:w-full"
          />
        </div>
        <div v-if="isAdministrator" class="flex flex-col gap-1 sm:col-span-2">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ copy.agent }}
          </label>
          <Select
            v-model="editForm.senderId"
            :options="editAgentOptions"
            class="!w-full [&_select]:w-full"
          />
        </div>
      </div>
      <TextArea
        v-model="editForm.reason"
        label="Motivo (opcional)"
        :max-length="500"
        resize
        min-height="4rem"
      />
      <ScheduledMessageSequenceEditor
        v-model="editForm.messages"
        :audio-record-format="scheduleAudioFormat"
        :allowed-file-types="scheduleAllowedFileTypes"
        :conversation-id="
          selectedConversation?.id || editingItem?.conversation_id
        "
        channel-type="Channel::Whatsapp"
        :medium="activeInbox.medium"
        :uploading="isUploading"
        @upload="uploadAttachment"
      />
    </Dialog>

    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="copy.deleteTitle"
      description="A mensagem não será enviada, mas continuará disponível no histórico como cancelada."
      confirm-button-label="Cancelar agendamento"
      cancel-button-label="Voltar"
      :is-loading="isSaving"
      @confirm="remove"
    >
      <div
        v-if="deletingItem"
        class="flex items-center gap-3 p-3 rounded-lg bg-n-alpha-2"
      >
        <Avatar
          :name="deletingItem.contact.name"
          :src="deletingItem.contact.thumbnail"
          :size="36"
          rounded-full
        />
        <div class="min-w-0">
          <p class="mb-0 text-sm font-medium truncate text-n-slate-12">
            {{ deletingItem.contact.name }}
          </p>
          <p class="mb-0 text-xs truncate text-n-slate-11">
            {{ deletingItem.content }}
          </p>
        </div>
      </div>
    </Dialog>
  </main>
</template>

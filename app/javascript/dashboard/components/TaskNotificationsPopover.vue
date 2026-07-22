<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import NotificationsAPI from 'dashboard/api/notifications';
import { useAlert } from 'dashboard/composables';

const router = useRouter();
const store = useStore();
const notificationMeta = useMapGetter('notifications/getMeta');

const isOpen = ref(false);
const tasks = ref([]);
const messages = ref([]);
const mentions = ref([]);
const isLoading = ref(false);
const popoverRef = ref(null);
const buttonRef = ref(null);
const popupRef = ref(null);
const popupStyle = ref({});

const updatePopupPosition = () => {
  if (!buttonRef.value) return;
  const rect = buttonRef.value.getBoundingClientRect();
  popupStyle.value = {
    position: 'fixed',
    top: `${rect.bottom + 8}px`,
    right: `${window.innerWidth - rect.right}px`,
    zIndex: 9999,
    width: '20rem',
    maxHeight: 'calc(100vh - 80px)',
  };
};

const unreadCount = computed(() => {
  if (!notificationMeta.value?.unreadCount) return '';
  return notificationMeta.value.unreadCount < 100
    ? `${notificationMeta.value.unreadCount}`
    : '99+';
});

const formatTimeAgo = dateStr => {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'agora';
  if (mins < 60) return `${mins}min`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  const days = Math.floor(hrs / 24);
  return `${days}d`;
};

const mentionTypes = ['conversation_mention'];
const messageTypes = ['conversation_creation', 'assigned_conversation_new_message', 'participating_conversation_new_message'];
const taskType = 'scheduled_task_due';

const fetchNotifications = async () => {
  isLoading.value = true;
  try {
    const { data } = await NotificationsAPI.get({ page: 1 });
    const all = data?.data?.payload || [];
    tasks.value = all.filter(n => n.notification_type === taskType);
    messages.value = all.filter(n => messageTypes.includes(n.notification_type));
    mentions.value = all.filter(n => mentionTypes.includes(n.notification_type));
  } catch {
    tasks.value = [];
    messages.value = [];
    mentions.value = [];
  } finally {
    isLoading.value = false;
  }
};

const toggle = async () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    await nextTick();
    updatePopupPosition();
    await fetchNotifications();
  }
};

const close = () => {
  isOpen.value = false;
};

const openConversation = notification => {
  const conversationId =
    notification.primary_actor_id || notification.meta?.conversation_id;
  if (conversationId) {
    const accountId = window.location.pathname.split('/')[3];
    router.push({
      name: 'inbox_conversation',
      params: { accountId, conversation_id: conversationId },
    });
  }
  close();
};

const markTaskDone = async (event, notification) => {
  event.stopPropagation();
  try {
    await NotificationsAPI.delete(notification.id);
    tasks.value = tasks.value.filter(n => n.id !== notification.id);
    store.dispatch('notifications/unReadCount');
    useAlert('Tarefa concluída');
  } catch {
    useAlert('Erro ao concluir tarefa');
  }
};

const handleClickOutside = event => {
  if (popoverRef.value && !popoverRef.value.contains(event.target) && !popupRef.value?.contains(event.target)) {
    close();
  }
};

onMounted(() => {
  document.addEventListener('click', handleClickOutside);
});

onBeforeUnmount(() => {
  document.removeEventListener('click', handleClickOutside);
});
</script>

<template>
  <div ref="popoverRef" class="relative">
    <button
      ref="buttonRef"
      class="relative flex items-center justify-center rounded-lg size-7 text-n-slate-11 hover:bg-n-alpha-2"
      :title="$t('SIDEBAR.NOTIFICATIONS')"
      @click="toggle"
    >
      <span class="i-lucide-bell size-4" />
      <span
        v-if="unreadCount"
        class="absolute px-1 py-0.5 min-w-[14px] h-3.5 bg-n-ruby-9 rounded-full -top-1 -right-1 grid place-items-center text-[9px] leading-none text-white font-medium"
      >
        {{ unreadCount }}
      </span>
    </button>

    <Teleport to="body">
    <div
      v-if="isOpen"
      ref="popupRef"
      :style="popupStyle"
      class="bg-n-background border border-n-weak rounded-xl shadow-lg overflow-y-auto"
    >
      <div v-if="isLoading" class="flex items-center justify-center py-10">
        <span class="i-lucide-loader-2 size-5 animate-spin text-n-slate-10" />
      </div>

      <template v-else>
        <div v-if="!tasks.length && !messages.length && !mentions.length" class="px-4 py-6 text-sm text-center text-n-slate-10">
          Nenhuma notificação
        </div>

        <template v-if="tasks.length">
          <div class="px-4 py-3 text-sm font-medium text-n-slate-12 border-b border-n-weak">
            📌 Tarefas Vencidas
          </div>
          <div class="max-h-48 overflow-y-auto">
          <div
            v-for="notification in tasks"
            :key="notification.id"
            class="flex items-start gap-2 px-4 py-3 border-b border-n-weak last:border-b-0 hover:bg-n-alpha-2 transition-colors cursor-pointer"
            @click="openConversation(notification)"
          >
            <div class="flex flex-col flex-1 min-w-0 gap-0.5">
              <div class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ notification.push_message_title || 'Tarefa' }}
                </span>
                <span class="text-xs shrink-0 text-n-slate-10">
                  {{ formatTimeAgo(notification.created_at) }}
                </span>
              </div>
              <p
                v-if="notification.push_message_body"
                class="mb-0 text-xs line-clamp-2 text-n-slate-11"
              >
                {{ notification.push_message_body }}
              </p>
            </div>
            <button
              class="flex items-center justify-center shrink-0 size-6 rounded-md text-n-slate-10 hover:text-n-teal-11 hover:bg-n-teal-3 transition-colors"
              :title="'Concluir'"
              @click="markTaskDone($event, notification)"
            >
              <span class="i-lucide-check size-3.5" />
            </button>
          </div>
        </div>
        </template>

        <!-- Divisória -->
        <div v-if="tasks.length" class="h-px bg-n-weak" />

        <!-- Mensagens -->
        <template v-if="messages.length">
          <div class="px-4 py-2.5 text-xs font-medium text-n-slate-10 border-b border-n-weak">
            💬 Mensagens
          </div>
          <div class="max-h-48 overflow-y-auto">
            <div
              v-for="notification in messages"
              :key="notification.id"
              class="flex items-start gap-2 px-4 py-3 border-b border-n-weak last:border-b-0 hover:bg-n-alpha-2 transition-colors cursor-pointer"
              @click="openConversation(notification)"
            >
              <div class="flex flex-col flex-1 min-w-0 gap-0.5">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-sm font-medium truncate text-n-slate-12">
                    {{ notification.push_message_title || 'Notificação' }}
                  </span>
                  <span class="text-xs shrink-0 text-n-slate-10">
                    {{ formatTimeAgo(notification.created_at) }}
                  </span>
                </div>
                <p
                  v-if="notification.push_message_body"
                  class="mb-0 text-xs line-clamp-2 text-n-slate-11"
                >
                  {{ notification.push_message_body }}
                </p>
              </div>
            </div>
          </div>
        </template>

        <!-- Divisória -->
        <div v-if="messages.length && mentions.length" class="h-px bg-n-weak" />

        <!-- Menções -->
        <template v-if="mentions.length">
          <div class="px-4 py-2.5 text-xs font-medium text-n-slate-10 border-b border-n-weak">
            @ Menções
          </div>
          <div class="max-h-48 overflow-y-auto">
            <div
              v-for="notification in mentions"
              :key="notification.id"
              class="flex items-start gap-2 px-4 py-3 border-b border-n-weak last:border-b-0 hover:bg-n-alpha-2 transition-colors cursor-pointer"
              @click="openConversation(notification)"
            >
              <div class="flex flex-col flex-1 min-w-0 gap-0.5">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-sm font-medium truncate text-n-slate-12">
                    {{ notification.push_message_title || 'Menção' }}
                  </span>
                  <span class="text-xs shrink-0 text-n-slate-10">
                    {{ formatTimeAgo(notification.created_at) }}
                  </span>
                </div>
                <p
                  v-if="notification.push_message_body"
                  class="mb-0 text-xs line-clamp-2 text-n-slate-11"
                >
                  {{ notification.push_message_body }}
                </p>
              </div>
            </div>
          </div>
        </template>
      </template>
    </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import NotificationsAPI from 'dashboard/api/notifications';

const router = useRouter();
const store = useStore();
const notificationMeta = useMapGetter('notifications/getMeta');

const isOpen = ref(false);
const notifications = ref([]);
const isLoading = ref(false);
const popoverRef = ref(null);

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

const fetchTaskNotifications = async () => {
  isLoading.value = true;
  try {
    const { data } = await NotificationsAPI.get({
      type: 'scheduled_task_due',
      page: 1,
    });
    notifications.value = data?.data?.payload || [];
  } catch {
    notifications.value = [];
  } finally {
    isLoading.value = false;
  }
};

const toggle = async () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    await fetchTaskNotifications();
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

const handleClickOutside = event => {
  if (popoverRef.value && !popoverRef.value.contains(event.target)) {
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

    <div
      v-if="isOpen"
      class="absolute z-50 w-80 mt-2 ltr:right-0 rtl:left-0 bg-n-background border border-n-weak rounded-xl shadow-lg overflow-hidden"
    >
      <div class="px-4 py-3 text-sm font-medium border-b border-n-weak text-n-slate-12">
        Tarefas vencidas
      </div>

      <div v-if="isLoading" class="flex items-center justify-center py-8">
        <span class="i-lucide-loader-2 size-5 animate-spin text-n-slate-10" />
      </div>

      <div
        v-else-if="!notifications.length"
        class="py-8 text-sm text-center text-n-slate-10"
      >
        Nenhuma tarefa vencida
      </div>

      <div v-else class="max-h-80 overflow-y-auto">
        <button
          v-for="notification in notifications"
          :key="notification.id"
          class="flex flex-col w-full gap-1 px-4 py-3 text-start border-b border-n-weak last:border-b-0 hover:bg-n-alpha-2 transition-colors"
          @click="openConversation(notification)"
        >
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
        </button>
      </div>
    </div>
  </div>
</template>

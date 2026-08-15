<script setup>
import { computed } from 'vue';

const props = defineProps({
  isCollapsed: { type: Boolean, default: false },
  label: { type: String, required: true },
  to: { type: [String, Object], required: true },
  unreadCount: { type: [Number, String], default: 0 },
});

const emit = defineEmits(['navigate']);

const normalizedUnreadCount = computed(() => {
  const count = Number(props.unreadCount);
  return Number.isFinite(count) && count > 0 ? count : 0;
});

const displayUnreadCount = computed(() =>
  normalizedUnreadCount.value > 99 ? '99+' : String(normalizedUnreadCount.value)
);
</script>

<template>
  <RouterLink
    data-test-id="sidebar-notifications-link"
    :to="to"
    :title="isCollapsed ? label : undefined"
    :aria-label="label"
    class="flex items-center gap-2 rounded-lg p-1 text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 min-w-0"
    :class="isCollapsed ? 'justify-center' : 'w-full'"
    active-class="bg-n-alpha-2 text-n-slate-12"
    @click="emit('navigate')"
  >
    <span class="relative grid size-8 flex-shrink-0 place-content-center">
      <span class="i-lucide-bell size-4" />
      <span
        v-if="isCollapsed && normalizedUnreadCount"
        data-test-id="sidebar-notifications-badge"
        class="absolute -right-1 -top-1 grid min-h-4 min-w-4 place-items-center rounded-full bg-n-ruby-9 px-1 text-[9px] font-medium leading-none text-white"
      >
        {{ displayUnreadCount }}
      </span>
    </span>
    <span
      v-if="!isCollapsed"
      data-test-id="sidebar-notifications-label"
      class="min-w-0 flex-1 truncate text-sm"
    >
      {{ label }}
    </span>
    <span
      v-if="!isCollapsed && normalizedUnreadCount"
      data-test-id="sidebar-notifications-badge"
      class="grid h-5 min-w-5 flex-shrink-0 place-items-center rounded-full bg-n-ruby-9 px-1 text-xxs font-medium leading-3 text-white"
    >
      {{ displayUnreadCount }}
    </span>
  </RouterLink>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import conversationApi from 'dashboard/api/inbox/conversation';
import Avatar from 'next/avatar/Avatar.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const groupContacts = ref([]);
const currentPage = ref(1);
const totalCount = ref(0);
const isLoading = ref(false);

const hasMore = computed(() => groupContacts.value.length < totalCount.value);

const fetchGroupContacts = async ({ reset = false } = {}) => {
  if (isLoading.value) return;

  isLoading.value = true;
  const page = reset ? 1 : currentPage.value;
  try {
    const { data } = await conversationApi.fetchGroupContacts(
      props.conversationId,
      page
    );
    groupContacts.value = reset
      ? data.payload || []
      : [...groupContacts.value, ...(data.payload || [])];
    totalCount.value = data.meta?.count || 0;
    currentPage.value = page + 1;
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => props.conversationId,
  () => fetchGroupContacts({ reset: true })
);

onMounted(() => fetchGroupContacts({ reset: true }));
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="groupContact in groupContacts"
      :key="groupContact.id"
      class="flex items-center gap-2 min-w-0"
    >
      <Avatar
        :name="groupContact.contact.name"
        :src="groupContact.contact.thumbnail"
        :size="24"
        hide-offline-status
      />
      <div class="min-w-0">
        <div class="text-sm text-n-slate-12 truncate">
          {{ groupContact.contact.name }}
        </div>
        <div
          v-if="groupContact.metadata.role"
          class="text-xs text-n-slate-10 truncate"
        >
          {{ groupContact.metadata.role }}
        </div>
      </div>
    </div>
    <button
      v-if="hasMore"
      type="button"
      class="text-sm text-n-brand text-left"
      :disabled="isLoading"
      @click="fetchGroupContacts()"
    >
      {{ $t('CONVERSATION.GROUP.LOAD_MORE') }}
    </button>
  </div>
</template>

<script setup>
import { ref, watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAgentVoipStore } from 'dashboard/stores/agentVoip';
import { VoipAPI } from 'dashboard/api/voip';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({ busy: { type: Boolean, default: false } });
const emit = defineEmits(['transfer']);
const { t } = useI18n();
const { accountId } = useAccount();
const phone = useAgentVoipStore();
const address = ref('');
const search = ref('');
const page = ref(1);
const items = ref([]);
const total = ref(0);
const loading = ref(false);
const error = ref(false);
let version = 0;

async function load() {
  version += 1;
  const current = version;
  items.value = [];
  total.value = 0;
  error.value = false;
  if (!accountId.value || !phone.activeService?.id) return;
  loading.value = true;
  try {
    const { data } = await new VoipAPI(accountId.value).directory({
      service_id: phone.activeService.id,
      kind: 'extensions',
      search: search.value,
      page: page.value,
    });
    if (current !== version) return;
    items.value = data.items.filter(
      entry => entry.address !== phone.activeBinding?.extension
    );
    total.value = data.total;
  } catch {
    if (current === version) error.value = true;
  } finally {
    if (current === version) loading.value = false;
  }
}
watch(
  [search, accountId, () => phone.activeService?.id],
  () => {
    address.value = '';
    if (page.value !== 1) page.value = 1;
    else load();
  },
  { immediate: true }
);
watch(page, load);
onUnmounted(() => {
  version += 1;
});
</script>

<template>
  <section
    class="mt-3 min-w-0 space-y-2"
    :aria-label="t('AGENT_VOIP.TRANSFER')"
  >
    <label class="block text-sm">
      {{ t('AGENT_VOIP.EXTENSIONS') }}
      <input
        v-model="search"
        type="search"
        :placeholder="t('AGENT_VOIP.SEARCH')"
        class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2 text-base"
      />
    </label>
    <p v-if="loading" role="status" class="text-sm">
      {{ t('AGENT_VOIP.LOADING') }}
    </p>
    <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ t('AGENT_VOIP.ERROR') }}
    </p>
    <p v-else-if="!items.length" class="text-sm text-n-slate-11">
      {{ t('AGENT_VOIP.NO_EXTENSIONS') }}
    </p>
    <ul v-else class="max-h-40 space-y-1 overflow-y-auto">
      <li v-for="entry in items" :key="entry.id">
        <button
          type="button"
          :disabled="busy"
          :aria-pressed="address === entry.address"
          class="flex min-h-11 w-full min-w-0 items-center gap-2 rounded-lg p-2 text-left hover:bg-n-alpha-2 disabled:opacity-50"
          @click="address = entry.address"
        >
          <Avatar
            :name="entry.name"
            :src="entry.avatar_url || ''"
            :size="32"
            rounded-full
          />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm">{{ entry.name }}</span>
            <span class="block text-xs text-n-slate-11">{{
              entry.address
            }}</span>
          </span>
          <span
            v-if="address === entry.address"
            class="i-lucide-check block size-5 shrink-0 text-n-brand"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>
    <nav
      v-if="total > 15"
      class="flex justify-end gap-2"
      :aria-label="t('AGENT_VOIP.PAGES')"
    >
      <button
        type="button"
        :disabled="loading || page <= 1"
        :aria-label="t('AGENT_VOIP.PREVIOUS')"
        class="flex size-11 items-center justify-center rounded-full disabled:opacity-40"
        @click="page -= 1"
      >
        <span class="i-lucide-chevron-left block size-5" aria-hidden="true" />
      </button>
      <span class="self-center text-sm">{{
        `${page} / ${Math.ceil(total / 15)}`
      }}</span>
      <button
        type="button"
        :disabled="loading || page * 15 >= total"
        :aria-label="t('AGENT_VOIP.NEXT')"
        class="flex size-11 items-center justify-center rounded-full disabled:opacity-40"
        @click="page += 1"
      >
        <span class="i-lucide-chevron-right block size-5" aria-hidden="true" />
      </button>
    </nav>
    <form
      class="flex min-w-0 gap-2"
      @submit.prevent="emit('transfer', address.trim())"
    >
      <label class="min-w-0 flex-1 text-sm">
        {{ t('AGENT_VOIP.EXTENSION') }}
        <input
          v-model="address"
          required
          autocomplete="off"
          :disabled="busy"
          class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-surface-2 p-2 text-base"
        />
      </label>
      <button
        type="submit"
        :disabled="busy || !address.trim()"
        :aria-label="t('AGENT_VOIP.TRANSFER')"
        :title="t('AGENT_VOIP.TRANSFER')"
        class="flex size-11 shrink-0 self-end items-center justify-center rounded-full bg-n-alpha-2 disabled:opacity-50"
      >
        <span
          class="i-lucide-phone-forwarded block size-5"
          aria-hidden="true"
        />
      </button>
    </form>
  </section>
</template>

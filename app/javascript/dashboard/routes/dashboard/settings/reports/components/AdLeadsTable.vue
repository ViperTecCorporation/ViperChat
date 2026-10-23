<script setup>
import { computed, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  leads: { type: Array, default: () => [] },
  timezone: { type: String, default: 'UTC' },
});
const search = ref('');
const source = ref('');
const provider = ref('');
const inbox = ref('');
const state = ref('');
const page = ref(1);
const inboxes = computed(() => [
  ...new Map(
    props.leads.map(lead => [
      lead.inbox_id,
      lead.inbox_name || String(lead.inbox_id),
    ])
  ).entries(),
]);
const filtered = computed(() =>
  props.leads.filter(lead => {
    const query = search.value.trim().toLocaleLowerCase();
    return (
      (!query ||
        `${lead.contact_name || ''} ${lead.contact_phone || ''} ${lead.contact_id}`
          .toLocaleLowerCase()
          .includes(query)) &&
      (!source.value ||
        String(lead.ad_source_id || '').includes(source.value.trim())) &&
      (!provider.value ||
        (lead.received_providers || [lead.provider]).includes(
          provider.value
        )) &&
      (!inbox.value || String(lead.inbox_id) === inbox.value) &&
      (!state.value || lead.state === state.value)
    );
  })
);
const contacts = computed(
  () => new Set(filtered.value.map(lead => lead.contact_id)).size
);
const pages = computed(() =>
  Math.max(1, Math.ceil(filtered.value.length / 10))
);
const visible = computed(() =>
  filtered.value.slice((page.value - 1) * 10, page.value * 10)
);
watch([search, source, provider, inbox, state, () => props.leads], () => {
  page.value = 1;
});
const date = value =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        timeZone: props.timezone,
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : '—';
</script>

<template>
  <section class="rounded-xl border border-n-weak p-4 min-w-0">
    <h3 class="text-base">{{ $t('PARTNER_REPORT.AD_LEADS') }}</h3>
    <p class="text-sm">
      {{
        $t('PARTNER_REPORT.AD_LEAD_COUNT', {
          contacts,
          entries: filtered.length,
        })
      }}
    </p>
    <p class="text-xs text-n-slate-11">
      {{ $t('PARTNER_REPORT.AD_LEAD_HELP') }}
    </p>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-4">
      <label class="text-sm min-w-0">
        {{ $t('PARTNER_REPORT.AD_SEARCH') }}
        <input v-model="search" type="search" class="!m-0 w-full" />
      </label>
      <label class="text-sm min-w-0">
        {{ $t('PARTNER_REPORT.AD_SOURCE') }}
        <input v-model="source" type="search" class="!m-0 w-full" />
      </label>
      <label class="text-sm min-w-0"
        >{{ $t('PARTNER_REPORT.PROVIDER')
        }}<select v-model="provider" class="!m-0 w-full">
          <option value="">{{ $t('PARTNER_REPORT.AD_ALL') }}</option>
          <option
            v-for="item in ['whatsapp_cloud', 'unoapi', 'unknown']"
            :key="item"
            :value="item"
          >
            {{ $t(`PARTNER_REPORT.PROVIDERS.${item}`) }}
          </option>
        </select></label
      >
      <label class="text-sm min-w-0"
        >{{ $t('PARTNER_REPORT.AD_INBOX')
        }}<select v-model="inbox" class="!m-0 w-full">
          <option value="">{{ $t('PARTNER_REPORT.AD_ALL') }}</option>
          <option v-for="[id, name] in inboxes" :key="id" :value="String(id)">
            {{ name }}
          </option>
        </select></label
      >
      <label class="text-sm min-w-0"
        >{{ $t('PARTNER_REPORT.AD_STATE')
        }}<select v-model="state" class="!m-0 w-full">
          <option value="">{{ $t('PARTNER_REPORT.AD_ALL') }}</option>
          <option
            v-for="item in [
              'active',
              'expired',
              'awaiting_response',
              'no_eligible_response',
            ]"
            :key="item"
            :value="item"
          >
            {{ $t(`PARTNER_REPORT.AD_STATES.${item}`) }}
          </option>
        </select></label
      >
    </div>
    <p v-if="!visible.length" class="text-sm">
      {{ $t('PARTNER_REPORT.AD_EMPTY') }}
    </p>
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
      <article
        v-for="lead in visible"
        :key="`${lead.business_phone}-${lead.message_id}`"
        class="rounded-lg bg-n-alpha-2 p-3 min-w-0 text-sm break-words"
      >
        <strong>{{
          lead.contact_name || lead.contact_phone || lead.contact_id
        }}</strong>
        <p>
          {{ lead.contact_phone }} · {{ lead.inbox_name }} ·
          {{ lead.business_phone }}
        </p>
        <p>
          {{ $t('PARTNER_REPORT.AD_SOURCE') }}: {{ lead.ad_source_id }} ·
          {{ $t('PARTNER_REPORT.REFERRALS') }}: {{ date(lead.received_at) }}
        </p>
        <p>{{ $t(`PARTNER_REPORT.AD_STATES.${lead.state}`) }}</p>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div>
            <dt>{{ $t('PARTNER_REPORT.AD_START') }}</dt>
            <dd class="m-0">{{ date(lead.window_start) }}</dd>
          </div>
          <div>
            <dt>{{ $t('PARTNER_REPORT.AD_END') }}</dt>
            <dd class="m-0">{{ date(lead.window_end) }}</dd>
          </div>
          <div>
            <dt>{{ $t('PARTNER_REPORT.AD_DAYS_ESTIMATED') }}</dt>
            <dd class="m-0">{{ lead.window_days || 0 }}</dd>
          </div>
          <div>
            <dt>{{ $t('PARTNER_REPORT.AD_ELAPSED') }}</dt>
            <dd class="m-0">{{ lead.exempt_days_elapsed }}</dd>
          </div>
          <div>
            <dt>{{ $t('PARTNER_REPORT.AD_FREE_MESSAGES') }}</dt>
            <dd class="m-0">{{ lead.free_meta_messages }}</dd>
          </div>
        </dl>
      </article>
    </div>
    <div class="flex items-center gap-3 justify-center mt-4">
      <Button
        icon="i-lucide-chevron-left"
        :label="$t('PARTNER_REPORT.AD_PREVIOUS')"
        :disabled="page <= 1"
        @click="page--"
      />
      <span class="text-sm">{{ page }} / {{ pages }}</span>
      <Button
        icon="i-lucide-chevron-right"
        :label="$t('PARTNER_REPORT.AD_NEXT')"
        :disabled="page >= pages"
        @click="page++"
      />
    </div>
  </section>
</template>

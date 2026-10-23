<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const period = ref('30');
const from = ref('');
const to = ref('');
const timezone = ref('');
const linkId = ref('');
const currency = ref('BRL');
const adDays = ref('7');
const rates = ref({
  service: '',
  utility: '',
  marketing: '',
  authentication: '',
});
const result = ref(null);
const busy = ref(false);
const error = ref('');
const providers = ['whatsapp_cloud', 'unoapi', 'unknown'];
const metrics = [
  'free_allowance',
  'free_ad',
  'free_customer_window',
  'chargeable',
  'unclassified',
  'unpriced',
];
const fieldsClass = 'w-full min-w-0 !m-0';
const cost = computed(() => {
  if (!result.value?.simulation) return '';
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: currency.value,
    maximumFractionDigits: 4,
  }).format(Number(result.value.simulation.estimated_cost));
});

function setDates() {
  if (period.value === 'custom') return;
  let date;
  try {
    date = new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone.value || 'UTC',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());
  } catch {
    return;
  }
  to.value = date;
  const start = new Date(`${date}T00:00:00Z`);
  start.setUTCDate(start.getUTCDate() - Number(period.value) + 1);
  from.value = start.toISOString().slice(0, 10);
}

async function update() {
  if (busy.value) return;
  setDates();
  busy.value = true;
  error.value = '';
  result.value = null;
  try {
    const { data } = await ReportsAPI.getPartnerInboxes({
      from: from.value,
      to: to.value,
      timezone: timezone.value || undefined,
      link_id: linkId.value || undefined,
      ad_window_days: adDays.value,
      ...Object.fromEntries(
        Object.entries(rates.value).map(([key, value]) => [
          `${key}_rate`,
          value,
        ])
      ),
    });
    result.value = data;
  } catch (exception) {
    const code = exception.response?.data?.error;
    const known = [
      'invalid_timezone',
      'invalid_period',
      'invalid_parameters',
      'invalid_rate',
      'invalid_ad_window',
      'period_too_large',
    ];
    error.value = t(
      known.includes(code)
        ? `PARTNER_REPORT.ERRORS.${code}`
        : 'PARTNER_REPORT.ERROR'
    );
  } finally {
    busy.value = false;
  }
}

onMounted(update);
</script>

<template>
  <ReportHeader
    :header-title="$t('PARTNER_REPORT.TITLE')"
    :header-description="$t('PARTNER_REPORT.DESCRIPTION')"
  />
  <form class="flex flex-col gap-4 min-w-0" @submit.prevent="update">
    <fieldset
      :disabled="busy"
      class="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
    >
      <label class="min-w-0 text-sm">
        {{ $t('PARTNER_REPORT.PERIOD') }}
        <select v-model="period" :class="fieldsClass" @change="setDates">
          <option
            v-for="days in [30, 21, 14, 7]"
            :key="days"
            :value="String(days)"
          >
            {{ $t('PARTNER_REPORT.DAYS', { count: days }) }}
          </option>
          <option value="custom">{{ $t('PARTNER_REPORT.CUSTOM') }}</option>
        </select>
      </label>
      <label class="min-w-0 text-sm">
        {{ $t('PARTNER_REPORT.FROM') }}
        <input
          v-model="from"
          required
          type="date"
          :disabled="period !== 'custom'"
          :class="fieldsClass"
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ $t('PARTNER_REPORT.TO') }}
        <input
          v-model="to"
          required
          type="date"
          :min="from"
          :disabled="period !== 'custom'"
          :class="fieldsClass"
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ $t('PARTNER_REPORT.PAIR') }}
        <select v-model="linkId" :class="fieldsClass">
          <option value="">{{ $t('PARTNER_REPORT.ALL') }}</option>
          <option
            v-for="pair in result?.available_pairs || []"
            :key="pair.id"
            :value="String(pair.id)"
          >
            {{
              $t('PARTNER_REPORT.PAIR_NAME', {
                name: pair.name,
                partner: pair.partner_name,
              })
            }}
          </option>
        </select>
      </label>
      <label class="min-w-0 text-sm sm:col-span-2">
        {{ $t('PARTNER_REPORT.TIMEZONE') }}
        <input
          v-model="timezone"
          type="text"
          :class="fieldsClass"
          @change="setDates"
        />
        <span class="text-xs text-n-slate-11 block mt-1">{{
          $t('PARTNER_REPORT.TIMEZONE_HELP')
        }}</span>
      </label>
    </fieldset>
    <fieldset
      :disabled="busy"
      class="min-w-0 rounded-xl border border-n-weak p-4"
    >
      <legend class="px-1 text-sm font-medium">
        {{ $t('PARTNER_REPORT.RATES') }}
      </legend>
      <p class="text-xs text-n-slate-11">
        {{ $t('PARTNER_REPORT.RATE_HELP') }}
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 min-w-0">
        <label
          v-for="(_, category) in rates"
          :key="category"
          class="text-sm min-w-0"
        >
          {{ $t(`PARTNER_REPORT.CATEGORY.${category}`) }}
          <input
            v-model="rates[category]"
            type="number"
            min="0"
            max="1000000"
            step="any"
            inputmode="decimal"
            :class="fieldsClass"
          />
        </label>
        <label class="min-w-0 text-sm">
          {{ $t('PARTNER_REPORT.AD_WINDOW') }}
          <select v-model="adDays" :class="fieldsClass">
            <option v-for="days in [7, 3]" :key="days" :value="String(days)">
              {{ $t('PARTNER_REPORT.AD_DAYS', { count: days }) }}
            </option>
          </select>
        </label>
        <label class="min-w-0 text-sm">
          {{ $t('PARTNER_REPORT.CURRENCY') }}
          <select v-model="currency" :class="fieldsClass">
            <option v-for="code in ['BRL', 'USD']" :key="code" :value="code">
              {{ code }}
            </option>
          </select>
        </label>
      </div>
    </fieldset>
    <Button
      type="submit"
      :disabled="busy"
      icon="i-lucide-chart-no-axes-combined"
      :label="$t(busy ? 'PARTNER_REPORT.LOADING' : 'PARTNER_REPORT.UPDATE')"
      class="self-start"
    />
  </form>
  <p v-if="error" role="alert" class="text-n-ruby-11 mt-4 break-words">
    {{ error }}
  </p>
  <section
    v-if="result"
    class="flex flex-col gap-5 mt-6 min-w-0"
    aria-live="polite"
  >
    <p v-if="!result.available_pairs.length" class="text-sm text-n-slate-11">
      {{ $t('PARTNER_REPORT.EMPTY') }}
    </p>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <div
        v-for="key in ['unique_messages', 'ad_referrals']"
        :key="key"
        class="rounded-xl border border-n-weak p-4 min-w-0"
      >
        <p class="text-sm text-n-slate-11">
          {{
            $t(
              key === 'unique_messages'
                ? 'PARTNER_REPORT.UNIQUE'
                : 'PARTNER_REPORT.REFERRALS'
            )
          }}
        </p>
        <strong class="text-2xl">{{ result.totals[key] }}</strong>
      </div>
    </div>
    <div
      v-for="pair in result.pairs"
      :key="pair.id"
      class="min-w-0 rounded-xl border border-n-weak p-3 sm:p-4"
    >
      <h3 class="text-base break-words">
        {{
          $t('PARTNER_REPORT.PAIR_NAME', {
            name: pair.name,
            partner: pair.partner_name,
          })
        }}
      </h3>
      <p class="text-xs text-n-slate-11 break-words">
        {{ pair.business_phone }}
        <span v-if="!pair.enabled">· {{ $t('PARTNER_REPORT.DISABLED') }}</span>
      </p>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div
          v-for="provider in providers"
          :key="provider"
          class="rounded-lg bg-n-alpha-2 p-3 min-w-0"
        >
          <h4 class="text-sm font-semibold">
            {{ $t(`PARTNER_REPORT.PROVIDERS.${provider}`) }}
          </h4>
          <dl class="text-sm mb-0">
            <div
              v-for="metric in ['incoming', 'outgoing', 'delivered']"
              :key="metric"
              class="flex gap-2 justify-between py-1"
            >
              <dt class="break-words">
                {{ $t(`PARTNER_REPORT.${metric.toUpperCase()}`) }}
              </dt>
              <dd class="mb-0 shrink-0">{{ pair.counts[provider][metric] }}</dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
    <p class="text-xs text-n-slate-11">
      {{ $t('PARTNER_REPORT.COUNTS_HELP') }}
    </p>
    <section class="rounded-xl border border-n-weak p-4 min-w-0">
      <h3 class="text-base">{{ $t('PARTNER_REPORT.SIMULATION') }}</h3>
      <p class="text-xs text-n-slate-11">
        {{ $t('PARTNER_REPORT.DISCLAIMER') }}
      </p>
      <p class="text-xs text-n-slate-11">
        {{ $t('PARTNER_REPORT.TIME_BASIS') }}
      </p>
      <p
        v-if="!result.timezone_confirmed"
        role="status"
        class="text-sm text-n-amber-11"
      >
        {{ $t('PARTNER_REPORT.NO_TIMEZONE') }}
      </p>
      <template v-if="result.simulation">
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div
            v-for="metric in metrics"
            :key="metric"
            class="flex justify-between gap-3 text-sm"
          >
            <dt>{{ $t(`PARTNER_REPORT.${metric.toUpperCase()}`) }}</dt>
            <dd class="shrink-0 mb-0">{{ result.simulation[metric] }}</dd>
          </div>
        </dl>
        <p class="font-semibold break-words">
          {{ $t('PARTNER_REPORT.ESTIMATE') }}: {{ cost }}
        </p>
        <h4 class="text-sm">
          {{ $t('PARTNER_REPORT.MONTHS') }} ({{ result.timezone }})
        </h4>
        <p class="text-xs text-n-slate-11">
          {{ $t('PARTNER_REPORT.MONTH_HELP') }}
        </p>
        <div
          v-for="month in result.simulation.months"
          :key="`${month.business_phone}-${month.month}`"
          class="text-sm border-t border-n-weak py-2 break-words"
        >
          {{
            $t('PARTNER_REPORT.MONTH_ROW', {
              phone: month.business_phone,
              month: month.month,
              used: month.allowance_used,
              remaining: month.allowance_remaining,
            })
          }}
        </div>
      </template>
    </section>
  </section>
</template>

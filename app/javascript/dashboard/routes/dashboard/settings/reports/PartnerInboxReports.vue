<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import timeZoneData from '../inbox/helpers/timezones.json';
import BarChart from 'shared/components/charts/BarChart.vue';
import AdLeadsTable from './components/AdLeadsTable.vue';

const props = defineProps({ leadsOnly: { type: Boolean, default: false } });
const { t } = useI18n();
const chartBrand = ref('rgb(39 129 246)');
const period = ref('current_month');
const from = ref('');
const to = ref('');
const timezone = ref('');
const accountTimezone = ref('UTC');
const effectiveTimezone = computed(
  () => timezone.value || accountTimezone.value
);
const timezones = computed(() =>
  [
    ...new Set([
      ...(Intl.supportedValuesOf
        ? Intl.supportedValuesOf('timeZone')
        : Object.values(timeZoneData)),
      'UTC',
      'America/Cuiaba',
      accountTimezone.value,
      timezone.value,
    ]),
  ]
    .filter(Boolean)
    .sort()
);
const linkId = ref('');
const currency = ref('BRL');
const adDays = ref('7');
const settingsMessage = ref('');
const rates = ref({
  service: '',
  utility: '',
  marketing: '',
  authentication: '',
});
function applyBrazilRates() {
  currency.value = 'BRL';
  Object.assign(rates.value, {
    service: '0.035',
    utility: '0.035',
    authentication: '0.035',
    marketing: '0.3217',
  });
  settingsMessage.value = '';
}
const result = ref(null);
const busy = ref(false);
const error = ref('');
const saving = ref(false);
const loadingSettings = ref(true);
const settingsLoadFailed = ref(false);
const settingsError = ref('');
const disabled = computed(
  () => busy.value || saving.value || loadingSettings.value
);
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

const formatMoney = value =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: currency.value,
    maximumFractionDigits: 4,
  }).format(Number(value));
const dailyChart = computed(() => ({
  labels: (result.value?.daily || []).map(day => day.date),
  datasets: providers.map((provider, index) => ({
    label: t(`PARTNER_REPORT.PROVIDERS.${provider}`),
    backgroundColor: [chartBrand.value, '#8b5cf6', '#94a3b8'][index],
    data: (result.value?.daily || []).map(day => day.counts[provider].outgoing),
  })),
}));
const costChart = computed(() => ({
  labels: [t('PARTNER_REPORT.CURRENT_COST'), t('PARTNER_REPORT.ALL_META_COST')],
  datasets: [
    {
      label: currency.value,
      backgroundColor: [chartBrand.value, '#8b5cf6'],
      data: [
        Number(result.value?.simulation?.estimated_cost || 0),
        Number(result.value?.simulation?.comparison?.all_meta_cost || 0),
      ],
    },
  ],
}));

function setDates() {
  if (period.value === 'custom') return;
  let date;
  try {
    date = new Intl.DateTimeFormat('en-CA', {
      timeZone: effectiveTimezone.value,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());
  } catch {
    return;
  }
  to.value = date;
  if (period.value === 'current_month') {
    from.value = `${date.slice(0, 7)}-01`;
    return;
  }
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
    const query = {
      from: from.value,
      to: to.value,
      timezone: effectiveTimezone.value,
      link_id: linkId.value || undefined,
      ad_window_days: adDays.value,
      ...Object.fromEntries(
        Object.entries(rates.value).map(([key, value]) => [
          `${key}_rate`,
          value,
        ])
      ),
    };
    const { data } = await (props.leadsOnly
      ? ReportsAPI.getAdLeads(query)
      : ReportsAPI.getPartnerInboxes(query));
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

async function saveSettings() {
  if (disabled.value || settingsLoadFailed.value) return;
  saving.value = true;
  settingsMessage.value = '';
  settingsError.value = '';
  try {
    await ReportsAPI.savePartnerInboxSettings({
      timezone: timezone.value,
      currency: currency.value,
      ad_window_days: adDays.value,
      ...Object.fromEntries(
        Object.entries(rates.value).map(([key, value]) => [
          `${key}_rate`,
          value,
        ])
      ),
    });
    settingsMessage.value = t('PARTNER_REPORT.SETTINGS_SAVED');
  } catch {
    settingsError.value = t('PARTNER_REPORT.SETTINGS_SAVE_ERROR');
  } finally {
    saving.value = false;
  }
}

watch(
  () => props.leadsOnly,
  () => {
    linkId.value = '';
    update();
  }
);

onMounted(async () => {
  const brand = getComputedStyle(document.documentElement)
    .getPropertyValue('--brand-color')
    .trim();
  if (brand) chartBrand.value = `rgb(${brand})`;
  try {
    const { data } = await ReportsAPI.getPartnerInboxSettings();
    accountTimezone.value = data.account_timezone ?? 'UTC';
    timezone.value = data.timezone ?? '';
    currency.value = data.currency ?? 'BRL';
    adDays.value = String(data.ad_window_days ?? 7);
    Object.keys(rates.value).forEach(key => {
      rates.value[key] = data[`${key}_rate`] ?? '';
    });
  } catch {
    settingsLoadFailed.value = true;
    settingsError.value = t('PARTNER_REPORT.SETTINGS_LOAD_ERROR');
  } finally {
    loadingSettings.value = false;
  }
  await update();
});
</script>

<template>
  <ReportHeader
    :header-title="
      $t(leadsOnly ? 'PARTNER_REPORT.AD_REPORT_TITLE' : 'PARTNER_REPORT.TITLE')
    "
    :header-description="
      $t(
        leadsOnly
          ? 'PARTNER_REPORT.AD_REPORT_DESCRIPTION'
          : 'PARTNER_REPORT.DESCRIPTION'
      )
    "
  />
  <form class="flex flex-col gap-4 min-w-0" @submit.prevent="update">
    <fieldset
      :disabled="disabled"
      class="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
    >
      <label class="min-w-0 text-sm">
        {{ $t('PARTNER_REPORT.PERIOD') }}
        <select v-model="period" :class="fieldsClass" @change="setDates">
          <option value="current_month">
            {{ $t('PARTNER_REPORT.CURRENT_MONTH') }}
          </option>
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
      <label v-if="!leadsOnly" class="min-w-0 text-sm">
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
        <select
          v-model="timezone"
          data-testid="report-timezone"
          :class="fieldsClass"
          @change="setDates"
        >
          <option value="">
            {{
              $t('PARTNER_REPORT.ACCOUNT_TIMEZONE', {
                timezone: accountTimezone,
              })
            }}
          </option>
          <option v-for="zone in timezones" :key="zone" :value="zone">
            {{ zone }}
          </option>
        </select>
        <span class="text-xs text-n-slate-11 block mt-1">{{
          $t('PARTNER_REPORT.TIMEZONE_HELP')
        }}</span>
      </label>
    </fieldset>
    <fieldset
      v-if="!leadsOnly"
      :disabled="disabled"
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
    <div class="flex flex-wrap gap-3">
      <Button
        type="submit"
        :disabled="disabled"
        icon="i-lucide-chart-no-axes-combined"
        :label="$t(busy ? 'PARTNER_REPORT.LOADING' : 'PARTNER_REPORT.UPDATE')"
      />
      <Button
        v-if="!leadsOnly"
        type="button"
        :disabled="disabled || settingsLoadFailed"
        icon="i-lucide-save"
        :label="
          $t(
            saving
              ? 'PARTNER_REPORT.SETTINGS_SAVING'
              : 'PARTNER_REPORT.SETTINGS_SAVE'
          )
        "
        @click="saveSettings"
      />
      <Button
        v-if="!leadsOnly"
        type="button"
        :disabled="disabled"
        icon="i-lucide-list-restart"
        :label="$t('PARTNER_REPORT.BRAZIL_RATES')"
        @click="applyBrazilRates"
      />
    </div>
    <p v-if="settingsMessage" role="status" class="text-sm text-n-teal-11">
      {{ settingsMessage }}
    </p>
    <p v-if="settingsError" role="alert" class="text-sm text-n-ruby-11">
      {{ settingsError }}
    </p>
  </form>
  <p v-if="error" role="alert" class="text-n-ruby-11 mt-4 break-words">
    {{ error }}
  </p>
  <section
    v-if="result"
    class="flex flex-col gap-5 mt-6 min-w-0"
    aria-live="polite"
  >
    <p
      v-if="!leadsOnly && !result.available_pairs.length"
      class="text-sm text-n-slate-11"
    >
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
    <div class="rounded-xl border border-n-weak p-4 text-sm">
      {{ $t('PARTNER_REPORT.AD_CONTACTS') }}:
      <strong>{{ result.totals.ad_contacts || 0 }}</strong>
    </div>
    <AdLeadsTable
      :leads="result.simulation?.ad_leads || []"
      :timezone="result.timezone"
    />
    <section
      v-if="!leadsOnly && result.daily?.length"
      class="rounded-xl border border-n-weak p-4 min-w-0"
    >
      <h3 class="text-base">{{ $t('PARTNER_REPORT.DAILY_CHART') }}</h3>
      <ul
        class="flex flex-wrap gap-4 text-sm list-none p-0"
        :aria-label="$t('PARTNER_REPORT.DAILY_CHART')"
      >
        <li
          v-for="dataset in dailyChart.datasets"
          :key="dataset.label"
          class="flex items-center gap-2"
        >
          <svg width="12" height="12" aria-hidden="true">
            <circle cx="6" cy="6" r="5" :fill="dataset.backgroundColor" />
          </svg>
          {{ dataset.label }}
        </li>
      </ul>
      <div class="h-64"><BarChart :collection="dailyChart" /></div>
    </section>
    <div
      v-for="pair in leadsOnly ? [] : result.pairs"
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
    <p v-if="!leadsOnly" class="text-xs text-n-slate-11">
      {{ $t('PARTNER_REPORT.COUNTS_HELP') }}
    </p>
    <section
      v-if="!leadsOnly"
      class="rounded-xl border border-n-weak p-4 min-w-0"
    >
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
        <section v-if="result.simulation.comparison" class="mb-5 min-w-0">
          <h4 class="text-base">{{ $t('PARTNER_REPORT.COMPARISON') }}</h4>
          <div class="h-56">
            <BarChart
              :collection="costChart"
              :chart-options="{ scales: { y: { beginAtZero: true } } }"
            />
          </div>
          <dl class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-sm">
            <div>
              <dt>{{ $t('PARTNER_REPORT.CURRENT_COST') }}</dt>
              <dd>{{ formatMoney(result.simulation.estimated_cost) }}</dd>
            </div>
            <div>
              <dt>{{ $t('PARTNER_REPORT.ALL_META_COST') }}</dt>
              <dd>
                {{ formatMoney(result.simulation.comparison.all_meta_cost) }}
              </dd>
            </div>
            <div>
              <dt>{{ $t('PARTNER_REPORT.AVOIDED_COST') }}</dt>
              <dd>
                {{ formatMoney(result.simulation.comparison.avoided_meta_cost)
                }}<span
                  v-if="result.simulation.comparison.avoided_percent !== null"
                >
                  ({{ result.simulation.comparison.avoided_percent }}%)</span
                >
              </dd>
            </div>
          </dl>
          <p class="text-xs text-n-slate-11">
            {{ $t('PARTNER_REPORT.COMPARISON_HELP') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{
              $t('PARTNER_REPORT.COMPARISON_GAPS', {
                categories: result.simulation.comparison.unclassified,
                rates: result.simulation.comparison.unpriced,
              })
            }}
          </p>
        </section>
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

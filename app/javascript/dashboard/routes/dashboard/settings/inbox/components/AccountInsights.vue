<script setup>
/* global axios */
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import InboxesAPI from 'dashboard/api/inboxes';
import ButtonV4 from 'next/button/Button.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});

const { t, te, locale } = useI18n();
const days = ref(30);
const insights = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
let requestId = 0;

const fetchInsights = async () => {
  requestId += 1;
  const currentRequest = requestId;
  insights.value = null;
  hasError.value = false;
  isLoading.value = true;
  try {
    const { data } = await axios.get(
      `${InboxesAPI.url}/${props.inboxId}/insights`,
      { params: { days: days.value } }
    );
    if (currentRequest === requestId) insights.value = data;
  } catch {
    if (currentRequest === requestId) hasError.value = true;
  } finally {
    if (currentRequest === requestId) isLoading.value = false;
  }
};

watch([() => props.inboxId, days], fetchInsights, { immediate: true });
onBeforeUnmount(() => {
  requestId += 1;
});

const unavailable = computed(() =>
  t('INBOX_MGMT.ACCOUNT_INSIGHTS.UNAVAILABLE')
);
const numberLocale = computed(() => locale.value.replace('_', '-'));

const pointsFor = section => {
  const sectionData = insights.value?.sections?.[section];
  if (sectionData?.status !== 'available' || !sectionData.data) return [];
  if (section === 'messages') return sectionData.data.data_points || [];
  return (sectionData.data.data || []).flatMap(item => item.data_points || []);
};

// A missing value is not a zero, and a partial sum would be misleading.
const total = (points, field) => {
  if (!points.length || !points.every(point => Number.isFinite(point[field]))) {
    return null;
  }
  return points.reduce((sum, point) => sum + point[field], 0);
};

const formatNumber = value =>
  value === null
    ? unavailable.value
    : new Intl.NumberFormat(numberLocale.value).format(value);

const formatCost = (points, useWabaCurrency = false) => {
  const cost = total(points, 'cost');
  const currencies = points.map(
    point => point.currency || (useWabaCurrency && insights.value?.currency)
  );
  const currency = currencies[0];
  if (
    cost === null ||
    !/^[A-Z]{3}$/.test(currency || '') ||
    !currencies.every(value => value === currency)
  ) {
    return unavailable.value;
  }
  return new Intl.NumberFormat(numberLocale.value, {
    style: 'currency',
    currency,
    maximumFractionDigits: 4,
  }).format(cost);
};

const averageDuration = points => {
  const count = total(points, 'count');
  if (!count || points.some(point => point.count < 0)) return null;
  const active = points.filter(point => point.count > 0);
  if (
    !active.every(
      point =>
        Number.isFinite(point.average_duration) && point.average_duration >= 0
    )
  ) {
    return null;
  }
  return (
    active.reduce(
      (sum, point) => sum + point.average_duration * point.count,
      0
    ) / count
  );
};

const pricingCategories = points => {
  const groups = points.reduce((categories, point) => {
    const category = point.pricing_category || 'UNKNOWN';
    const group = categories.get(category) || [];
    group.push(point);
    categories.set(category, group);
    return categories;
  }, new Map());
  return Array.from(groups, ([category, entries]) => {
    const key = `INBOX_MGMT.ACCOUNT_INSIGHTS.CATEGORIES.${category}`;
    return {
      key: category,
      label: te(key) ? t(key) : category,
      volume: formatNumber(total(entries, 'volume')),
      cost: formatCost(entries, true),
    };
  });
};

const cards = computed(() => {
  const messages = pointsFor('messages');
  const messageSection = insights.value?.sections?.messages;
  const received =
    messageSection?.received_status === 'unavailable'
      ? []
      : messageSection?.data?.received_data_points || [];
  const pricing = pointsFor('pricing');
  const calls = pointsFor('calls');
  return [
    {
      key: 'messages',
      title: t('INBOX_MGMT.ACCOUNT_INSIGHTS.MESSAGES'),
      metrics: [
        { key: 'SENT', value: formatNumber(total(messages, 'sent')) },
        { key: 'DELIVERED', value: formatNumber(total(messages, 'delivered')) },
        { key: 'RECEIVED', value: formatNumber(total(received, 'received')) },
      ],
    },
    {
      key: 'pricing',
      title: t('INBOX_MGMT.ACCOUNT_INSIGHTS.PRICING'),
      metrics: [
        { key: 'VOLUME', value: formatNumber(total(pricing, 'volume')) },
        { key: 'COST', value: formatCost(pricing, true) },
        ...['FREE_CUSTOMER_SERVICE', 'FREE_ENTRY_POINT', 'REGULAR'].map(
          type => ({
            key: type,
            value: formatNumber(
              total(
                pricing.filter(point => point.pricing_type === type),
                'volume'
              )
            ),
          })
        ),
      ],
      categories: pricingCategories(pricing),
    },
    {
      key: 'calls',
      title: t('INBOX_MGMT.ACCOUNT_INSIGHTS.CALLS'),
      metrics: [
        { key: 'COUNT', value: formatNumber(total(calls, 'count')) },
        { key: 'COST', value: formatCost(calls) },
        {
          key: 'AVERAGE_DURATION',
          value: formatNumber(averageDuration(calls)),
        },
        ...['BUSINESS_INITIATED', 'USER_INITIATED'].map(direction => ({
          key: direction,
          value: formatNumber(
            total(
              calls.filter(point => point.direction === direction),
              'count'
            )
          ),
        })),
      ],
    },
  ];
});

const formatDate = value => {
  if (!value) return unavailable.value;
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? unavailable.value
    : date.toLocaleString(numberLocale.value);
};
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:p-5"
    :aria-label="t('INBOX_MGMT.ACCOUNT_INSIGHTS.TITLE')"
    :aria-busy="isLoading"
  >
    <h3 class="text-heading-3 text-n-slate-12">
      {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.TITLE') }}
    </h3>
    <p class="text-body-main text-n-slate-11">
      {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.DESCRIPTION') }}
    </p>
    <p class="text-body-small text-n-slate-11">
      {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.UTC_PERIOD') }}
    </p>
    <div class="flex flex-wrap items-end gap-3">
      <label
        class="flex min-w-0 flex-col gap-1 text-body-small text-n-slate-12"
      >
        {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.PERIOD') }}
        <select
          v-model="days"
          class="!mb-0 min-h-10 max-w-full rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option v-for="period in [7, 30, 90]" :key="period" :value="period">
            {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.DAYS', { days: period }) }}
          </option>
        </select>
      </label>
      <ButtonV4
        type="button"
        size="sm"
        :is-loading="isLoading"
        :disabled="isLoading"
        @click="fetchInsights"
      >
        {{
          hasError
            ? t('INBOX_MGMT.ACCOUNT_INSIGHTS.RETRY')
            : t('INBOX_MGMT.ACCOUNT_INSIGHTS.REFRESH')
        }}
      </ButtonV4>
    </div>
    <p v-if="isLoading" role="status" class="text-body-main text-n-slate-11">
      {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.LOADING') }}
    </p>
    <p v-else-if="hasError" role="alert" class="text-body-main text-n-ruby-11">
      {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.ERROR') }}
    </p>
    <template v-else-if="insights">
      <p class="break-words text-body-small text-n-slate-11">
        {{
          t('INBOX_MGMT.ACCOUNT_INSIGHTS.FETCHED_AT', {
            date: formatDate(insights.fetched_at),
          })
        }}
      </p>
      <div class="grid min-w-0 grid-cols-1 gap-3 lg:grid-cols-3">
        <article
          v-for="card in cards"
          :key="card.key"
          :data-testid="card.key"
          class="min-w-0 space-y-3 rounded-lg border border-n-weak bg-n-solid-1 p-4"
        >
          <h4 class="break-words text-body-main font-medium text-n-slate-12">
            {{ card.title }}
          </h4>
          <dl class="space-y-2">
            <div v-for="metric in card.metrics" :key="metric.key">
              <dt class="break-words text-body-small text-n-slate-11">
                {{ t(`INBOX_MGMT.ACCOUNT_INSIGHTS.METRICS.${metric.key}`) }}
              </dt>
              <dd class="m-0 break-words text-body-main text-n-slate-12">
                {{ metric.value }}
              </dd>
            </div>
          </dl>
          <div
            v-if="card.key === 'pricing'"
            class="space-y-3 border-t border-n-weak pt-3"
          >
            <h5 class="text-body-small font-medium text-n-slate-12">
              {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.PRICING_CATEGORIES') }}
            </h5>
            <p
              v-if="!card.categories.length"
              class="text-body-small text-n-slate-11"
            >
              {{ unavailable }}
            </p>
            <div
              v-for="category in card.categories"
              :key="category.key"
              data-testid="pricing-category"
              class="min-w-0 space-y-1"
            >
              <h6
                class="break-words text-body-small font-medium text-n-slate-12"
              >
                {{ category.label }}
              </h6>
              <dl
                class="grid min-w-0 grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-1"
              >
                <div>
                  <dt class="text-body-small text-n-slate-11">
                    {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.METRICS.VOLUME') }}
                  </dt>
                  <dd class="m-0 break-words text-body-main text-n-slate-12">
                    {{ category.volume }}
                  </dd>
                </div>
                <div>
                  <dt class="text-body-small text-n-slate-11">
                    {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.METRICS.COST') }}
                  </dt>
                  <dd class="m-0 break-words text-body-main text-n-slate-12">
                    {{ category.cost }}
                  </dd>
                </div>
              </dl>
            </div>
          </div>
        </article>
      </div>
    </template>
    <p class="text-body-small text-n-slate-11">
      {{ t('INBOX_MGMT.ACCOUNT_INSIGHTS.COST_NOTICE') }}
    </p>
  </section>
</template>

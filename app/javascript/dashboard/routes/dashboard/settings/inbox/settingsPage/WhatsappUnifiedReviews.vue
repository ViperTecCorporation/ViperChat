<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { RouterLink, useRoute } from 'vue-router';
import Inboxes from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: { type: Number, required: true },
  linkEnabled: { type: Boolean, default: false },
});
const route = useRoute();
const kind = ref('event');
const status = ref('open');
const page = ref(1);
const items = ref([]);
const meta = ref({ page: 1, total: 0, total_pages: 0 });
const loading = ref(false);
const acting = ref(false);
const error = ref('');
const notice = ref('');
const confirmation = ref(null);
let requestSequence = 0;
let active = true;

const kinds = ['event', 'delivery', 'media', 'reservation'];
const statuses = ['open', 'acknowledged', 'all'];
const summaryFields = ['state', 'conversation_display_id'];
const fields = [
  'id',
  'kind',
  'provider',
  'original_id',
  'public_id',
  'message_id',
  'conversation_id',
  'created_at',
  'updated_at',
  'attempts',
  'next_attempt_at',
  'reviewed_at',
  'reviewed_by_id',
];
const reasons = [
  'identity_pending',
  'outbound_response_pending',
  'correlation_conflict',
  'link_changed',
  'identity_conflict',
  'processing_error',
  'correlated',
  'delivery_confirmation_uncertain',
  'link_disabled',
  'invalid_scope',
  'untrusted_mapping',
  'incompatible_messages',
  'unsupported_media',
  'media_unavailable',
  'attachment_count',
  'attachment_scope',
  'media_mismatch',
  'principal_unavailable',
  'counterpart_pending',
  'reservation_without_message',
];
const states = [
  'pending',
  'processing',
  'ready',
  'review',
  'disabled',
  'completed',
  'attempting',
  'acknowledged',
  'uncertain',
  'rejected',
  'reconciled',
  'unchanged',
];

function conversationRoute(item) {
  if (!route.params.accountId || !item.conversation_display_id) return null;
  return {
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: item.conversation_display_id,
    },
  };
}

function canRecheck(item) {
  return (
    item.kind !== 'reservation' && item.actions.recheck && props.linkEnabled
  );
}

function valueTranslation(field, value) {
  if (field === 'reason' && reasons.includes(value)) {
    return `WHATSAPP_UNIFIED.REVIEWS.REASONS.${value}`;
  }
  if (field === 'state' && states.includes(value)) {
    return `WHATSAPP_UNIFIED.REVIEWS.STATES.${value}`;
  }
  if (field === 'provider' && ['unoapi', 'whatsapp_cloud'].includes(value)) {
    return `WHATSAPP_UNIFIED.${value === 'unoapi' ? 'VIPERCONNECT' : 'META'}`;
  }
  return null;
}

async function load() {
  requestSequence += 1;
  const sequence = requestSequence;
  loading.value = true;
  error.value = '';
  confirmation.value = null;
  items.value = [];
  try {
    const { data } = await Inboxes.getWhatsappLinkReviews(props.inboxId, {
      page: page.value,
      kind: kind.value,
      status: status.value,
    });
    if (!active || sequence !== requestSequence) return;
    if (data.meta.total_pages > 0 && page.value > data.meta.total_pages) {
      page.value = data.meta.total_pages;
      return;
    }
    items.value = data.items;
    meta.value = data.meta;
  } catch {
    if (active && sequence === requestSequence) {
      error.value = 'WHATSAPP_UNIFIED.REVIEWS.LOAD_ERROR';
    }
  } finally {
    if (active && sequence === requestSequence) loading.value = false;
  }
}

function requestAction(item, action) {
  if (acting.value || loading.value) return;
  confirmation.value = { id: item.id, version: item.version, action };
  notice.value = '';
  error.value = '';
}

async function confirmAction() {
  if (!confirmation.value || acting.value || loading.value) return;
  const { id, version, action } = confirmation.value;
  const inboxId = props.inboxId;
  acting.value = true;
  error.value = '';
  notice.value = '';
  try {
    if (action === 'recheck') {
      await Inboxes.recheckWhatsappLinkReview(inboxId, id, version);
    } else {
      await Inboxes.acknowledgeWhatsappLinkReview(inboxId, id, version);
    }
    if (!active || inboxId !== props.inboxId) return;
    notice.value = `WHATSAPP_UNIFIED.REVIEWS.${action === 'recheck' ? 'RECHECK_SUCCESS' : 'ACKNOWLEDGE_SUCCESS'}`;
    await load();
  } catch (exception) {
    if (!active || inboxId !== props.inboxId) return;
    confirmation.value = null;
    if (exception.response?.status === 409) {
      notice.value = 'WHATSAPP_UNIFIED.REVIEWS.CHANGED';
      await load();
    } else {
      error.value = 'WHATSAPP_UNIFIED.REVIEWS.ACTION_ERROR';
    }
  } finally {
    if (active) acting.value = false;
  }
}

watch([kind, status], () => {
  notice.value = '';
  page.value = 1;
});
watch(
  [() => props.inboxId, () => props.linkEnabled, kind, status, page],
  load,
  {
    immediate: true,
  }
);
onBeforeUnmount(() => {
  active = false;
  requestSequence += 1;
});
</script>

<template>
  <section
    class="mt-6 w-full min-w-0 border-t border-n-weak pt-5 text-sm"
    :aria-label="$t('WHATSAPP_UNIFIED.REVIEWS.TITLE')"
    :aria-busy="loading || acting"
  >
    <h4 class="text-heading-3 text-n-slate-12">
      {{ $t('WHATSAPP_UNIFIED.REVIEWS.TITLE') }}
    </h4>
    <p class="text-n-slate-11">{{ $t('WHATSAPP_UNIFIED.REVIEWS.HELP') }}</p>
    <p class="text-n-slate-11">
      {{ $t('WHATSAPP_UNIFIED.REVIEWS.NO_RESEND') }}
    </p>
    <dl
      class="mt-3 grid min-w-0 grid-cols-1 gap-3 text-n-slate-11 sm:grid-cols-2"
    >
      <div>
        <dt class="font-semibold">
          {{ $t('WHATSAPP_UNIFIED.REVIEWS.RECHECK') }}
        </dt>
        <dd class="!m-0 break-words">
          {{ $t('WHATSAPP_UNIFIED.REVIEWS.RECHECK_HELP') }}
        </dd>
      </div>
      <div>
        <dt class="font-semibold">
          {{ $t('WHATSAPP_UNIFIED.REVIEWS.ACKNOWLEDGE') }}
        </dt>
        <dd class="!m-0 break-words">
          {{ $t('WHATSAPP_UNIFIED.REVIEWS.ACKNOWLEDGE_HELP') }}
        </dd>
      </div>
    </dl>
    <p v-if="!linkEnabled" class="text-n-amber-11">
      {{ $t('WHATSAPP_UNIFIED.REVIEWS.DISABLED_LINK') }}
    </p>
    <div class="my-4 grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
      <label class="min-w-0">
        <span class="mb-1 block">{{
          $t('WHATSAPP_UNIFIED.REVIEWS.KIND')
        }}</span>
        <select v-model="kind" :disabled="acting" class="!m-0 w-full min-w-0">
          <option v-for="value in kinds" :key="value" :value="value">
            {{ $t(`WHATSAPP_UNIFIED.REVIEWS.KINDS.${value}`) }}
          </option>
        </select>
      </label>
      <label class="min-w-0">
        <span class="mb-1 block">{{
          $t('WHATSAPP_UNIFIED.REVIEWS.STATUS')
        }}</span>
        <select v-model="status" :disabled="acting" class="!m-0 w-full min-w-0">
          <option v-for="value in statuses" :key="value" :value="value">
            {{ $t(`WHATSAPP_UNIFIED.REVIEWS.STATUSES.${value}`) }}
          </option>
        </select>
      </label>
    </div>
    <NextButton
      type="button"
      :label="$t('WHATSAPP_UNIFIED.REVIEWS.REFRESH')"
      :disabled="loading || acting"
      variant="outline"
      size="sm"
      @click="load"
    />
    <p v-if="notice" role="status" class="mt-3 break-words text-n-slate-12">
      {{ $t(notice) }}
    </p>
    <p v-if="error" role="alert" class="mt-3 break-words text-n-ruby-11">
      {{ $t(error) }}
    </p>
    <p v-if="loading" role="status" class="mt-3 text-n-slate-11">
      {{ $t('WHATSAPP_UNIFIED.REVIEWS.LOADING') }}
    </p>
    <template v-else-if="!error">
      <p v-if="!items.length" role="status" class="mt-3 text-n-slate-11">
        {{ $t('WHATSAPP_UNIFIED.REVIEWS.EMPTY') }}
      </p>
      <ul v-else class="!m-0 mt-4 flex min-w-0 list-none flex-col gap-3 !p-0">
        <li
          v-for="item in items"
          :key="item.id"
          class="min-w-0 rounded-lg border border-n-weak p-3"
          :data-review-id="item.id"
        >
          <p class="mb-1 break-words text-xs text-n-slate-11">
            {{
              $t(
                `WHATSAPP_UNIFIED.REVIEWS.${kinds.includes(item.kind) ? `KINDS.${item.kind}` : 'UNKNOWN_KIND'}`
              )
            }}
          </p>
          <h5
            class="mb-2 break-words [overflow-wrap:anywhere] font-semibold text-n-slate-12"
          >
            {{
              valueTranslation('reason', item.reason)
                ? $t(valueTranslation('reason', item.reason))
                : item.reason || $t('WHATSAPP_UNIFIED.REVIEWS.UNKNOWN_REASON')
            }}
          </h5>
          <p class="break-words text-n-slate-11" data-review-guidance>
            {{
              $t(
                `WHATSAPP_UNIFIED.REVIEWS.${reasons.includes(item.reason) ? `GUIDANCE.${item.reason}` : 'UNKNOWN_GUIDANCE'}`
              )
            }}
          </p>
          <p v-if="item.kind === 'delivery'" class="text-n-amber-11">
            {{ $t('WHATSAPP_UNIFIED.REVIEWS.DELIVERY_WARNING') }}
          </p>
          <dl class="grid min-w-0 grid-cols-1 gap-2 sm:grid-cols-2">
            <template v-for="field in summaryFields" :key="field">
              <div
                v-if="item[field] !== null && item[field] !== undefined"
                class="min-w-0"
              >
                <dt class="text-xs text-n-slate-11">
                  {{ $t(`WHATSAPP_UNIFIED.REVIEWS.FIELDS.${field}`) }}
                </dt>
                <dd
                  class="!m-0 whitespace-pre-wrap break-words [overflow-wrap:anywhere] text-n-slate-12"
                >
                  {{
                    valueTranslation(field, item[field])
                      ? $t(valueTranslation(field, item[field]))
                      : item[field]
                  }}
                </dd>
              </div>
            </template>
          </dl>
          <p v-if="!item.conversation_display_id" class="mt-2 text-n-slate-11">
            {{ $t('WHATSAPP_UNIFIED.REVIEWS.NO_CONVERSATION') }}
          </p>
          <details class="mt-3 min-w-0 rounded-lg border border-n-weak p-3">
            <summary
              class="cursor-pointer break-words font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-2"
            >
              {{ $t('WHATSAPP_UNIFIED.REVIEWS.TECHNICAL_DETAILS') }}
            </summary>
            <dl class="mt-3 grid min-w-0 grid-cols-1 gap-2 sm:grid-cols-2">
              <template v-for="field in fields" :key="field">
                <div
                  v-if="item[field] !== null && item[field] !== undefined"
                  class="min-w-0"
                >
                  <dt class="text-xs text-n-slate-11">
                    {{ $t(`WHATSAPP_UNIFIED.REVIEWS.FIELDS.${field}`) }}
                  </dt>
                  <dd
                    class="!m-0 whitespace-pre-wrap break-all text-n-slate-12"
                  >
                    {{
                      valueTranslation(field, item[field])
                        ? $t(valueTranslation(field, item[field]))
                        : item[field]
                    }}
                  </dd>
                </div>
              </template>
            </dl>
          </details>
          <div class="mt-3 flex flex-col flex-wrap gap-2 sm:flex-row">
            <RouterLink
              v-if="conversationRoute(item)"
              :to="conversationRoute(item)"
              class="inline-flex min-h-8 items-center justify-center rounded-lg px-3 py-1 text-n-blue-text hover:underline focus-visible:outline focus-visible:outline-2"
            >
              {{ $t('WHATSAPP_UNIFIED.REVIEWS.OPEN_CONVERSATION') }}
            </RouterLink>
            <NextButton
              v-if="canRecheck(item)"
              type="button"
              :label="$t('WHATSAPP_UNIFIED.REVIEWS.RECHECK')"
              :disabled="acting"
              variant="outline"
              size="sm"
              @click="requestAction(item, 'recheck')"
            />
            <NextButton
              v-if="item.actions.acknowledge"
              type="button"
              :label="$t('WHATSAPP_UNIFIED.REVIEWS.ACKNOWLEDGE')"
              :disabled="acting"
              variant="outline"
              size="sm"
              @click="requestAction(item, 'acknowledge')"
            />
          </div>
          <p
            v-if="!canRecheck(item) && !item.actions.acknowledge"
            class="mt-2 text-xs text-n-slate-11"
          >
            {{ $t('WHATSAPP_UNIFIED.REVIEWS.READ_ONLY') }}
          </p>
          <div
            v-if="confirmation?.id === item.id"
            role="group"
            :aria-label="$t('WHATSAPP_UNIFIED.REVIEWS.CONFIRM_TITLE')"
            class="mt-3 min-w-0 rounded-lg border border-n-weak bg-n-alpha-1 p-3"
          >
            <p class="break-words">
              {{
                $t(
                  `WHATSAPP_UNIFIED.REVIEWS.${confirmation.action === 'recheck' ? 'CONFIRM_RECHECK' : 'CONFIRM_ACKNOWLEDGE'}`
                )
              }}
            </p>
            <div class="flex flex-col flex-wrap gap-2 sm:flex-row">
              <NextButton
                type="button"
                :label="$t('WHATSAPP_UNIFIED.REVIEWS.CONFIRM')"
                :disabled="acting"
                :is-loading="acting"
                size="sm"
                @click="confirmAction"
              />
              <NextButton
                type="button"
                :label="$t('WHATSAPP_UNIFIED.REVIEWS.CANCEL')"
                :disabled="acting"
                variant="ghost"
                size="sm"
                @click="confirmation = null"
              />
            </div>
          </div>
        </li>
      </ul>
      <nav
        v-if="meta.total_pages > 1"
        :aria-label="$t('WHATSAPP_UNIFIED.REVIEWS.PAGINATION')"
        class="mt-4 flex min-w-0 flex-wrap items-center gap-2"
      >
        <NextButton
          type="button"
          :label="$t('WHATSAPP_UNIFIED.REVIEWS.PREVIOUS')"
          :disabled="acting || meta.page <= 1"
          variant="outline"
          size="sm"
          @click="page = meta.page - 1"
        />
        <span class="break-words">
          {{
            $t('WHATSAPP_UNIFIED.REVIEWS.PAGE', {
              page: meta.page,
              pages: meta.total_pages,
              total: meta.total,
            })
          }}
        </span>
        <NextButton
          type="button"
          :label="$t('WHATSAPP_UNIFIED.REVIEWS.NEXT')"
          :disabled="acting || meta.page >= meta.total_pages"
          variant="outline"
          size="sm"
          @click="page = meta.page + 1"
        />
      </nav>
    </template>
  </section>
</template>

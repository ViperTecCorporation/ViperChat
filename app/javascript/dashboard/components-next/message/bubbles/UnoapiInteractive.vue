<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const {
  content,
  contentAttributes,
  conversationId,
  id: messageId,
} = useMessageContext();
const store = useStore();
const copiedValue = ref('');
const selectedReply = ref('');

const interactive = computed(
  () => contentAttributes.value?.whatsappInteractive || {}
);
const actions = computed(() =>
  Array.isArray(interactive.value.actions) ? interactive.value.actions : []
);
const sections = computed(() =>
  Array.isArray(interactive.value.sections) ? interactive.value.sections : []
);
const order = computed(() => interactive.value.order || {});
const status = computed(() => interactive.value.status || {});

const safeHttpUrl = value => {
  try {
    const url = new URL(String(value || ''));
    return ['http:', 'https:'].includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
};

const safePhoneUrl = value => {
  const phone = String(value || '').replace(/[^\d+]/g, '');
  return phone ? `tel:${phone}` : '';
};

const formatAmount = (amount, currency = 'BRL') => {
  const value = Number(amount?.value);
  const offset = Number(amount?.offset || 1);
  if (!Number.isFinite(value) || !Number.isFinite(offset) || offset <= 0)
    return '';

  try {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: currency || 'BRL',
    }).format(value / offset);
  } catch {
    return `${currency || ''} ${value / offset}`.trim();
  }
};

const copyValue = async value => {
  if (!value || !navigator?.clipboard) return;
  await navigator.clipboard.writeText(value);
  copiedValue.value = value;
  window.setTimeout(() => {
    if (copiedValue.value === value) copiedValue.value = '';
  }, 1600);
};

const paymentLabel = payment => {
  const labels = {
    pix_static_code: 'PIX estático',
    pix_dynamic_code: 'PIX dinâmico',
    payment_link: 'Link de pagamento',
    boleto: 'Boleto',
    offsite_card_pay: 'Cartão',
  };
  return labels[payment?.type] || 'Forma de pagamento';
};

const statusTone = value => {
  if (['completed', 'captured', 'shipped'].includes(value)) return 'success';
  if (['failed', 'canceled'].includes(value)) return 'danger';
  if (['pending', 'processing', 'partially_shipped'].includes(value))
    return 'warning';
  return 'neutral';
};

const replyKey = (reply, responseType) =>
  `${responseType}:${reply?.id || reply?.title || ''}`;

const sendReply = async (reply, responseType) => {
  const title = String(reply?.title || '').trim();
  if (!title || selectedReply.value) return;

  selectedReply.value = replyKey(reply, responseType);
  await store.dispatch('createPendingMessageAndSend', {
    conversationId: conversationId.value,
    message: title,
    private: false,
    contentType: 'text',
    contentAttributes: {
      in_reply_to: messageId.value,
      whatsapp_interactive_reply: {
        id: String(reply?.id || ''),
        title,
        type: responseType,
      },
    },
  });
};
</script>

<template>
  <BaseBubble
    class="min-w-64 max-w-[min(28rem,calc(100vw-5rem))] overflow-hidden"
    data-bubble-name="unoapi-interactive"
  >
    <img
      v-if="safeHttpUrl(interactive.header?.imageUrl)"
      :src="safeHttpUrl(interactive.header.imageUrl)"
      alt=""
      class="max-h-60 w-full bg-n-alpha-2 object-cover"
      loading="lazy"
    />
    <div class="grid gap-2 px-4 py-3">
      <p
        v-if="interactive.header?.text"
        class="m-0 text-sm font-semibold text-n-slate-12"
      >
        {{ interactive.header.text }}
      </p>
      <p v-if="content" class="m-0 whitespace-pre-wrap break-words text-sm">
        {{ content }}
      </p>

      <div v-if="interactive.reply" class="rounded-lg bg-n-alpha-2 px-3 py-2">
        <p class="m-0 font-medium">{{ interactive.reply.title }}</p>
        <p
          v-if="interactive.reply.description"
          class="m-0 mt-1 text-xs text-n-slate-11"
        >
          {{ interactive.reply.description }}
        </p>
      </div>

      <div v-for="(section, index) in sections" :key="index" class="grid gap-1">
        <p
          v-if="section.title"
          class="m-0 text-xs font-semibold text-n-slate-11"
        >
          {{ section.title }}
        </p>
        <button
          v-for="row in section.rows || []"
          :key="row.id || row.title"
          type="button"
          :disabled="Boolean(selectedReply)"
          class="rounded-lg border border-n-weak px-3 py-2 text-left transition-colors hover:border-n-brand hover:bg-n-alpha-2 disabled:cursor-default disabled:opacity-60"
          :data-selected="
            selectedReply === replyKey(row, 'list_reply') || undefined
          "
          @click="sendReply(row, 'list_reply')"
        >
          <p class="m-0 text-sm font-medium">{{ row.title || row.id }}</p>
          <p v-if="row.description" class="m-0 text-xs text-n-slate-11">
            {{ row.description }}
          </p>
        </button>
      </div>

      <div
        v-if="order.referenceId"
        class="grid gap-2 rounded-lg bg-n-alpha-2 p-3"
      >
        <div class="flex items-center justify-between gap-4">
          <span class="text-xs text-n-slate-11">
            {{ $t('CONVERSATION.UNOAPI.ORDER', { id: order.referenceId }) }}
          </span>
          <strong v-if="formatAmount(order.totalAmount, order.currency)">
            {{ formatAmount(order.totalAmount, order.currency) }}
          </strong>
        </div>
        <div
          v-for="item in order.items || []"
          :key="item.retailerId || item.name"
          class="flex justify-between gap-3 text-sm"
        >
          <span>
            {{
              $t('CONVERSATION.UNOAPI.QUANTITY', {
                quantity: item.quantity || 1,
                name: item.name || item.retailerId,
              })
            }}
          </span>
          <span>{{ formatAmount(item.amount, order.currency) }}</span>
        </div>
      </div>

      <div
        v-if="status.referenceId"
        class="grid gap-2 rounded-lg bg-n-alpha-2 p-3"
      >
        <span class="text-xs text-n-slate-11">
          {{ $t('CONVERSATION.UNOAPI.ORDER', { id: status.referenceId }) }}
        </span>
        <span
          v-if="status.order?.status"
          class="w-fit rounded-full px-2 py-1 text-xs font-medium"
          :class="{
            'bg-n-teal-3 text-n-teal-11':
              statusTone(status.order.status) === 'success',
            'bg-n-ruby-3 text-n-ruby-11':
              statusTone(status.order.status) === 'danger',
            'bg-n-amber-3 text-n-amber-11':
              statusTone(status.order.status) === 'warning',
            'bg-n-alpha-3 text-n-slate-11':
              statusTone(status.order.status) === 'neutral',
          }"
        >
          {{ status.order.status }}
        </span>
        <p v-if="status.order?.description" class="m-0 text-sm">
          {{ status.order.description }}
        </p>
      </div>

      <template
        v-for="(payment, index) in order.paymentSettings || []"
        :key="`${payment.type}-${index}`"
      >
        <div class="grid gap-1 rounded-lg border border-n-weak p-3 text-sm">
          <strong>{{ paymentLabel(payment) }}</strong>
          <span v-if="payment.merchantName">{{ payment.merchantName }}</span>
          <span v-if="payment.key" class="break-all">{{ payment.key }}</span>
          <span v-if="payment.lastFourDigits">
            {{
              $t('CONVERSATION.UNOAPI.CARD_ENDING', {
                digits: payment.lastFourDigits,
              })
            }}
          </span>
          <a
            v-if="safeHttpUrl(payment.url)"
            :href="safeHttpUrl(payment.url)"
            target="_blank"
            rel="noopener noreferrer"
            class="text-n-brand"
          >
            {{ $t('CONVERSATION.UNOAPI.OPEN_PAYMENT') }}
          </a>
          <button
            v-if="payment.digitableLine"
            type="button"
            class="text-left text-n-brand"
            @click="copyValue(payment.digitableLine)"
          >
            {{
              copiedValue === payment.digitableLine
                ? $t('CONVERSATION.UNOAPI.COPIED')
                : $t('CONVERSATION.UNOAPI.COPY_DIGITABLE_LINE')
            }}
          </button>
        </div>
      </template>

      <div v-if="actions.length" class="grid gap-2 border-t border-n-weak pt-2">
        <template
          v-for="(action, index) in actions"
          :key="`${action.type}-${index}`"
        >
          <a
            v-if="action.type === 'url' && safeHttpUrl(action.url)"
            :href="safeHttpUrl(action.url)"
            target="_blank"
            rel="noopener noreferrer"
            class="text-center text-sm font-medium text-n-brand"
          >
            {{ action.title || $t('CONVERSATION.UNOAPI.OPEN_LINK') }}
          </a>
          <a
            v-else-if="
              action.type === 'call' && safePhoneUrl(action.phoneNumber)
            "
            :href="safePhoneUrl(action.phoneNumber)"
            class="text-center text-sm font-medium text-n-brand"
          >
            {{ action.title || action.phoneNumber }}
          </a>
          <button
            v-else-if="action.type === 'copy' && action.code"
            type="button"
            class="text-sm font-medium text-n-brand"
            @click="copyValue(action.code)"
          >
            {{
              copiedValue === action.code
                ? $t('CONVERSATION.UNOAPI.COPIED')
                : action.title || $t('CONVERSATION.UNOAPI.COPY')
            }}
          </button>
          <button
            v-else-if="action.type === 'reply'"
            type="button"
            :disabled="Boolean(selectedReply)"
            class="rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-brand transition-colors hover:border-n-brand hover:bg-n-alpha-2 disabled:cursor-default disabled:opacity-60"
            :data-selected="
              selectedReply === replyKey(action, 'button_reply') || undefined
            "
            @click="sendReply(action, 'button_reply')"
          >
            {{ action.title || action.id }}
          </button>
          <div
            v-else-if="action.type === 'payment_request'"
            class="grid gap-1 rounded-lg bg-n-alpha-2 p-3 text-sm"
          >
            <strong>{{
              action.payment?.referenceId
                ? $t('CONVERSATION.UNOAPI.PAYMENT', {
                    id: action.payment.referenceId,
                  })
                : paymentLabel(action.payment)
            }}</strong>
            <span
              v-if="
                formatAmount(
                  action.payment?.totalAmount,
                  action.payment?.currency
                )
              "
            >
              {{
                formatAmount(
                  action.payment.totalAmount,
                  action.payment.currency
                )
              }}
            </span>
            <template
              v-for="(payment, paymentIndex) in action.payment
                ?.paymentSettings || [action.payment]"
              :key="paymentIndex"
            >
              <span>{{ paymentLabel(payment) }}</span>
              <span v-if="payment?.merchantName">{{
                payment.merchantName
              }}</span>
              <span v-if="payment?.key" class="break-all">{{
                payment.key
              }}</span>
            </template>
          </div>
        </template>
      </div>

      <p v-if="interactive.footer?.text" class="m-0 text-xs text-n-slate-10">
        {{ interactive.footer.text }}
      </p>
    </div>
  </BaseBubble>
</template>

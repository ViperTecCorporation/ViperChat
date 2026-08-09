<script setup>
import { computed, ref } from 'vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { content, contentAttributes } = useMessageContext();
const imageFailed = ref(false);
const product = computed(() => contentAttributes.value?.unoapiCatalog || {});
const order = computed(() => contentAttributes.value?.unoapiOrder || {});
const payload = computed(() =>
  contentAttributes.value?.unoapiMessageType === 'order'
    ? order.value
    : product.value
);
const isOrder = computed(
  () => contentAttributes.value?.unoapiMessageType === 'order'
);

const safeHttpUrl = value => {
  try {
    const url = new URL(String(value || ''));
    return ['http:', 'https:'].includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
};
const imageUrl = item => safeHttpUrl(item?.image?.url);
const price = (item, formattedKey, amountKey) => {
  if (item?.[formattedKey]) return item[formattedKey];
  const raw = Number(item?.[amountKey]);
  if (!Number.isFinite(raw)) return '';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: item.currency || payload.value.currency || 'BRL',
  }).format(raw / 1000);
};
</script>

<template>
  <BaseBubble
    class="min-w-64 max-w-[min(30rem,calc(100vw-5rem))] overflow-hidden"
    data-bubble-name="unoapi-catalog"
  >
    <img
      v-if="!isOrder && imageUrl(product) && !imageFailed"
      :src="imageUrl(product)"
      :alt="product.title || ''"
      class="max-h-64 w-full bg-n-alpha-2 object-cover"
      loading="lazy"
      @error="imageFailed = true"
    />
    <div class="grid gap-2 px-4 py-3">
      <p v-if="content" class="m-0 whitespace-pre-wrap break-words text-sm">
        {{ content }}
      </p>
      <template v-if="!isOrder">
        <strong v-if="product.title">{{ product.title }}</strong>
        <p v-if="product.description" class="m-0 text-sm text-n-slate-11">
          {{ product.description }}
        </p>
        <div class="flex items-center gap-2">
          <strong>{{
            price(product, 'formattedSalePrice', 'salePriceAmount1000') ||
            price(product, 'formattedPrice', 'priceAmount1000')
          }}</strong>
          <s
            v-if="product.formattedSalePrice && product.formattedPrice"
            class="text-xs text-n-slate-10"
          >
            {{ product.formattedPrice }}
          </s>
        </div>
        <a
          v-if="safeHttpUrl(product.url)"
          :href="safeHttpUrl(product.url)"
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm font-medium text-n-brand"
        >
          {{ $t('CONVERSATION.UNOAPI.VIEW_PRODUCT') }}
        </a>
      </template>
      <template v-else>
        <div class="flex items-center justify-between gap-3">
          <strong>{{
            order.title || $t('CONVERSATION.UNOAPI.ORDER_RECEIVED')
          }}</strong>
          <span class="rounded-full bg-n-alpha-3 px-2 py-1 text-xs">{{
            order.resolutionStatus || order.status
          }}</span>
        </div>
        <div
          v-for="item in order.items || []"
          :key="item.productId || item.retailerId || item.title"
          class="flex gap-3 rounded-lg bg-n-alpha-2 p-2"
        >
          <img
            v-if="imageUrl(item)"
            :src="imageUrl(item)"
            :alt="item.title || ''"
            class="size-12 rounded object-cover"
            loading="lazy"
          />
          <div class="min-w-0 flex-1 text-sm">
            <p class="m-0 truncate font-medium">
              {{
                $t('CONVERSATION.UNOAPI.QUANTITY', {
                  quantity: item.quantity || 1,
                  name: item.title || item.retailerId,
                })
              }}
            </p>
            <p class="m-0 text-n-slate-11">
              {{
                price(item, 'formattedSubtotal', 'subtotalAmount1000') ||
                price(item, 'formattedUnitPrice', 'unitPriceAmount1000')
              }}
            </p>
          </div>
        </div>
        <div
          class="flex justify-between border-t border-n-weak pt-2 text-sm font-semibold"
        >
          <span>{{ $t('CONVERSATION.UNOAPI.TOTAL') }}</span>
          <span>{{
            order.formattedTotal ||
            price(order, 'formattedTotal', 'totalAmount1000')
          }}</span>
        </div>
        <p v-if="order.message" class="m-0 text-sm text-n-slate-11">
          {{ order.message }}
        </p>
      </template>
    </div>
  </BaseBubble>
</template>

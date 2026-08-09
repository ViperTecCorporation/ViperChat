<script setup>
import { computed, ref } from 'vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { content, contentAttributes } = useMessageContext();
const failedImages = ref(new Set());
const copiedValue = ref('');

const stringValue = value => (typeof value === 'string' ? value : '');

const safeHttpUrl = value => {
  const rawUrl = stringValue(value);
  if (!rawUrl) return '';

  try {
    const parsedUrl = new URL(rawUrl);
    return ['http:', 'https:'].includes(parsedUrl.protocol)
      ? parsedUrl.href
      : '';
  } catch {
    return '';
  }
};

const items = computed(() => {
  const rawItems = contentAttributes.value?.items;
  if (!Array.isArray(rawItems)) return [];

  return rawItems
    .filter(item => item && typeof item === 'object' && !Array.isArray(item))
    .map(item => {
      const rawActions = Array.isArray(item.actions) ? item.actions : [];
      const actions = rawActions
        .filter(
          action =>
            action && typeof action === 'object' && !Array.isArray(action)
        )
        .map(action => ({
          type: stringValue(action.type),
          text: stringValue(action.text),
          uri: safeHttpUrl(action.uri),
          payload: stringValue(action.payload),
          phoneNumber: stringValue(action.phoneNumber || action.phone_number),
          code: stringValue(action.code),
        }))
        .filter(
          action =>
            action.text ||
            action.uri ||
            action.payload ||
            action.phoneNumber ||
            action.code
        );

      return {
        title: stringValue(item.title),
        description: stringValue(item.description),
        footer: stringValue(item.footer),
        mediaUrl: safeHttpUrl(item.mediaUrl || item.media_url),
        actions,
      };
    });
});

const markImageAsFailed = index => {
  failedImages.value = new Set([...failedImages.value, index]);
};

const copyValue = async value => {
  if (!value || !navigator?.clipboard) return;
  await navigator.clipboard.writeText(value);
  copiedValue.value = value;
};
</script>

<template>
  <BaseBubble class="overflow-hidden" data-bubble-name="cards">
    <p v-if="content" class="whitespace-pre-wrap break-words px-4 pt-3">
      {{ content }}
    </p>
    <div
      v-if="items.length"
      class="flex max-w-[min(32rem,calc(100vw-5rem))] snap-x snap-mandatory gap-3 overflow-x-auto p-3"
      data-testid="cards-carousel"
    >
      <article
        v-for="(item, index) in items"
        :key="index"
        class="w-60 shrink-0 snap-start overflow-hidden rounded-lg border border-n-weak bg-n-background text-n-slate-12 shadow-sm dark:bg-n-solid-3"
        data-testid="carousel-card"
      >
        <img
          v-if="item.mediaUrl && !failedImages.has(index)"
          :src="item.mediaUrl"
          :alt="item.title || item.description"
          class="h-36 w-full bg-n-alpha-2 object-cover"
          loading="lazy"
          @error="markImageAsFailed(index)"
        />
        <div
          v-else-if="item.mediaUrl"
          class="grid h-36 place-items-center bg-n-alpha-2 text-n-slate-9"
          data-testid="carousel-image-fallback"
        >
          <span class="i-lucide-image-off size-6" />
        </div>
        <div class="flex min-h-28 flex-col gap-2 p-3">
          <h4 v-if="item.title" class="m-0 text-sm font-semibold">
            {{ item.title }}
          </h4>
          <p
            v-if="item.description"
            class="m-0 whitespace-pre-wrap break-words text-sm text-n-slate-11"
          >
            {{ item.description }}
          </p>
          <p v-if="item.footer" class="m-0 text-xs text-n-slate-10">
            {{ item.footer }}
          </p>
          <div v-if="item.actions.length" class="mt-auto grid gap-2 pt-1">
            <template
              v-for="(action, actionIndex) in item.actions"
              :key="`${index}-${actionIndex}`"
            >
              <a
                v-if="action.type === 'link' && action.uri"
                :href="action.uri"
                target="_blank"
                rel="noopener noreferrer"
                class="skip-context-menu inline-flex min-h-8 items-center justify-center rounded-md border border-n-weak px-3 py-1.5 text-center text-sm font-medium text-n-brand hover:bg-n-alpha-2"
              >
                {{ action.text || action.uri }}
              </a>
              <button
                v-else-if="action.type === 'postback'"
                type="button"
                disabled
                class="min-h-8 cursor-not-allowed rounded-md border border-n-weak px-3 py-1.5 text-sm font-medium text-n-slate-10 opacity-70"
              >
                {{ action.text || action.payload }}
              </button>
              <a
                v-else-if="action.type === 'call' && action.phoneNumber"
                :href="`tel:${action.phoneNumber.replace(/[^\d+]/g, '')}`"
                class="skip-context-menu inline-flex min-h-8 items-center justify-center rounded-md border border-n-weak px-3 py-1.5 text-center text-sm font-medium text-n-brand hover:bg-n-alpha-2"
              >
                {{ action.text || action.phoneNumber }}
              </a>
              <button
                v-else-if="action.type === 'copy' && action.code"
                type="button"
                class="min-h-8 rounded-md border border-n-weak px-3 py-1.5 text-sm font-medium text-n-brand hover:bg-n-alpha-2"
                @click="copyValue(action.code)"
              >
                {{
                  copiedValue === action.code
                    ? $t('CONVERSATION.UNOAPI.COPIED')
                    : action.text || $t('CONVERSATION.UNOAPI.COPY')
                }}
              </button>
            </template>
          </div>
        </div>
      </article>
    </div>
    <p v-else-if="!content" class="px-4 py-3 text-n-slate-11">
      {{ $t('CONVERSATION.NO_CONTENT') }}
    </p>
  </BaseBubble>
</template>

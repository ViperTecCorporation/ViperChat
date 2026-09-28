<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { useIntersectionObserver } from '@vueuse/core';
import BaseBubble from './Base.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../provider.js';

const { attachments, content } = useMessageContext();
const { t } = useI18n();
const previewContainer = ref(null);
const previewFrame = ref(null);
const visible = ref(false);
const previewFailed = ref(false);
useIntersectionObserver(previewContainer, ([entry]) => {
  if (entry?.isIntersecting) visible.value = true;
});

const attachment = computed(() => {
  return attachments.value[0];
});

const lat = computed(() => {
  return attachment.value.coordinatesLat ?? attachment.value.coordinates_lat;
});
const long = computed(() => {
  return attachment.value.coordinatesLong ?? attachment.value.coordinates_long;
});

const title = computed(() => {
  return (
    attachment.value.fallbackTitle ||
    attachment.value.fallback_title ||
    content?.value ||
    ''
  );
});

const mapUrl = computed(() => {
  const name = (attachment.value.meta?.name || title.value).trim();
  if (!name) return `https://maps.google.com/?q=${lat.value},${long.value}`;

  return `https://maps.google.com/maps/search/${encodeURIComponent(name)}/@${lat.value},${long.value},17z?hl=pt-BR`;
});
const placeName = computed(() => attachment.value.meta?.name?.trim() || '');
const details = computed(() => {
  const text = title.value.trim();
  if (placeName.value && text.startsWith(placeName.value)) {
    return text.slice(placeName.value.length).replace(/^[\s,–—-]+/, '');
  }
  return text;
});
const previewUrl = computed(() => {
  const url = new URL(
    '/location-map/preview',
    window.chatwootConfig?.hostURL || window.location.origin
  );
  url.searchParams.set('lat', lat.value);
  url.searchParams.set('lng', long.value);
  return url;
});
const onPreviewMessage = event => {
  if (
    event.origin === previewUrl.value.origin &&
    event.source === previewFrame.value?.contentWindow &&
    event.data?.source === 'viper-location-preview' &&
    event.data.type === 'error'
  ) {
    previewFailed.value = true;
  }
};
onMounted(() => window.addEventListener('message', onPreviewMessage));
onBeforeUnmount(() => window.removeEventListener('message', onPreviewMessage));
</script>

<template>
  <BaseBubble
    class="w-80 !max-w-full box-border overflow-hidden p-2"
    data-bubble-name="location"
  >
    <a
      :href="mapUrl"
      target="_blank"
      rel="noreferrer noopener nofollow"
      :aria-label="t('COMPONENTS.LOCATION_BUBBLE.SEE_ON_MAP')"
      class="block min-w-0 text-inherit rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
    >
      <div
        v-if="!previewFailed"
        ref="previewContainer"
        class="w-full aspect-[2/1] overflow-hidden rounded-lg bg-n-alpha-3"
      >
        <iframe
          v-if="visible"
          ref="previewFrame"
          :src="previewUrl.href"
          :title="t('COMPONENTS.LOCATION_BUBBLE.SEE_ON_MAP')"
          class="h-full w-full border-0 pointer-events-none"
          tabindex="-1"
          @error="previewFailed = true"
        />
      </div>
      <div class="px-1 pt-2 space-y-1 text-n-slate-12">
        <p v-if="placeName" class="m-0 font-semibold break-words text-sm">
          {{ placeName }}
        </p>
        <p v-if="details" class="m-0 whitespace-pre-line break-words text-sm">
          {{ details }}
        </p>
        <p
          v-if="previewFailed || (!placeName && !details)"
          class="m-0 text-sm underline"
        >
          {{ t('COMPONENTS.LOCATION_BUBBLE.SEE_ON_MAP') }}
        </p>
      </div>
    </a>
  </BaseBubble>
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import VideoBubble from '../components/VideoBubble.vue';
import { attachmentUrl } from './api';

const props = defineProps({ attachment: { type: Object, required: true } });
const { t } = useI18n();
const failed = ref(false);
const url = computed(() => attachmentUrl(props.attachment.url));
const contacts = computed(() => {
  const value = props.attachment.meta?.contacts;
  if (Array.isArray(value)) return value;
  if (props.attachment.file_type !== 'contact') return [];
  const meta = props.attachment.meta || {};
  return [
    {
      name:
        meta.formattedName ||
        meta.formatted_name ||
        [meta.firstName, meta.lastName].filter(Boolean).join(' ') ||
        t('contact'),
      phones: [{ phone: props.attachment.fallback_title }],
      email: meta.email,
    },
  ];
});
const mapUrl = computed(() => {
  if (props.attachment.file_type !== 'location') return '';
  const { latitude, longitude } = props.attachment;
  if (
    latitude === null ||
    latitude === undefined ||
    longitude === null ||
    longitude === undefined
  )
    return '';
  const lat = Number(latitude);
  const lon = Number(longitude);
  if (
    !Number.isFinite(lat) ||
    !Number.isFinite(lon) ||
    Math.abs(lat) > 90 ||
    Math.abs(lon) > 180
  )
    return '';
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=16/${lat}/${lon}`;
});
</script>

<template>
  <div class="min-w-0 space-y-2 break-words">
    <template v-if="attachment.file_type === 'contact' || contacts.length">
      <div
        v-for="(contact, index) in contacts"
        :key="index"
        class="rounded-lg border border-n-weak p-2"
      >
        <p class="font-medium">
          {{ contact.name?.formatted_name || contact.name || t('contact') }}
        </p>
        <p
          v-for="(phone, phoneIndex) in contact.phones || []"
          :key="phoneIndex"
          class="text-sm"
        >
          {{ phone.phone || phone.wa_id }}
        </p>
        <p v-if="contact.email" class="break-all text-sm">
          {{ contact.email }}
        </p>
      </div>
      <p v-if="!contacts.length">
        {{ attachment.fallback_title || t('contact') }}
      </p>
    </template>
    <a
      v-else-if="mapUrl"
      :href="mapUrl"
      target="_blank"
      rel="noopener noreferrer"
      class="block underline"
    >
      {{
        t('locationMap', { name: attachment.fallback_title || t('location') })
      }}
    </a>
    <p v-else-if="failed || !url" role="status">{{ t('mediaFailed') }}</p>
    <a
      v-else-if="attachment.file_type === 'image'"
      :href="url"
      target="_blank"
      rel="noopener noreferrer"
    >
      <img
        :src="url"
        :alt="attachment.name || t('image')"
        class="max-h-80 w-full rounded-lg object-contain"
        loading="lazy"
        @error="failed = true"
      />
    </a>
    <VideoBubble
      v-else-if="attachment.file_type === 'video'"
      :url="url"
      @error="failed = true"
    />
    <audio
      v-else-if="attachment.file_type === 'audio'"
      :src="url"
      controls
      preload="none"
      class="w-full min-w-0 max-w-full"
      @error="failed = true"
    />
    <a
      v-else
      :href="url"
      target="_blank"
      rel="noopener noreferrer"
      class="block break-all underline"
    >
      {{ attachment.name || t('download') }}
    </a>
  </div>
</template>

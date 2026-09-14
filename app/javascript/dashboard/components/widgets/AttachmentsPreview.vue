<script setup>
import { computed, ref } from 'vue';
import { formatBytes } from 'shared/helpers/FileHelper';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  attachments: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['removeAttachment']);
const failedPreviews = ref(new Set());

const nonRecordedAudioAttachments = computed(() => {
  return props.attachments.filter(attachment => !attachment?.isVoiceMessage);
});

const recordedAudioAttachments = computed(() =>
  props.attachments.filter(attachment => attachment.isVoiceMessage)
);

const onRemoveAttachment = itemIndex => {
  emit(
    'removeAttachment',
    nonRecordedAudioAttachments.value
      .filter((_, index) => index !== itemIndex)
      .concat(recordedAudioAttachments.value)
  );
};

const formatFileSize = file => {
  const size = file.byte_size || file.size;
  return formatBytes(size, 0);
};

const isTypeImage = file => {
  const type = file.content_type || file.type || '';
  return type.startsWith('image/');
};

const isTypeVideo = file =>
  (file.content_type || file.type || '').startsWith('video/');

const previewFailed = attachment => failedPreviews.value.add(attachment);

const fileLabel = file => {
  const name = file.filename || file.name || '';
  const extension = name.includes('.') ? name.split('.').pop() : '';
  return extension.slice(0, 5).toUpperCase() || '📄';
};

const fileName = file => {
  return file.filename || file.name;
};
</script>

<template>
  <div class="flex flex-wrap gap-y-1 gap-x-2 overflow-auto max-h-[12.5rem]">
    <div
      v-for="(attachment, index) in nonRecordedAudioAttachments"
      :key="attachment.id"
      class="flex items-center p-1 bg-n-slate-3 gap-2 rounded-md w-[18rem] max-w-full min-w-0"
    >
      <div
        class="flex-shrink-0 size-10 flex items-center justify-center rounded bg-n-slate-4 overflow-hidden"
      >
        <img
          v-if="
            attachment.thumb &&
            isTypeImage(attachment.resource) &&
            !failedPreviews.has(attachment)
          "
          class="object-cover size-10 rounded-sm"
          :src="attachment.thumb"
          :alt="fileName(attachment.resource)"
          @error="previewFailed(attachment)"
        />
        <video
          v-else-if="
            attachment.thumb &&
            isTypeVideo(attachment.resource) &&
            !failedPreviews.has(attachment)
          "
          class="object-cover size-10"
          :src="attachment.thumb"
          muted
          playsinline
          preload="metadata"
          @error="previewFailed(attachment)"
        />
        <span v-else class="text-[10px] font-semibold text-n-slate-12">
          {{ fileLabel(attachment.resource) }}
        </span>
      </div>
      <div class="flex-1 min-w-0" :title="fileName(attachment.resource)">
        <span class="block truncate text-sm font-medium">
          {{ fileName(attachment.resource) }}
        </span>
      </div>
      <div class="flex-shrink-0">
        <span class="overflow-hidden text-xs text-ellipsis whitespace-nowrap">
          {{ formatFileSize(attachment.resource) }}
        </span>
      </div>
      <div class="flex items-center justify-center">
        <Button
          ghost
          slate
          xs
          icon="i-lucide-x"
          @click="onRemoveAttachment(index)"
        />
      </div>
    </div>
  </div>
</template>

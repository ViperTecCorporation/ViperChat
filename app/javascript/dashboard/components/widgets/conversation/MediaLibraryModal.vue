<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import GalleryView from './components/GalleryView.vue';
import { downloadFile } from '@chatwoot/utils';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  attachments: {
    type: Array,
    default: () => [],
  },
  messages: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const dialogRef = ref(null);
const activeTab = ref('media');
const previewAttachment = ref(null);
const showGallery = ref(false);
const { t } = useI18n();

const getAttachmentUrl = attachment =>
  attachment?.data_url ||
  attachment?.dataUrl ||
  attachment?.thumb_url ||
  attachment?.thumbUrl ||
  attachment?.file_url ||
  attachment?.fileUrl ||
  attachment?.download_url ||
  attachment?.downloadUrl ||
  attachment?.external_url ||
  attachment?.externalUrl ||
  attachment?.url ||
  '';

const getExtension = attachment => {
  const type = (
    attachment?.file_type ||
    attachment?.fileType ||
    attachment?.content_type ||
    attachment?.contentType ||
    attachment?.mime_type ||
    attachment?.mimeType ||
    ''
  ).toString();
  const byType =
    attachment?.extension ||
    (type.includes('/') ? type.split('/')[1] : type.includes('.') ? type.split('.').pop() : '');

  const byName =
    attachment?.file_name ||
    attachment?.filename ||
    attachment?.name ||
    attachment?.title ||
    '';

  if (byType) return byType.toLowerCase();
  if (byName && byName.includes('.')) {
    const parts = byName.split('.');
    return parts.pop().toLowerCase();
  }

  const url = getAttachmentUrl(attachment);
  if (!url) return '';
  const cleanUrl = url.split('?')[0];
  const segments = cleanUrl.split('.');
  return segments.length > 1 ? segments.pop().toLowerCase() : '';
};

const getNormalizedType = attachment => {
  const rawType = (
    attachment?.file_type ||
    attachment?.fileType ||
    attachment?.content_type ||
    attachment?.contentType ||
    attachment?.mime_type ||
    attachment?.mimeType ||
    ''
  )
    .toString()
    .toLowerCase();
  const ext = getExtension(attachment);
  const url = getAttachmentUrl(attachment);

  if (rawType.includes('audio')) return 'audio';
  if (rawType.includes('video') || rawType.includes('ig_reel')) return 'video';
  if (rawType.includes('image')) return 'image';

  if (url.startsWith('data:')) {
    if (url.includes('audio')) return 'audio';
    if (url.includes('video')) return 'video';
    if (url.includes('image')) return 'image';
  }

  const audioExts = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'flac', 'opus', 'amr'];
  const videoExts = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'];
  const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'tiff', 'svg'];

  if (audioExts.includes(ext)) return 'audio';
  if (videoExts.includes(ext)) return 'video';
  if (imageExts.includes(ext)) return 'image';

  return 'unknown';
};

const isImage = attachment => getNormalizedType(attachment) === 'image';
const isVideo = attachment => getNormalizedType(attachment) === 'video';
const isAudio = attachment => getNormalizedType(attachment) === 'audio';
const isMediaFile = attachment => ['image', 'video', 'audio'].includes(getNormalizedType(attachment));

const getDisplayName = attachment => {
  const name =
    attachment?.file_name ||
    attachment?.filename ||
    attachment?.name ||
    attachment?.title ||
    '';
  if (name) return name;
  const url = getAttachmentUrl(attachment);
  if (!url) return attachment?.id || '';
  const last = url.split('/').pop();
  return last ? decodeURIComponent(last.split('?')[0]) : attachment?.id || '';
};

const getLinkPreview = url => {
  try {
    const parsed = new URL(url);
    return `${parsed.origin}/favicon.ico`;
  } catch (error) {
    return '';
  }
};

const onPreviewError = event => {
  if (event?.target) {
    event.target.style.display = 'none';
  }
};

const downloadAttachment = async attachment => {
  const url = getAttachmentUrl(attachment);
  if (!url) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
    return;
  }
  const type = attachment?.file_type || attachment?.fileType;
  const extension = getExtension(attachment);
  const fileName = getDisplayName(attachment) || `attachment${extension ? `.${extension}` : ''}`;
  try {
    await downloadFile({ url, type, extension, fileName });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  }
};

const openDocument = (attachment, event) => {
  const url = getAttachmentUrl(attachment);
  event?.preventDefault?.();
  event?.stopPropagation?.();

  if (!url) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
    return;
  }

  const opened = window.open(url, '_blank', 'noopener');
  if (!opened) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  }
};

watch(
  () => props.show,
  value => {
    if (value) {
      dialogRef.value?.open();
    } else {
      dialogRef.value?.close();
      showGallery.value = false;
      previewAttachment.value = null;
      activeTab.value = 'media';
    }
  },
  { flush: 'post', immediate: true }
);

watch(
  showGallery,
  value => {
    if (!value && props.show) {
      nextTick(() => dialogRef.value?.open());
    }
  },
  { flush: 'post' }
);

const close = () => emit('close');

const toDate = value => {
  const parsed = Number(value);
  if (!Number.isNaN(parsed)) {
    return parsed > 1000000000000 ? new Date(parsed) : new Date(parsed * 1000);
  }
  const asDate = new Date(value);
  return Number.isNaN(asDate.getTime()) ? new Date() : asDate;
};

const monthKey = date => `${date.getFullYear()}-${date.getMonth() + 1}`;

const monthLabel = date => {
  const now = new Date();
  if (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth()
  ) {
    return t('CONVERSATION.MEDIA_LIBRARY.THIS_MONTH');
  }
  return new Intl.DateTimeFormat('pt-BR', {
    month: 'long',
    year: 'numeric',
  }).format(date);
};

const groupByMonth = items => {
  return items.reduce((acc, item) => {
    const date = toDate(item.created_at || item.timestamp || Date.now());
    const key = monthKey(date);
    const label = monthLabel(date);
    if (!acc[key]) {
      acc[key] = { label, items: [] };
    }
    acc[key].items.push({ ...item, createdAtDate: date });
    return acc;
  }, {});
};

const attachmentList = computed(() => props.attachments || []);

const mediaAttachments = computed(() =>
  attachmentList.value
    .filter(attachment => isMediaFile(attachment))
    .sort(
      (a, b) =>
        toDate(b.created_at || b.timestamp).getTime() -
        toDate(a.created_at || a.timestamp).getTime()
    )
);

const documents = computed(() =>
  attachmentList.value
    .filter(attachment => !isMediaFile(attachment))
    .sort(
      (a, b) =>
        toDate(b.created_at || b.timestamp).getTime() -
        toDate(a.created_at || a.timestamp).getTime()
    )
);

const urlRegex = /https?:\/\/[^\s<>"']+/gi;

const links = computed(() => {
  return (props.messages || []).flatMap(message => {
    const rawContent = message.content || '';
    const matches = rawContent.match(urlRegex) || [];
    return matches.map(url => ({
      url,
      sender: message.sender,
      created_at: message.created_at,
    }));
  });
});

const groupedDocs = computed(() => groupByMonth(documents.value));
const groupedLinks = computed(() => groupByMonth(links.value));

const mediaSummary = computed(() => {
  const photos = mediaAttachments.value.filter(item => isImage(item)).length;
  const videos = mediaAttachments.value.filter(item => isVideo(item)).length;
  const audios = mediaAttachments.value.filter(item => isAudio(item)).length;
  const total = photos + videos + audios;

  return {
    photos,
    videos,
    audios,
    total,
  };
});

const formatSize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
};

const formatDateTime = value =>
  new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(toDate(value));

const openPreview = attachment => {
  previewAttachment.value = attachment;
  showGallery.value = true;
};
</script>

<template>
  <Dialog
    v-if="show && !showGallery"
    ref="dialogRef"
    width="3xl"
    :overflow-y-auto="true"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="close"
  >
    <template #default>
      <div class="flex flex-col gap-4">
        <div
          class="sticky top-0 z-10 flex items-center justify-between gap-3 px-1 py-2 bg-n-alpha-3 backdrop-blur-sm"
        >
          <div class="text-sm font-medium text-n-slate-12">
            {{ $t('CONVERSATION.MEDIA_LIBRARY.TITLE') }}
          </div>
          <button
            type="button"
            class="p-1 rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
            @click="close"
          >
            <span class="i-lucide-x w-5 h-5" />
          </button>
        </div>
        <div class="flex items-center gap-2">
          <Button
            size="sm"
            variant="faded"
            :color="activeTab === 'media' ? 'blue' : 'slate'"
            class="min-w-[6rem]"
            @click="activeTab = 'media'"
          >
            <span class="flex items-center gap-2">
              <span>{{ $t('CONVERSATION.MEDIA_LIBRARY.TAB_MEDIA') }}</span>
              <span
                class="min-w-[1.75rem] px-2 rounded-md text-xs leading-5 font-medium text-center text-n-slate-11 outline outline-1 outline-n-strong"
              >
                {{ mediaSummary.total }}
              </span>
            </span>
          </Button>
          <Button
            size="sm"
            variant="faded"
            :color="activeTab === 'docs' ? 'blue' : 'slate'"
            class="min-w-[6rem]"
            @click="activeTab = 'docs'"
          >
            <span class="flex items-center gap-2">
              <span>{{ $t('CONVERSATION.MEDIA_LIBRARY.TAB_DOCS') }}</span>
              <span
                class="min-w-[1.75rem] px-2 rounded-md text-xs leading-5 font-medium text-center text-n-slate-11 outline outline-1 outline-n-strong"
              >
                {{ documents.length }}
              </span>
            </span>
          </Button>
          <Button
            size="sm"
            variant="faded"
            :color="activeTab === 'links' ? 'blue' : 'slate'"
            class="min-w-[6rem]"
            @click="activeTab = 'links'"
          >
            <span class="flex items-center gap-2">
              <span>{{ $t('CONVERSATION.MEDIA_LIBRARY.TAB_LINKS') }}</span>
              <span
                class="min-w-[1.75rem] px-2 rounded-md text-xs leading-5 font-medium text-center text-n-slate-11 outline outline-1 outline-n-strong"
              >
                {{ links.length }}
              </span>
            </span>
          </Button>
        </div>

        <div v-if="isLoading" class="flex justify-center py-12">
          <div class="flex items-center gap-2 text-sm text-n-slate-11">
            <span class="i-lucide-loader-2 animate-spin" />
            <span>{{ $t('CONVERSATION.MEDIA_LIBRARY.LOADING') }}</span>
          </div>
        </div>

        <div v-else class="flex flex-col gap-6">
          <div v-if="activeTab === 'media'" class="flex flex-col gap-4">
            <div class="flex flex-wrap gap-4 text-sm text-n-slate-11">
              <span class="inline-flex items-center gap-1">
                <span class="i-lucide-image w-4 h-4" />
                <span>
                  {{ mediaSummary.photos }}
                  {{ $t('CONVERSATION.MEDIA_LIBRARY.PHOTOS_LABEL') }}
                </span>
              </span>
              <span class="inline-flex items-center gap-1">
                <span class="i-lucide-clapperboard w-4 h-4" />
                <span>
                  {{ mediaSummary.videos }}
                  {{ $t('CONVERSATION.MEDIA_LIBRARY.VIDEOS_LABEL') }}
                </span>
              </span>
              <span class="inline-flex items-center gap-1">
                <span class="i-lucide-waveform w-4 h-4" />
                <span>
                  {{ mediaSummary.audios }}
                  {{ $t('CONVERSATION.MEDIA_LIBRARY.AUDIOS_LABEL') }}
                </span>
              </span>
            </div>
            <div
              v-if="mediaAttachments.length"
              class="grid grid-cols-2 md:grid-cols-3 gap-3"
            >
              <button
                v-for="attachment in mediaAttachments"
                :key="attachment.id"
                type="button"
                class="flex flex-col gap-2 p-2 rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-left"
                @click="openPreview(attachment)"
              >
                <div
                  class="w-full aspect-video overflow-hidden rounded-md bg-n-alpha-3 flex items-center justify-center"
                >
                  <img
                    v-if="isImage(attachment)"
                    class="object-cover w-full h-full"
                    :src="attachment.thumb_url || attachment.data_url"
                    :alt="attachment.file_name || 'image'"
                  />
                  <video
                    v-else-if="isVideo(attachment)"
                    class="object-cover w-full h-full"
                    :src="attachment.thumb_url || attachment.data_url"
                    muted
                  />
                  <div
                    v-else
                    class="flex flex-col items-center justify-center w-full h-full gap-2 text-n-slate-11"
                  >
                    <span class="i-lucide-waveform w-6 h-6" />
                    <span class="text-xs truncate px-2 text-center">
                      {{ getDisplayName(attachment) }}
                    </span>
                  </div>
                </div>
                <div class="flex items-center justify-between text-xs text-n-slate-11">
                  <span class="truncate">
                    {{ attachment.file_name || attachment.filename || attachment.id }}
                  </span>
                  <span class="flex items-center gap-1">
                    <i class="i-lucide-clock-3 w-3.5 h-3.5" />
                    {{ formatDateTime(attachment.created_at || attachment.timestamp) }}
                  </span>
                </div>
              </button>
            </div>
            <div
              v-else
              class="flex items-center justify-center py-12 text-sm text-n-slate-11"
            >
              {{ $t('CONVERSATION.MEDIA_LIBRARY.EMPTY') }}
            </div>
          </div>

          <div v-if="activeTab === 'docs'" class="flex flex-col gap-3">
            <div
              v-if="documents.length"
              class="flex flex-col gap-4"
            >
              <div
                v-for="group in Object.values(groupedDocs)"
                :key="group.label"
                class="flex flex-col gap-2"
              >
                <div class="text-xs font-medium text-n-slate-12 uppercase">
                  {{ group.label }}
                </div>
                <div class="flex flex-col gap-2">
                  <a
                    v-for="doc in group.items"
                    :key="doc.id"
                    class="flex items-center gap-3 p-3 rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-left no-underline"
                    :href="getAttachmentUrl(doc) || undefined"
                    :download="getDisplayName(doc) || undefined"
                    target="_blank"
                    rel="noopener noreferrer"
                    @click.prevent.stop="openDocument(doc, $event)"
                  >
                    <span class="i-lucide-file-text w-5 h-5 text-n-slate-11 flex-shrink-0" />
                    <div class="flex flex-col min-w-0 gap-0.5">
                      <span class="text-sm text-n-slate-12 truncate">
                        {{ getDisplayName(doc) }}
                      </span>
                      <span class="text-xs text-n-slate-11 flex items-center gap-2">
                        <span class="flex items-center gap-1">
                          <i class="i-lucide-clock-3 w-3.5 h-3.5" />
                          {{ formatDateTime(doc.created_at || doc.timestamp) }}
                        </span>
                        <span v-if="doc.file_size" class="flex items-center gap-1">
                          <span class="i-lucide-database w-3.5 h-3.5" />
                          {{ formatSize(doc.file_size) }}
                        </span>
                      </span>
                    </div>
                    <span class="i-lucide-download w-4 h-4 text-n-slate-11 flex-shrink-0" />
                  </a>
                </div>
              </div>
              <div class="text-right text-xs text-n-slate-11">
                {{
                  $t('CONVERSATION.MEDIA_LIBRARY.DOC_COUNT', {
                    count: documents.length,
                  })
                }}
              </div>
            </div>
            <div
              v-else
              class="flex items-center justify-center py-12 text-sm text-n-slate-11"
            >
              {{ $t('CONVERSATION.MEDIA_LIBRARY.EMPTY') }}
            </div>
          </div>

          <div v-if="activeTab === 'links'" class="flex flex-col gap-3">
            <div v-if="links.length" class="flex flex-col gap-4">
              <div
                v-for="group in Object.values(groupedLinks)"
                :key="group.label"
                class="flex flex-col gap-2"
              >
                <div class="text-xs font-medium text-n-slate-12 uppercase">
                  {{ group.label }}
                </div>
                <div class="flex flex-col gap-2">
                  <a
                    v-for="link in group.items"
                    :key="`${link.url}-${link.created_at}`"
                    class="flex items-center justify-between gap-3 p-3 rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
                    :href="link.url"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <span class="flex items-center gap-3 truncate">
                      <span
                        class="w-8 h-8 rounded-md bg-n-alpha-3 flex items-center justify-center overflow-hidden flex-shrink-0"
                      >
                        <img
                          v-if="getLinkPreview(link.url)"
                          :src="getLinkPreview(link.url)"
                          class="w-full h-full object-contain"
                          :alt="link.url"
                          @error="onPreviewError"
                        />
                        <span v-else class="i-lucide-link-2 w-4 h-4 text-n-slate-11" />
                      </span>
                      <span class="flex items-center gap-2 truncate">
                        <span class="i-lucide-link-2 w-4 h-4 text-n-slate-11" />
                        <span class="truncate">{{ link.url }}</span>
                      </span>
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{ formatDateTime(link.created_at) }}
                    </span>
                  </a>
                </div>
              </div>
              <div class="text-right text-xs text-n-slate-11">
                {{
                  $t('CONVERSATION.MEDIA_LIBRARY.LINK_COUNT', {
                    count: links.length,
                  })
                }}
              </div>
            </div>
            <div
              v-else
              class="flex items-center justify-center py-12 text-sm text-n-slate-11"
            >
              {{ $t('CONVERSATION.MEDIA_LIBRARY.EMPTY') }}
            </div>
          </div>
        </div>
      </div>
    </template>
  </Dialog>
  <GalleryView
    v-if="previewAttachment && showGallery"
    v-model:show="showGallery"
    :attachment="previewAttachment"
    :all-attachments="mediaAttachments"
    @close="showGallery = false"
  />
</template>

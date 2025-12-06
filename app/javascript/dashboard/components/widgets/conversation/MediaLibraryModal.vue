<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import GalleryView from './components/GalleryView.vue';

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

watch(
  () => props.show,
  value => {
    if (value) {
      dialogRef.value?.open();
    } else {
      dialogRef.value?.close();
      showGallery.value = false;
      previewAttachment.value = null;
    }
  }
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
    .filter(attachment =>
      ['image', 'video', 'audio', 'ig_reel'].includes(attachment.file_type)
    )
    .sort(
      (a, b) =>
        toDate(b.created_at || b.timestamp).getTime() -
        toDate(a.created_at || a.timestamp).getTime()
    )
);

const documents = computed(() =>
  attachmentList.value
    .filter(
      attachment =>
        !['image', 'video', 'audio', 'ig_reel'].includes(attachment.file_type)
    )
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
  const photos = mediaAttachments.value.filter(
    item => item.file_type === 'image'
  ).length;
  const videos = mediaAttachments.value.filter(
    item => item.file_type === 'video' || item.file_type === 'ig_reel'
  ).length;
  const audios = mediaAttachments.value.filter(
    item => item.file_type === 'audio'
  ).length;

  return {
    photos,
    videos,
    audios,
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
    v-if="show"
    ref="dialogRef"
    width="3xl"
    :overflow-y-auto="true"
    :title="$t('CONVERSATION.MEDIA_LIBRARY.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="close"
  >
    <template #default>
      <div class="flex flex-col gap-4">
        <div class="flex items-center gap-2">
          <Button
            size="sm"
            variant="faded"
            :color="activeTab === 'media' ? 'blue' : 'slate'"
            :label="$t('CONVERSATION.MEDIA_LIBRARY.TAB_MEDIA')"
            class="min-w-[6rem]"
            @click="activeTab = 'media'"
          />
          <Button
            size="sm"
            variant="faded"
            :color="activeTab === 'docs' ? 'blue' : 'slate'"
            :label="$t('CONVERSATION.MEDIA_LIBRARY.TAB_DOCS')"
            class="min-w-[6rem]"
            @click="activeTab = 'docs'"
          />
          <Button
            size="sm"
            variant="faded"
            :color="activeTab === 'links' ? 'blue' : 'slate'"
            :label="$t('CONVERSATION.MEDIA_LIBRARY.TAB_LINKS')"
            class="min-w-[6rem]"
            @click="activeTab = 'links'"
          />
        </div>

        <div v-if="isLoading" class="flex justify-center py-12">
          <div class="flex items-center gap-2 text-sm text-n-slate-11">
            <span class="i-lucide-loader-2 animate-spin" />
            <span>{{ $t('CONVERSATION.MEDIA_LIBRARY.LOADING') }}</span>
          </div>
        </div>

        <div v-else class="flex flex-col gap-6">
          <div v-if="activeTab === 'media'" class="flex flex-col gap-4">
            <div class="text-sm text-n-slate-11">
              {{
                $t('CONVERSATION.MEDIA_LIBRARY.MEDIA_SUMMARY', {
                  photos: mediaSummary.photos,
                  videos: mediaSummary.videos,
                  audios: mediaSummary.audios,
                })
              }}
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
                    v-if="attachment.file_type === 'image'"
                    class="object-cover w-full h-full"
                    :src="attachment.thumb_url || attachment.data_url"
                    :alt="attachment.file_name || 'image'"
                  />
                  <video
                    v-else-if="attachment.file_type === 'video'"
                    class="object-cover w-full h-full"
                    :src="attachment.thumb_url || attachment.data_url"
                    muted
                  />
                  <div
                    v-else
                    class="flex items-center justify-center w-full h-full text-n-slate-11"
                  >
                    <span class="i-lucide-waveform w-6 h-6" />
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
                  <div
                    v-for="doc in group.items"
                    :key="doc.id"
                    class="flex items-center gap-3 p-3 rounded-lg bg-n-alpha-2"
                  >
                    <span class="i-lucide-file-text w-5 h-5 text-n-slate-11" />
                    <div class="flex flex-col min-w-0">
                      <span class="text-sm text-n-slate-12 truncate">
                        {{ doc.file_name || doc.filename || doc.id }}
                      </span>
                      <span class="text-xs text-n-slate-11">
                        {{ formatDateTime(doc.created_at || doc.timestamp) }}
                        <span v-if="doc.file_size"> · {{ formatSize(doc.file_size) }}</span>
                      </span>
                    </div>
                  </div>
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
                    <span class="flex items-center gap-2 truncate">
                      <span class="i-lucide-link-2 w-4 h-4 text-n-slate-11" />
                      <span class="truncate">{{ link.url }}</span>
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

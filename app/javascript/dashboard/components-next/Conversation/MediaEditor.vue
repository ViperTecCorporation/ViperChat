<script setup>
/* eslint-disable no-restricted-syntax, no-await-in-loop, no-continue -- Bound memory and preserve attachment order. */
import {
  computed,
  ref,
  watch,
  onMounted,
  onBeforeUnmount,
  nextTick,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';
import MediaImageCanvas from './MediaImageCanvas.vue';
import MediaPreviewZoom from './MediaPreviewZoom.vue';
import { prepareImage, prepareVideo } from 'dashboard/helper/mediaPreparation';
import {
  isEditableMedia,
  formatMediaTime,
  MEDIA_LIMIT,
  VIDEO_LIMIT,
} from 'dashboard/helper/mediaProfiles';
import { MEDIA_FONTS } from 'dashboard/helper/mediaTextStyle';

const props = defineProps({
  files: { type: Array, required: true },
  caption: { type: String, default: '' },
  recipient: { type: String, default: '' },
  maxCaption: { type: Number, default: 1024 },
  maxVideoOutputBytes: { type: Number, default: VIDEO_LIMIT },
  submitFile: { type: Function, required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const label = key => t(`MEDIA_EDITOR.${key}`);
const entries = ref([]);
const selected = ref(0);
const current = computed(() => entries.value[selected.value]);
const video = computed(() => current.value?.file.type.startsWith('video/'));
const tool = ref('');
const color = ref('#ffffff');
const text = ref('');
const canvas = ref(null);
const previewActive = ref(false);
function previewChanged(value) {
  previewActive.value = value;
  if (value) canvas.value?.stopInteraction();
}
const font = ref('Arial');
const bold = ref(false);
const italic = ref(false);
const underline = ref(false);
const shadow = ref(false);
const textStyles = computed(() => [
  {
    key: 'BOLD',
    icon: 'i-lucide-bold',
    enabled: bold.value,
    toggle: () => {
      bold.value = !bold.value;
    },
  },
  {
    key: 'ITALIC',
    icon: 'i-lucide-italic',
    enabled: italic.value,
    toggle: () => {
      italic.value = !italic.value;
    },
  },
  {
    key: 'UNDERLINE',
    icon: 'i-lucide-underline',
    enabled: underline.value,
    toggle: () => {
      underline.value = !underline.value;
    },
  },
  {
    key: 'SHADOW',
    icon: 'i-lucide-sun-moon',
    enabled: shadow.value,
    toggle: () => {
      shadow.value = !shadow.value;
    },
  },
]);
const thickness = ref(4);
const textSelected = ref(false);
const showEmojis = ref(false);
function selection(value) {
  textSelected.value = !!value;
  if (value) {
    tool.value = 'text';
    text.value = value.text;
    font.value = value.font;
    color.value = value.color;
    bold.value = !!value.bold;
    italic.value = !!value.italic;
    underline.value = !!value.underline;
    shadow.value = !!value.shadow;
  }
}
async function chooseEmoji(value) {
  showEmojis.value = false;
  tool.value = 'text';
  text.value = value.emoji;
  await nextTick();
  canvas.value?.addText(value.emoji);
}
async function applyTextStyle() {
  await nextTick();
  if (textSelected.value) canvas.value?.updateText();
}
const busy = ref(false);
const imageBusy = ref(false);
const sending = ref(false);
const progress = ref(0);
const uploadStatus = ref({ phase: 'PREPARING', percent: null });
const sendingName = ref('');
const uploadQuietSeconds = ref(0);
let uploadLastUpdate = 0;
let uploadTimer;
const error = ref('');
const exportIssues = ref([]);
function diagnosticValue(value) {
  if (value === null || value === undefined) return label('DIAGNOSTIC_UNKNOWN');
  if (typeof value === 'boolean')
    return label(value ? 'DIAGNOSTIC_YES' : 'DIAGNOSTIC_NO');
  return typeof value === 'number'
    ? String(Math.round(value * 1000) / 1000)
    : value;
}
const notice = ref('');
const fileInput = ref(null);
const dialog = ref(null);
const player = ref(null);
const seen = new WeakSet();
let controller;
let active = true;
let previousFocus;
let hadOverflow;
let captionAssigned = false;

function addFiles(files) {
  if (busy.value) return;
  for (const file of files) {
    if (seen.has(file)) continue;
    if (file.type.startsWith('video/') && file.size > VIDEO_LIMIT) {
      error.value = label('VIDEO_INPUT_TOO_LARGE');
      continue;
    }
    if (!isEditableMedia(file)) {
      error.value = label('UNSUPPORTED_FILE');
      continue;
    }
    if (
      entries.value.length >= MEDIA_LIMIT ||
      entries.value.reduce((sum, item) => sum + item.file.size, 0) + file.size >
        512 * 1024 * 1024
    ) {
      error.value = label('QUEUE_LIMIT');
      break;
    }
    seen.add(file);
    entries.value.push({
      id: crypto.randomUUID(),
      file,
      url: URL.createObjectURL(file),
      caption: captionAssigned ? '' : props.caption,
      quality: 'hd',
      history: [],
      scene: null,
      duration: 0,
      start: 0,
      end: 0,
      mute: false,
      useServer: false,
    });
    captionAssigned = true;
  }
}
watch(
  () => props.files.length,
  () => addFiles(props.files),
  { immediate: true }
);
watch(selected, () => {
  previewActive.value = false;
  tool.value = '';
  text.value = '';
  textSelected.value = false;
  showEmojis.value = false;
});
function chooseFiles(event) {
  addFiles(Array.from(event.target.files));
  event.target.value = '';
}
function changedImage(file, scene) {
  const entry = current.value;
  if (!entry || !active) return;
  entry.history.push({ file: entry.file, scene: entry.scene });
  if (entry.history.length > 5) entry.history.shift();
  URL.revokeObjectURL(entry.url);
  entry.file = file;
  entry.scene = scene;
  entry.url = URL.createObjectURL(file);
}
function undo() {
  const entry = current.value;
  if (!entry?.history.length) return;
  URL.revokeObjectURL(entry.url);
  const previous = entry.history.pop();
  entry.file = previous.file;
  entry.scene = previous.scene;
  entry.url = URL.createObjectURL(entry.file);
}
function remove() {
  URL.revokeObjectURL(current.value.url);
  entries.value.splice(selected.value, 1);
  selected.value = Math.max(
    0,
    Math.min(selected.value, entries.value.length - 1)
  );
  if (!entries.value.length) emit('close');
}
function download() {
  const anchor = document.createElement('a');
  anchor.href = current.value.url;
  anchor.download = current.value.file.name;
  anchor.click();
}
function loadedVideo(event) {
  const duration = event.target.duration;
  if (!Number.isFinite(duration)) {
    error.value = label('INVALID_VIDEO');
    return;
  }
  current.value.duration = duration;
  if (!current.value.end) current.value.end = duration;
}
function previewTime() {
  if (player.value.currentTime > current.value.end) player.value.pause();
}
function serverFallback() {
  current.value.useServer = true;
  current.value.start = 0;
  current.value.end = current.value.duration;
  current.value.mute = false;
  error.value = '';
}
function close() {
  if (sending.value) return;
  controller?.abort();
  emit('close');
}
function trapFocus(event) {
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
  }
  if (event.key !== 'Tab') return;
  const nodes = [
    ...dialog.value.querySelectorAll(
      'button:not([disabled]), input:not([disabled]), textarea:not([disabled]), [tabindex="0"]'
    ),
  ].filter(el => el.getClientRects().length);
  const first = nodes[0];
  const last = nodes.at(-1);
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last?.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first?.focus();
  }
}
async function send() {
  if (busy.value || imageBusy.value || !entries.value.length) return;
  if (entries.value.some(entry => entry.caption.length > props.maxCaption)) {
    error.value = label('CAPTION_LIMIT');
    return;
  }
  busy.value = true;
  error.value = '';
  exportIssues.value = [];
  notice.value = '';
  controller = new AbortController();
  try {
    const prepared = [];
    for (const [index, entry] of entries.value.entries()) {
      selected.value = index;
      progress.value = 0;
      // eslint-disable-next-line no-nested-ternary
      const output = entry.useServer
        ? entry.file
        : entry.file.type.startsWith('video/')
          ? await prepareVideo(
              entry.file,
              {
                quality: entry.quality,
                mute: entry.mute,
                start: entry.start,
                end: entry.end,
                maxOutputBytes: props.maxVideoOutputBytes,
              },
              {
                signal: controller.signal,
                onNotice: code => {
                  if (
                    ['AUDIO_BITRATE_FALLBACK', 'VIDEO_BITRATE_RETRY'].includes(
                      code
                    )
                  )
                    notice.value = label(code);
                },
                onProgress: value => {
                  progress.value = Math.round(value * 100);
                },
              }
            )
          : await prepareImage(entry.file, entry.quality);
      if (controller.signal.aborted || !active) return;
      prepared.push({ entry, output });
    }
    sending.value = true;
    for (const { entry, output } of prepared) {
      if (!active) return;
      sendingName.value = output.name;
      uploadStatus.value = { phase: 'PREPARING', percent: null };
      uploadLastUpdate = Date.now();
      uploadQuietSeconds.value = 0;
      const result = await props.submitFile(output, entry.caption, {
        // eslint-disable-next-line no-loop-func -- Sequential upload; callback stops updating after unmount.
        onProgress: status => {
          if (active) {
            uploadStatus.value = status;
            uploadLastUpdate = Date.now();
            uploadQuietSeconds.value = 0;
          }
        },
        videoQuality: entry.file.type.startsWith('video/')
          ? entry.quality
          : undefined,
      });
      if (!active) return;
      if (result.dispatched) {
        URL.revokeObjectURL(entry.url);
        entries.value = entries.value.filter(item => item.id !== entry.id);
        selected.value = 0;
      }
      // Once handed to the conversation, retries belong to its message bubble.
      // Do not leave an empty editor open even if the HTTP response was lost.
      if (!entries.value.length) {
        if (!result.ok) useAlert(label('SEND_FAILED'));
        emit('close');
        return;
      }
      if (!result.ok) {
        error.value = label(
          result.dispatched ? 'SEND_FAILED' : 'UPLOAD_FAILED'
        );
        return;
      }
    }
    emit('close');
  } catch (exception) {
    exportIssues.value = exception.issues || [];
    if (exception.name !== 'AbortError')
      error.value = label(
        [
          'VIDEO_INPUT_TOO_LARGE',
          'VIDEO_TOO_LARGE',
          'VIDEO_EXPORT_NONCONFORMING',
          'INVALID_VIDEO',
          'VIDEO_UNSUPPORTED',
        ].includes(exception.message)
          ? exception.message
          : 'IMAGE_ERROR'
      );
  } finally {
    busy.value = false;
    sending.value = false;
  }
}
onMounted(async () => {
  uploadTimer = setInterval(() => {
    if (sending.value)
      uploadQuietSeconds.value = Math.floor(
        (Date.now() - uploadLastUpdate) / 1000
      );
  }, 1000);
  previousFocus = document.activeElement;
  hadOverflow = document.body.classList.contains('overflow-hidden');
  document.body.classList.add('overflow-hidden');
  await nextTick();
  if (active) dialog.value?.focus();
});
onBeforeUnmount(() => {
  clearInterval(uploadTimer);
  active = false;
  controller?.abort();
  entries.value.forEach(entry => URL.revokeObjectURL(entry.url));
  if (!hadOverflow) document.body.classList.remove('overflow-hidden');
  previousFocus?.focus();
});
const toolbar = computed(() => [
  { key: 'DOWNLOAD', icon: 'i-lucide-download', action: download },
  {
    key: 'QUALITY',
    text: current.value?.quality === 'hd' ? 'HD' : 'SD',
    action: () => {
      current.value.quality = current.value.quality === 'hd' ? 'sd' : 'hd';
    },
  },
  ...(!video.value
    ? [
        { key: 'CROP', icon: 'i-lucide-crop', mode: 'crop' },
        {
          key: 'ROTATE',
          icon: 'i-lucide-rotate-cw',
          action: () => canvas.value?.rotate(),
        },
        {
          key: 'EMOJI',
          icon: 'i-lucide-smile',
          action: () => {
            showEmojis.value = !showEmojis.value;
          },
        },
        { key: 'TEXT', icon: 'i-lucide-type', mode: 'text' },
        { key: 'DRAW', icon: 'i-lucide-pencil', mode: 'draw' },
        { key: 'UNDO', icon: 'i-lucide-undo-2', action: undo },
      ]
    : [
        {
          key: 'MUTE',
          icon: current.value.mute ? 'i-lucide-volume-x' : 'i-lucide-volume-2',
          action: () => {
            current.value.mute = !current.value.mute;
          },
        },
      ]),
]);
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[10000] bg-[#000000cc] sm:p-4 flex items-center justify-center"
      @keydown.stop="trapFocus"
      @paste.stop
    >
      <section
        ref="dialog"
        role="dialog"
        aria-modal="true"
        :aria-label="label('TITLE')"
        tabindex="-1"
        class="w-full max-w-4xl h-dvh sm:h-[90dvh] bg-[#101112] text-white sm:rounded-2xl flex flex-col min-w-0 overflow-hidden pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)] outline-none"
      >
        <header class="flex items-center gap-1 p-2 shrink-0 overflow-x-auto">
          <button
            type="button"
            :aria-label="label('CLOSE')"
            :title="label('CLOSE')"
            :disabled="sending"
            class="shrink-0 size-10 rounded-full bg-white/10 grid place-items-center disabled:opacity-40"
            @click="close"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
          <div class="flex-1" />
          <button
            v-for="item in toolbar"
            :key="item.key"
            type="button"
            :aria-label="label(item.key)"
            :title="label(item.key)"
            :disabled="busy || imageBusy || !current || previewActive"
            :aria-pressed="item.mode ? tool === item.mode : undefined"
            class="shrink-0 size-10 rounded-full bg-white/10 hover:bg-white/20 grid place-items-center disabled:opacity-40"
            :class="{
              'ring-2 ring-[#2dd4bf]': item.mode && tool === item.mode,
            }"
            @click="
              item.action
                ? item.action()
                : (tool = tool === item.mode ? '' : item.mode)
            "
          >
            <Icon v-if="item.icon" :icon="item.icon" class="size-5" />
            <span v-else class="text-xs font-bold">
              {{ item.text }}
            </span>
          </button>
        </header>
        <div
          v-if="tool && !video && !previewActive"
          class="px-3 pb-2 flex flex-wrap items-center gap-2 shrink-0 max-h-[30dvh] overflow-y-auto"
        >
          <input
            v-if="tool !== 'crop'"
            v-model="color"
            type="color"
            :aria-label="label('COLOR')"
            class="w-9 h-9 shrink-0"
            :disabled="busy"
            @change="applyTextStyle"
          />
          <input
            v-if="tool === 'text'"
            v-model="text"
            :placeholder="label('TEXT_HINT')"
            :aria-label="label('TEXT')"
            maxlength="200"
            class="!m-0 !min-w-0 !bg-[#262626] !text-white !text-base flex-1 basis-32"
            :disabled="busy"
          />
          <span v-else class="text-xs text-white/80">{{
            label(tool === 'crop' ? 'CROP_HINT' : 'DRAW_HINT')
          }}</span>
          <template v-if="tool === 'text'">
            <select
              v-model="font"
              :aria-label="label('FONT')"
              :disabled="busy || imageBusy"
              class="!m-0 !w-auto !max-w-full !bg-[#262626] !text-white"
              @change="applyTextStyle"
            >
              <option
                v-for="family in MEDIA_FONTS"
                :key="family"
                :value="family"
              >
                {{ family }}
              </option>
            </select>
            <button
              v-for="style in textStyles"
              :key="style.key"
              type="button"
              :aria-label="label(style.key)"
              :title="label(style.key)"
              :aria-pressed="style.enabled"
              :disabled="busy || imageBusy"
              class="size-10 shrink-0 rounded-lg bg-white/10 grid place-items-center"
              :class="{ 'ring-2 ring-[#2dd4bf]': style.enabled }"
              @click="
                style.toggle();
                applyTextStyle();
              "
            >
              <Icon :icon="style.icon" class="size-5" />
            </button>
            <button
              type="button"
              :disabled="busy || imageBusy || !text.trim()"
              class="rounded-lg bg-white/10 px-3 py-2 disabled:opacity-40"
              @click="canvas.addText()"
            >
              {{ label('INSERT_TEXT') }}
            </button>
            <template v-if="textSelected">
              <button
                type="button"
                :disabled="busy || imageBusy || !text.trim()"
                class="rounded-lg bg-white/10 px-3 py-2 disabled:opacity-40"
                @click="canvas.updateText()"
              >
                {{ label('UPDATE_TEXT') }}
              </button>
              <button
                type="button"
                :aria-label="label('DELETE_TEXT')"
                :title="label('DELETE_TEXT')"
                :disabled="busy || imageBusy"
                class="size-10 rounded-full bg-white/10 grid place-items-center"
                @click="canvas.removeText()"
              >
                <Icon icon="i-lucide-trash-2" class="size-5" />
              </button>
            </template>
          </template>
          <label
            v-if="tool === 'draw'"
            class="flex items-center gap-2 text-xs min-w-0 !text-white"
          >
            {{ label('THICKNESS') }} {{ thickness }}
            <input
              v-model.number="thickness"
              type="range"
              min="1"
              max="32"
              :disabled="busy || imageBusy"
              class="w-28"
            />
          </label>
          <button
            v-if="tool === 'crop'"
            type="button"
            :disabled="busy || imageBusy"
            class="rounded-lg bg-n-brand text-white px-3 py-2"
            @click="
              canvas.applyCrop();
              tool = '';
            "
          >
            {{ label('APPLY_CROP') }}
          </button>
          <button
            v-if="tool === 'crop'"
            type="button"
            :disabled="busy || imageBusy"
            class="rounded-lg bg-white/10 px-3 py-2"
            @click="tool = ''"
          >
            {{ label('CANCEL_CROP') }}
          </button>
        </div>
        <div
          v-if="current"
          class="flex-1 min-h-0 min-w-0 relative flex items-center justify-center overflow-hidden bg-[#000000]"
        >
          <EmojiPicker
            v-if="showEmojis && !busy"
            class="!absolute top-2 left-2 !w-[min(22rem,calc(100%-1rem))] max-h-full"
            @select="chooseEmoji"
          />
          <video
            v-if="video"
            :key="current.id"
            ref="player"
            :src="current.url"
            :muted="current.mute"
            controls
            playsinline
            class="w-full h-full object-contain"
            @loadedmetadata="loadedVideo"
            @timeupdate="previewTime"
          />
          <MediaPreviewZoom
            v-else
            :key="current.id"
            :src="current.url"
            :disabled="busy || imageBusy"
            @active="previewChanged"
          >
            <MediaImageCanvas
              :key="current.id"
              ref="canvas"
              :file="current.file"
              :scene="current.scene"
              :tool="tool"
              :color="color"
              :text="text"
              :font="font"
              :thickness="thickness"
              :bold="bold"
              :italic="italic"
              :underline="underline"
              :shadow="shadow"
              :disabled="busy || previewActive"
              @change="changedImage"
              @selection="selection"
              @error="error = label('IMAGE_ERROR')"
              @busy="imageBusy = $event"
            />
          </MediaPreviewZoom>
        </div>
        <div
          v-if="current && video"
          class="px-3 py-2 grid grid-cols-2 gap-3 shrink-0"
        >
          <label class="text-xs">
            {{ label('START') }} {{ formatMediaTime(current.start) }}
            <input
              v-model.number="current.start"
              type="range"
              min="0"
              :max="Math.max(0, current.end - 0.1)"
              step="0.1"
              :disabled="busy"
              class="w-full"
              @input="player.currentTime = current.start"
            />
          </label>
          <label class="text-xs">
            {{ label('END') }} {{ formatMediaTime(current.end) }}
            <input
              v-model.number="current.end"
              type="range"
              :min="current.start + 0.1"
              :max="current.duration"
              step="0.1"
              :disabled="busy"
              class="w-full"
          /></label>
        </div>
        <div
          v-if="error || notice"
          role="alert"
          class="px-3 py-2 text-sm text-[#fcd34d] max-h-28 overflow-y-auto shrink-0"
        >
          {{ error || notice }}
          <details
            v-if="error && exportIssues.length"
            open
            class="mt-2 break-words"
          >
            <summary class="cursor-pointer font-semibold">
              {{ label('DIAGNOSTIC_TITLE') }}
            </summary>
            <ul class="mt-2 space-y-2" data-testid="video-export-issues">
              <li v-for="issue in exportIssues" :key="issue.field">
                <strong>
                  {{ label(`DIAGNOSTIC_FIELDS.${issue.field}`) }}
                </strong>
                : {{ diagnosticValue(issue.actual) }} —
                {{ label('DIAGNOSTIC_EXPECTED') }}
                {{ diagnosticValue(issue.expected) }}
              </li>
            </ul>
          </details>
          <button
            v-if="
              video &&
              !busy &&
              [
                label('VIDEO_UNSUPPORTED'),
                label('VIDEO_EXPORT_NONCONFORMING'),
              ].includes(error)
            "
            type="button"
            class="block underline text-left mt-1"
            @click="serverFallback"
          >
            {{ label('SERVER_FALLBACK') }}
          </button>
        </div>
        <div v-if="busy" role="status" class="px-3 py-2 shrink-0 text-sm">
          <p
            v-if="sending && uploadQuietSeconds >= 15"
            class="text-amber-300 mb-1 text-xs"
          >
            {{
              $t('MEDIA_EDITOR.UPLOAD_WAITING', { seconds: uploadQuietSeconds })
            }}
          </p>
          <p v-if="sending" class="truncate font-medium">{{ sendingName }}</p>
          <div class="flex justify-between gap-2">
            <span>{{
              sending
                ? $t(`MULTIPART_UPLOAD.${uploadStatus.phase}`)
                : label('PREPARING')
            }}</span>
            <span class="shrink-0 tabular-nums">{{
              sending
                ? uploadStatus.percent === null
                  ? ''
                  : `${uploadStatus.percent}%`
                : `${progress}%`
            }}</span>
          </div>
          <progress
            :value="sending ? (uploadStatus.percent ?? undefined) : progress"
            max="100"
            class="block w-full h-2 mt-2 accent-[#14b8a6]"
          />
          <p
            v-if="sending && uploadStatus.total"
            class="text-xs text-white/70 mt-1 tabular-nums"
          >
            {{
              $t('MEDIA_EDITOR.UPLOAD_BYTES', {
                loaded: (uploadStatus.loaded / 1048576).toFixed(1),
                total: (uploadStatus.total / 1048576).toFixed(1),
              })
            }}
          </p>
        </div>
        <footer class="p-3 space-y-2 shrink-0 min-w-0">
          <div class="flex gap-2 overflow-x-auto pb-1">
            <button
              v-for="(entry, index) in entries"
              :key="entry.id"
              type="button"
              :aria-label="`${label('ATTACHMENT')} ${index + 1}`"
              :disabled="busy || imageBusy"
              class="relative size-12 shrink-0 rounded-lg overflow-hidden border-2"
              :class="
                index === selected ? 'border-[#2dd4bf]' : 'border-transparent'
              "
              @click="selected = index"
            >
              <img
                v-if="entry.file.type.startsWith('image/')"
                :src="entry.url"
                alt=""
                class="w-full h-full object-cover"
              />
              <span
                v-else
                class="grid place-items-center w-full h-full bg-[#262626]"
              >
                <Icon icon="i-lucide-video" class="size-6" />
              </span>
            </button>
            <button
              type="button"
              :aria-label="label('ADD')"
              :title="label('ADD')"
              :disabled="busy || imageBusy"
              class="size-12 shrink-0 rounded-lg border border-white/40 grid place-items-center"
              @click="fileInput.click()"
            >
              <Icon icon="i-lucide-plus" class="size-6" />
            </button>
            <button
              v-if="current"
              type="button"
              :aria-label="label('REMOVE')"
              :title="label('REMOVE')"
              :disabled="busy || imageBusy"
              class="size-12 shrink-0 grid place-items-center text-red-300"
              @click="remove"
            >
              <Icon icon="i-lucide-trash-2" class="size-5" />
            </button>
          </div>
          <input
            ref="fileInput"
            type="file"
            multiple
            accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,video/webm,video/x-matroska"
            class="hidden"
            @change="chooseFiles"
          />
          <textarea
            v-if="current"
            v-model="current.caption"
            :maxlength="maxCaption"
            :aria-label="label('CAPTION')"
            :placeholder="label('CAPTION')"
            :disabled="busy"
            rows="2"
            class="!m-0 !w-full !rounded-2xl !bg-[#262626] !border-white/20 !text-white !text-base resize-none"
          />
          <div class="flex items-center justify-between gap-3">
            <span class="truncate text-sm bg-white/10 rounded-lg px-3 py-2">{{
              recipient
            }}</span>
            <span v-if="current?.useServer" class="text-xs text-[#fcd34d]">{{
              label('SERVER_MODE')
            }}</span>
            <NextButton
              type="button"
              icon="i-lucide-send"
              color="blue"
              sm
              :aria-label="label('SEND')"
              :title="label('SEND')"
              :disabled="busy || imageBusy || !entries.length"
              class="!rounded-full shrink-0"
              @click="send"
            />
          </div>
        </footer>
      </section>
    </div>
  </Teleport>
</template>

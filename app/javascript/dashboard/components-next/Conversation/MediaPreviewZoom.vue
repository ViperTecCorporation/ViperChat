<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { zoomPreview } from 'dashboard/helper/mediaPreviewZoom';

const props = defineProps({
  src: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['active']);
const { t } = useI18n();
const host = ref(null);
const surface = ref(null);
const view = ref({ zoom: 1, x: 0, y: 0 });
const active = ref(false);
let image;
let observer;
let gesture;
let drag;
const center = () => ({
  x: host.value.clientWidth / 2,
  y: host.value.clientHeight / 2,
});
function setActive(value) {
  if (active.value !== value) {
    active.value = value;
    emit('active', value);
  }
}
function render() {
  if (!surface.value || !host.value || !image?.complete || !image.naturalWidth)
    return;
  const width = host.value.clientWidth;
  const height = host.value.clientHeight;
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  surface.value.width = Math.round(width * ratio);
  surface.value.height = Math.round(height * ratio);
  const context = surface.value.getContext('2d');
  context.scale(ratio, ratio);
  const fit = Math.min(
    width / image.naturalWidth,
    height / image.naturalHeight,
    1
  );
  const w = image.naturalWidth * fit * view.value.zoom;
  const h = image.naturalHeight * fit * view.value.zoom;
  view.value.x = Math.max(
    -Math.max(0, (w - width) / 2),
    Math.min(Math.max(0, (w - width) / 2), view.value.x)
  );
  view.value.y = Math.max(
    -Math.max(0, (h - height) / 2),
    Math.min(Math.max(0, (h - height) / 2), view.value.y)
  );
  context.drawImage(
    image,
    (width - w) / 2 + view.value.x,
    (height - h) / 2 + view.value.y,
    w,
    h
  );
}
function reset() {
  gesture = null;
  drag = null;
  view.value = { zoom: 1, x: 0, y: 0 };
  setActive(false);
  render();
}
function zoom(value, anchor = center()) {
  if (props.disabled) return;
  view.value = zoomPreview(view.value, value, anchor, center());
  setActive(view.value.zoom > 1);
  render();
}
function local(point) {
  const box = host.value.getBoundingClientRect();
  return { x: point.clientX - box.left, y: point.clientY - box.top };
}
function touchInfo(event) {
  const a = local(event.touches[0]);
  const b = local(event.touches[1]);
  return {
    distance: Math.hypot(a.x - b.x, a.y - b.y),
    mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 },
  };
}
function touchStart(event) {
  if (event.target.closest('button')) return;
  if (props.disabled) return;
  if (event.touches.length >= 2) {
    event.preventDefault();
    event.stopPropagation();
    gesture = { ...touchInfo(event), view: { ...view.value } };
    drag = null;
    setActive(true);
  } else if (active.value) {
    event.preventDefault();
    event.stopPropagation();
    drag = { point: local(event.touches[0]), view: { ...view.value } };
  }
}
function touchMove(event) {
  if (event.target.closest('button')) return;
  if (props.disabled || !active.value) return;
  event.preventDefault();
  event.stopPropagation();
  if (gesture && event.touches.length >= 2) {
    const next = touchInfo(event);
    view.value = zoomPreview(
      gesture.view,
      (gesture.view.zoom * next.distance) / Math.max(1, gesture.distance),
      gesture.mid,
      center()
    );
    view.value.x += next.mid.x - gesture.mid.x;
    view.value.y += next.mid.y - gesture.mid.y;
  } else if (drag && event.touches.length === 1) {
    const next = local(event.touches[0]);
    view.value.x = drag.view.x + next.x - drag.point.x;
    view.value.y = drag.view.y + next.y - drag.point.y;
  }
  render();
}
function touchEnd(event) {
  if (event.target.closest('button')) return;
  if (!active.value) return;
  event.stopPropagation();
  if (event.touches.length < 2) gesture = null;
  drag =
    event.touches.length === 1
      ? { point: local(event.touches[0]), view: { ...view.value } }
      : null;
  setActive(view.value.zoom > 1);
}
function pointerDown(event) {
  if (event.pointerType === 'touch' || props.disabled || !active.value) return;
  surface.value.setPointerCapture(event.pointerId);
  drag = { point: local(event), view: { ...view.value } };
}
function pointerMove(event) {
  if (event.pointerType === 'touch' || !drag || props.disabled) return;
  const next = local(event);
  view.value.x = drag.view.x + next.x - drag.point.x;
  view.value.y = drag.view.y + next.y - drag.point.y;
  render();
}
function load() {
  reset();
  if (image) image.onload = null;
  image = new Image();
  image.onload = render;
  image.src = props.src;
}
watch(() => props.src, load);
onMounted(() => {
  observer = new ResizeObserver(render);
  observer.observe(host.value);
  load();
});
onBeforeUnmount(() => {
  observer?.disconnect();
  if (image) image.onload = null;
});
</script>

<template>
  <div
    ref="host"
    class="relative w-full h-full min-h-0 overflow-hidden touch-none"
    @touchstart.capture="touchStart"
    @touchmove.capture="touchMove"
    @touchend.capture="touchEnd"
    @touchcancel.capture="reset"
  >
    <slot />
    <canvas
      ref="surface"
      :class="active ? 'block' : 'hidden'"
      class="absolute inset-0 w-full h-full bg-[#000000] cursor-grab active:cursor-grabbing touch-none"
      @pointerdown="pointerDown"
      @pointermove="pointerMove"
      @pointerup="drag = null"
      @pointercancel="drag = null"
    />
    <div
      class="absolute top-2 right-2 flex items-center gap-1 rounded-full bg-[#000000b3] p-1 text-white"
    >
      <button
        type="button"
        :disabled="disabled"
        :aria-label="t('MEDIA_EDITOR.ZOOM_OUT')"
        :title="t('MEDIA_EDITOR.ZOOM_OUT')"
        class="size-8 grid place-items-center rounded-full hover:bg-white/20 disabled:opacity-40"
        @click="zoom(view.zoom / 1.4)"
      >
        <Icon icon="i-lucide-zoom-out" class="size-4" />
      </button>
      <button
        type="button"
        :disabled="disabled"
        :aria-label="t('MEDIA_EDITOR.ZOOM_RESET')"
        :title="t('MEDIA_EDITOR.ZOOM_RESET')"
        class="min-w-10 h-8 px-1 text-xs rounded-full hover:bg-white/20"
        @click="reset"
      >
        {{ Math.round(view.zoom * 100) }}%
      </button>
      <button
        type="button"
        :disabled="disabled"
        :aria-label="t('MEDIA_EDITOR.ZOOM_IN')"
        :title="t('MEDIA_EDITOR.ZOOM_IN')"
        class="size-8 grid place-items-center rounded-full hover:bg-white/20 disabled:opacity-40"
        @click="zoom(view.zoom * 1.4)"
      >
        <Icon icon="i-lucide-zoom-in" class="size-4" />
      </button>
    </div>
    <span
      v-if="active"
      class="absolute bottom-2 inset-x-2 text-center text-xs text-white bg-[#000000b3] rounded-lg px-2 py-1 pointer-events-none"
    >
      {{ t('MEDIA_EDITOR.ZOOM_PREVIEW') }}
    </span>
  </div>
</template>

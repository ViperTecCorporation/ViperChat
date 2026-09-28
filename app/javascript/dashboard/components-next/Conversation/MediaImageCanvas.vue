<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import Konva from 'konva';
import { fitMediaText } from 'dashboard/helper/mediaTextLayout';
import { mediaTextStyle } from 'dashboard/helper/mediaTextStyle';

const props = defineProps({
  file: { type: File, required: true },
  scene: { type: Object, default: null },
  tool: { type: String, default: '' },
  color: { type: String, default: '#ffffff' },
  text: { type: String, default: '' },
  font: { type: String, default: 'Arial' },
  thickness: { type: Number, default: 4 },
  bold: Boolean,
  italic: Boolean,
  underline: Boolean,
  shadow: Boolean,
  disabled: Boolean,
});
const emit = defineEmits(['change', 'error', 'busy', 'selection']);
const host = ref(null);
let stage;
let content;
let controls;
let transformer;
let crop;
let selected;
let bitmap;
let base;
let width;
let height;
let observer;
let version = 0;
let line;
let working = false;
let lastExport;
const point = () => stage.getRelativePointerPosition();
const textStyle = fontSize =>
  mediaTextStyle(
    {
      bold: props.bold,
      italic: props.italic,
      underline: props.underline,
      shadow: props.shadow,
    },
    fontSize
  );

function select(node) {
  selected = node;
  transformer.nodes(node ? [node] : []);
  emit(
    'selection',
    node
      ? {
          text: node.text(),
          font: node.fontFamily(),
          color: node.fill(),
          bold: node.fontStyle().includes('bold'),
          italic: node.fontStyle().includes('italic'),
          underline: node.textDecoration().includes('underline'),
          shadow: node.shadowEnabled() && node.shadowBlur() > 0,
        }
      : null
  );
}
function resize() {
  if (!bitmap || !host.value) return;
  const bounds = host.value.getBoundingClientRect();
  const scale = Math.min(bounds.width / width, bounds.height / height, 1);
  stage.size({ width: width * scale, height: height * scale });
  stage.scale({ x: scale, y: scale });
}
function snapshot() {
  return {
    base,
    width,
    height,
    nodes: content.getChildren().map(node => {
      const attrs = { ...node.getAttrs() };
      delete attrs.image;
      return { className: node.getClassName(), attrs };
    }),
  };
}
async function commit() {
  if (working) return;
  working = true;
  stage.listening(false);
  emit('busy', true);
  try {
    controls.hide();
    const scene = snapshot();
    const canvas = stage.toCanvas({
      pixelRatio: Math.min(1, 4096 / Math.max(width, height)) / stage.scaleX(),
    });
    controls.show();
    const blob = await new Promise(resolve => {
      canvas.toBlob(resolve, 'image/png');
    });
    if (!blob) throw new Error('IMAGE_ERROR');
    lastExport = new File(
      [blob],
      props.file.name.replace(/\.[^.]+$/, '') + '.png',
      { type: 'image/png' }
    );
    emit('change', lastExport, scene);
  } catch {
    controls.show();
    emit('error');
  } finally {
    working = false;
    stage.listening(!props.disabled);
    emit('busy', false);
  }
}
function bindText(node) {
  fitMediaText(node, width * 0.85);
  node.draggable(true);
  node.on('dragstart', () => select(node));
  node.on('click tap', event => {
    event.cancelBubble = true;
    if (!props.disabled && !working && props.tool !== 'crop') select(node);
  });
  node.on('dragend transformend', () => {
    if (!props.disabled) commit();
  });
}
function setMode() {
  if (!bitmap) return;
  crop?.destroy();
  crop = null;
  if (props.tool !== 'text' || !selected) select(null);
  content.getChildren().forEach(node => {
    if (node.getClassName() === 'Text')
      node.listening(
        !props.disabled && props.tool !== 'crop' && props.tool !== 'draw'
      );
  });
  transformer.rotateEnabled(props.tool !== 'crop');
  transformer.keepRatio(props.tool !== 'crop');
  if (props.tool === 'crop') {
    crop = new Konva.Rect({
      x: width * 0.05,
      y: height * 0.05,
      width: width * 0.9,
      height: height * 0.9,
      stroke: '#ffffff',
      strokeWidth: 2 / stage.scaleX(),
      dash: [8, 4],
      draggable: !props.disabled,
    });
    crop.dragBoundFunc(pos => ({
      x: Math.max(
        0,
        Math.min(
          stage.width() - crop.width() * crop.scaleX() * stage.scaleX(),
          pos.x
        )
      ),
      y: Math.max(
        0,
        Math.min(
          stage.height() - crop.height() * crop.scaleY() * stage.scaleY(),
          pos.y
        )
      ),
    }));
    controls.add(crop);
    transformer.nodes([crop]);
    transformer.moveToTop();
  }
}
async function load() {
  if (props.file === lastExport) return;
  version += 1;
  const current = version;
  emit('busy', true);
  try {
    const scene = props.scene;
    const source = scene?.base || props.file;
    const image = await createImageBitmap(source);
    if (current !== version) {
      image.close();
      return;
    }
    content.destroyChildren();
    bitmap?.close();
    bitmap = image;
    base = source;
    width = scene?.width || image.width;
    height = scene?.height || image.height;
    const nodes = scene?.nodes || [
      {
        className: 'Image',
        attrs: { x: 0, y: 0, width, height, listening: false },
      },
    ];
    nodes.forEach(data => {
      const node = Konva.Node.create(data);
      if (data.className === 'Image') node.image(bitmap);
      if (data.className === 'Text') bindText(node);
      content.add(node);
    });
    resize();
    setMode();
  } catch {
    emit('error');
  } finally {
    if (current === version) emit('busy', false);
  }
}
function start(event) {
  if (props.disabled || working || !bitmap || crop || event.target !== stage)
    return;
  const pos = point();
  if (!pos) return;
  select(null);
  if (props.tool === 'draw') {
    line = new Konva.Line({
      points: [pos.x, pos.y],
      stroke: props.color,
      strokeWidth: props.thickness / stage.scaleX(),
      lineCap: 'round',
      lineJoin: 'round',
      listening: false,
    });
    content.add(line);
  }
}
function move() {
  if (!line || props.disabled) return;
  const pos = point();
  if (pos)
    line.points([
      ...line.points(),
      Math.max(0, Math.min(width, pos.x)),
      Math.max(0, Math.min(height, pos.y)),
    ]);
}
function finish() {
  if (line) {
    line = null;
    commit();
  }
}
function addText(value = props.text) {
  if (!bitmap || working || props.disabled || !value.trim()) return;
  const node = new Konva.Text({
    x: width * 0.15,
    y: height * 0.4,
    text: value,
    fill: props.color,
    fontSize: 28 / stage.scaleX(),
    fontFamily: props.font,
    ...textStyle(28 / stage.scaleX()),
  });
  bindText(node);
  content.add(node);
  select(node);
  commit();
}
function updateText() {
  if (!selected || working || props.disabled) return;
  selected.setAttrs({
    text: props.text,
    fontFamily: props.font,
    fill: props.color,
  });
  selected.setAttrs(textStyle(selected.fontSize()));
  fitMediaText(selected, width * 0.85);
  transformer.forceUpdate();
  commit();
}
function removeText() {
  if (!selected || working || props.disabled) return;
  selected.destroy();
  select(null);
  commit();
}
function applyCrop() {
  if (!crop || working || props.disabled) return;
  const x = Math.max(0, crop.x());
  const y = Math.max(0, crop.y());
  const nextWidth = Math.min(width - x, crop.width() * crop.scaleX());
  const nextHeight = Math.min(height - y, crop.height() * crop.scaleY());
  if (nextWidth < 10 || nextHeight < 10) return;
  content
    .getChildren()
    .forEach(node => node.position({ x: node.x() - x, y: node.y() - y }));
  width = nextWidth;
  height = nextHeight;
  crop.destroy();
  crop = null;
  select(null);
  resize();
  commit();
}
function rotate() {
  if (!bitmap || working || props.disabled) return;
  content.getChildren().forEach(node => {
    node.position({ x: height - node.y(), y: node.x() });
    node.rotation(node.rotation() + 90);
  });
  [width, height] = [height, width];
  resize();
  setMode();
  commit();
}
onMounted(() => {
  stage = new Konva.Stage({ container: host.value });
  content = new Konva.Layer();
  controls = new Konva.Layer();
  transformer = new Konva.Transformer({
    flipEnabled: false,
    anchorSize: 14,
    anchorCornerRadius: 3,
    borderStroke: '#2dd4bf',
    anchorStroke: '#2dd4bf',
    boundBoxFunc: (oldBox, box) => {
      if (box.width < 10 || box.height < 10) return oldBox;
      if (
        crop &&
        (box.x < 0 ||
          box.y < 0 ||
          box.x + box.width > stage.width() ||
          box.y + box.height > stage.height())
      )
        return oldBox;
      return box;
    },
  });
  controls.add(transformer);
  stage.add(content, controls);
  stage.on('mousedown touchstart', start);
  stage.on('mousemove touchmove', move);
  stage.on('mouseup touchend', finish);
  observer = new ResizeObserver(resize);
  observer.observe(host.value);
  load();
});
watch(() => props.file, load);
watch(() => props.tool, setMode);
watch(
  () => props.disabled,
  disabled => {
    if (stage) stage.listening(!disabled);
  }
);
onBeforeUnmount(() => {
  version += 1;
  observer?.disconnect();
  stage?.destroy();
  bitmap?.close();
});
function stopInteraction() {
  const previous = working;
  working = true;
  line?.destroy();
  line = null;
  transformer?.stopTransform();
  content?.getChildren().forEach(node => node.stopDrag());
  crop?.stopDrag();
  working = previous;
}
defineExpose({
  rotate,
  addText,
  updateText,
  removeText,
  applyCrop,
  stopInteraction,
});
</script>

<template>
  <div
    ref="host"
    class="w-full h-full min-h-0 flex items-center justify-center touch-none overflow-hidden"
  />
</template>

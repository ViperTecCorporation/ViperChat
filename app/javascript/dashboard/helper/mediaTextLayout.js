// Let Konva measure the glyphs instead of reserving an arbitrary text column.
// Keep the transform intact when editing a rotated/resized object.
export function fitMediaText(node, maxWidth) {
  node.setAttrs({ width: 'auto', height: 'auto' });
  const displayedWidth = node.width() * Math.abs(node.scaleX());
  if (displayedWidth > maxWidth) {
    node.fontSize(node.fontSize() * (maxWidth / displayedWidth));
  }
}

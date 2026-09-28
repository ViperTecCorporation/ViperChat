export function zoomPreview(view, targetZoom, anchor, center) {
  const zoom = Math.max(1, Math.min(4, targetZoom));
  if (zoom === 1) return { zoom, x: 0, y: 0 };
  const factor = zoom / view.zoom;
  return {
    zoom,
    x: anchor.x - center.x - (anchor.x - center.x - view.x) * factor,
    y: anchor.y - center.y - (anchor.y - center.y - view.y) * factor,
  };
}

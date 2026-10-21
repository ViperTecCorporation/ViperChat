import { onUnmounted, ref, watch } from 'vue';
import { useEventListener, useResizeObserver } from '@vueuse/core';

// Layout stays in Tailwind. Web Animations applies only runtime drag coordinates
// and visual-viewport bounds, which cannot be represented by static utilities.
export function useFloatingWebphone(panel, enabled = ref(true)) {
  let position = null;
  let translation = { x: 0, y: 0 };
  let animation;
  let drag;

  function place(next = position) {
    const element = panel.value;
    if (!element || !enabled.value) return;
    const viewport = window.visualViewport;
    const left = (viewport?.offsetLeft || 0) + 16;
    const top = (viewport?.offsetTop || 0) + 16;
    const width = viewport?.width || window.innerWidth;
    const height = viewport?.height || window.innerHeight;
    const bounds = {
      maxWidth: `${Math.max(0, Math.min(384, width - 32))}px`,
      maxHeight: `${Math.max(0, height - 32)}px`,
    };
    const transform = `translate(${translation.x}px, ${translation.y}px)`;
    animation?.cancel();
    animation = element.animate([{ ...bounds, transform }], {
      duration: 0,
      fill: 'forwards',
    });
    const rect = element.getBoundingClientRect();
    const base = {
      left: rect.left - translation.x,
      top: rect.top - translation.y,
    };
    position = {
      left: Math.max(
        left,
        Math.min(next?.left ?? rect.left, left + width - 32 - rect.width)
      ),
      top: Math.max(
        top,
        Math.min(next?.top ?? rect.top, top + height - 32 - rect.height)
      ),
    };
    translation = { x: position.left - base.left, y: position.top - base.top };
    animation.effect.setKeyframes([
      {
        ...bounds,
        transform: `translate(${translation.x}px, ${translation.y}px)`,
      },
    ]);
  }

  function startDrag(event) {
    if (!enabled.value || event.button !== 0 || !event.isPrimary) return;
    place();
    drag = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      position: { ...position },
    };
    event.currentTarget.setPointerCapture(event.pointerId);
    event.preventDefault();
  }

  function moveDrag(event) {
    if (!enabled.value || !drag || event.pointerId !== drag.id) return;
    place({
      left: drag.position.left + event.clientX - drag.x,
      top: drag.position.top + event.clientY - drag.y,
    });
  }

  function stopDrag() {
    drag = null;
  }

  function moveByKeyboard(event) {
    const directions = {
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
      ArrowUp: [0, -1],
      ArrowDown: [0, 1],
    };
    if (!enabled.value || !directions[event.key]) return;
    event.preventDefault();
    place();
    const step = event.shiftKey ? 40 : 10;
    const [x, y] = directions[event.key];
    place({ left: position.left + x * step, top: position.top + y * step });
  }

  watch(
    [panel, enabled],
    () => {
      animation?.cancel();
      animation = null;
      translation = { x: 0, y: 0 };
      drag = null;
      place();
    },
    { flush: 'post' }
  );
  useResizeObserver(panel, () => place());
  useEventListener(window, 'resize', () => place());
  useEventListener(window.visualViewport, ['resize', 'scroll'], () => place());
  onUnmounted(() => animation?.cancel());

  return { startDrag, moveDrag, stopDrag, moveByKeyboard };
}

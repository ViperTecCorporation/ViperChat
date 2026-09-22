import { ref, computed } from 'vue';
import {
  debounce,
  calculateCenterOffset,
  applyRotationTransform,
  normalizeToPercentage,
} from '@chatwoot/utils';

// Composable for images in gallery view
export const useImageZoom = imageRef => {
  const MAX_ZOOM_LEVEL = 3;
  const MIN_ZOOM_LEVEL = 1;
  const ZOOM_INCREMENT = 0.2;
  const MOUSE_MOVE_DEBOUNCE_MS = 100;
  const MOUSE_LEAVE_DEBOUNCE_MS = 110;
  const DEFAULT_IMG_TRANSFORM_ORIGIN = 'center center';

  const zoomScale = ref(1);
  const imgTransformOriginPoint = ref(DEFAULT_IMG_TRANSFORM_ORIGIN);
  const activeImageRotation = ref(0);
  const pan = ref({ x: 0, y: 0 });
  const isTouching = ref(false);
  let gesture = null;

  const imageWrapperStyle = computed(() => ({
    transform: `rotate(${activeImageRotation.value}deg)`,
  }));

  const imageStyle = computed(() => ({
    transform: `translate(${pan.value.x}px, ${pan.value.y}px) scale(${zoomScale.value})`,
    cursor: zoomScale.value < MAX_ZOOM_LEVEL ? 'zoom-in' : 'zoom-out',
    transformOrigin: `${imgTransformOriginPoint.value}`,
  }));

  // Resets the transform origin to center
  const resetTransformOrigin = () => {
    if (imageRef.value) {
      imgTransformOriginPoint.value = DEFAULT_IMG_TRANSFORM_ORIGIN;
    }
  };

  // Rotates the current image
  const onRotate = type => {
    if (!imageRef.value) return;
    resetTransformOrigin();

    const rotation = type === 'clockwise' ? 90 : -90;

    // ensure that the value of the rotation is within the range of -360 to 360 degrees
    activeImageRotation.value = (activeImageRotation.value + rotation) % 360;

    // Reset zoom when rotating
    zoomScale.value = 1;
    pan.value = { x: 0, y: 0 };
    gesture = null;
    resetTransformOrigin();
  };

  /**
   * Calculates the appropriate transform origin point based on mouse position and image rotation
   * Used to create a natural zoom behavior where the image zooms toward/from the cursor position
   *
   * @param {number} x - The client X coordinate of the mouse pointer
   * @param {number} y - The client Y coordinate of the mouse pointer
   * @returns {{x: number, y: number}} Object containing the transform origin coordinates as percentages
   */
  const getZoomOrigin = (x, y) => {
    // Default to center
    if (!imageRef.value) return { x: 50, y: 50 };

    const rect = imageRef.value.getBoundingClientRect();

    // Step 1: Calculate offset from center
    const { relativeX, relativeY } = calculateCenterOffset(x, y, rect);

    // Step 2: Apply rotation transformation
    const { rotatedX, rotatedY } = applyRotationTransform(
      relativeX,
      relativeY,
      activeImageRotation.value
    );

    // Step 3: Convert to percentage coordinates
    return normalizeToPercentage(rotatedX, rotatedY, rect.width, rect.height);
  };

  // Handles zooming the image
  const onZoom = (scale, x, y) => {
    if (!imageRef.value) return;

    // Calculate new scale within bounds
    const newScale = Math.max(
      MIN_ZOOM_LEVEL,
      Math.min(MAX_ZOOM_LEVEL, zoomScale.value + scale)
    );

    // Skip if no change
    if (newScale === zoomScale.value) return;

    // Update transform origin based on mouse position and zoom scale is minimum
    if (x != null && y != null && zoomScale.value === MIN_ZOOM_LEVEL) {
      const { x: originX, y: originY } = getZoomOrigin(x, y);
      imgTransformOriginPoint.value = `${originX}% ${originY}%`;
    }

    // Apply the new scale
    zoomScale.value = newScale;
    if (newScale === MIN_ZOOM_LEVEL) pan.value = { x: 0, y: 0 };
  };

  // Handles double-click zoom toggling
  const onDoubleClickZoomImage = e => {
    if (!imageRef.value) return;
    e.preventDefault();

    // Toggle between max zoom and min zoom
    const newScale =
      zoomScale.value >= MAX_ZOOM_LEVEL ? MIN_ZOOM_LEVEL : MAX_ZOOM_LEVEL;

    // Update transform origin based on mouse position
    const { x: originX, y: originY } = getZoomOrigin(e.clientX, e.clientY);
    imgTransformOriginPoint.value = `${originX}% ${originY}%`;

    // Apply the new scale
    zoomScale.value = newScale;
    pan.value = { x: 0, y: 0 };
  };

  // Handles mouse wheel zooming for images
  const onWheelImageZoom = e => {
    if (!imageRef.value) return;
    e.preventDefault();

    const scale = e.deltaY > 0 ? -ZOOM_INCREMENT : ZOOM_INCREMENT;
    onZoom(scale, e.clientX, e.clientY);
  };

  /**
   * Sets transform origin to mouse position during hover.
   * Enables precise scroll/double-click zoom targeting by updating the
   * transform origin to cursor position. Only active at minimum zoom level.
   * Debounced (100ms) to improve performance during rapid mouse movement.
   */
  const onMouseMove = debounce(
    e => {
      if (!imageRef.value) return;
      if (zoomScale.value !== MIN_ZOOM_LEVEL) return;

      const { x: originX, y: originY } = getZoomOrigin(e.clientX, e.clientY);
      imgTransformOriginPoint.value = `${originX}% ${originY}%`;
    },
    MOUSE_MOVE_DEBOUNCE_MS,
    false
  );

  /**
   * Resets transform origin to center when mouse leaves image.
   * Ensures button-based zooming works predictably after hover ends.
   * Uses slightly longer debounce (110ms) to avoid conflicts with onMouseMove.
   */
  const onMouseLeave = debounce(
    () => {
      if (!imageRef.value) return;
      if (zoomScale.value !== MIN_ZOOM_LEVEL) return;
      imgTransformOriginPoint.value = DEFAULT_IMG_TRANSFORM_ORIGIN;
    },
    MOUSE_LEAVE_DEBOUNCE_MS,
    false
  );

  const onTouchStart = event => {
    const [first, second] = event.touches;
    isTouching.value = Boolean(first);
    if (!first) {
      gesture = null;
      return;
    }
    if (zoomScale.value === MIN_ZOOM_LEVEL) resetTransformOrigin();
    gesture = {
      x: first.clientX,
      y: first.clientY,
      distance: second
        ? Math.hypot(
            second.clientX - first.clientX,
            second.clientY - first.clientY
          )
        : 0,
      scale: zoomScale.value,
      pan: { ...pan.value },
    };
  };

  const onTouchMove = event => {
    if (!gesture || !imageRef.value) return;
    const [first, second] = event.touches;
    if (!first) return;
    if (second && gesture.distance) {
      const distance = Math.hypot(
        second.clientX - first.clientX,
        second.clientY - first.clientY
      );
      onZoom((gesture.scale * distance) / gesture.distance - zoomScale.value);
    } else if (!second && zoomScale.value > MIN_ZOOM_LEVEL) {
      const angle = (activeImageRotation.value * Math.PI) / 180;
      const dx = first.clientX - gesture.x;
      const dy = first.clientY - gesture.y;
      const maxX = (imageRef.value.clientWidth * (zoomScale.value - 1)) / 2;
      const maxY = (imageRef.value.clientHeight * (zoomScale.value - 1)) / 2;
      pan.value = {
        x: Math.max(
          -maxX,
          Math.min(
            maxX,
            gesture.pan.x + dx * Math.cos(angle) + dy * Math.sin(angle)
          )
        ),
        y: Math.max(
          -maxY,
          Math.min(
            maxY,
            gesture.pan.y - dx * Math.sin(angle) + dy * Math.cos(angle)
          )
        ),
      };
    }
  };

  const onTouchCancel = () => {
    gesture = null;
    isTouching.value = false;
  };

  const resetZoomAndRotation = () => {
    activeImageRotation.value = 0;
    zoomScale.value = 1;
    pan.value = { x: 0, y: 0 };
    onTouchCancel();
    resetTransformOrigin();
  };

  return {
    zoomScale,
    isTouching,
    onTouchStart,
    onTouchMove,
    onTouchCancel,
    imgTransformOriginPoint,
    activeImageRotation,
    imageWrapperStyle,
    imageStyle,
    getZoomOrigin,
    resetTransformOrigin,
    onRotate,
    onZoom,
    onDoubleClickZoomImage,
    onWheelImageZoom,
    onMouseMove,
    onMouseLeave,
    resetZoomAndRotation,
  };
};

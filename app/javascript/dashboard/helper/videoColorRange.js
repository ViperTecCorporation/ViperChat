import { VideoSample } from 'mediabunny';

// Canvas readback is sRGB. Convert its transfer curve before BT.709 YCbCr.
const srgbTo709 = Float64Array.from({ length: 256 }, (_, value) => {
  const srgb = value / 255;
  const linear =
    srgb <= 0.04045 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
  return 255 * (linear < 0.018 ? 4.5 * linear : 1.099 * linear ** 0.45 - 0.099);
});

// Convert pixels, not just the color tag: limited-range BT.709 8-bit I420.
export function rgbaToLimitedI420(rgba, width, height) {
  const size = width * height;
  const output = new Uint8Array(size * 1.5);
  const clamp = (value, min, max) =>
    Math.min(max, Math.max(min, Math.round(value)));
  for (let y = 0; y < height; y += 2) {
    for (let x = 0; x < width; x += 2) {
      let cb = 0;
      let cr = 0;
      for (let dy = 0; dy < 2; dy += 1) {
        for (let dx = 0; dx < 2; dx += 1) {
          const pixel = (y + dy) * width + x + dx;
          const r = srgbTo709[rgba[pixel * 4]];
          const g = srgbTo709[rgba[pixel * 4 + 1]];
          const b = srgbTo709[rgba[pixel * 4 + 2]];
          const luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          output[pixel] = clamp(16 + (219 * luma) / 255, 16, 235);
          cb += (b - luma) / 1.8556;
          cr += (r - luma) / 1.5748;
        }
      }
      const chroma = (y / 2) * (width / 2) + x / 2;
      output[size + chroma] = clamp(128 + (224 * cb) / (255 * 4), 16, 240);
      output[size + size / 4 + chroma] = clamp(
        128 + (224 * cr) / (255 * 4),
        16,
        240
      );
    }
  }
  return output;
}

export function limitedRangeProcessor(width, height) {
  const canvas = new OffscreenCanvas(width, height);
  const context = canvas.getContext('2d', { willReadFrequently: true });
  return sample => {
    const frame = sample.toVideoFrame();
    try {
      context.drawImage(frame, 0, 0, width, height);
      const rgba = context.getImageData(0, 0, width, height).data;
      return new VideoSample(rgbaToLimitedI420(rgba, width, height), {
        format: 'I420',
        codedWidth: width,
        codedHeight: height,
        timestamp: sample.timestamp,
        duration: sample.duration,
        colorSpace: {
          primaries: 'bt709',
          transfer: 'bt709',
          matrix: 'bt709',
          fullRange: false,
        },
      });
    } finally {
      frame.close();
    }
  };
}

// Inspect all timestamps: a VFR stream can average 30 while containing 60 FPS.
// Unlike ffprobe's r_frame_rate this is a timestamp-derived estimate, not a
// claim of bit-for-bit equivalence to ffprobe's codec/container heuristics.
export async function inspectVideoFrameRate(track, packetStats) {
  const metrics = await track.computeFrameRateMetrics({
    targetPacketCount: Infinity,
  });
  const rates = [
    packetStats.averagePacketRate,
    metrics.bestGuessFrameRate,
    metrics.maxFrameRate,
  ];
  if (rates.some(rate => !Number.isFinite(rate) || rate <= 0))
    throw new Error('INVALID_VIDEO');
  const maximum = Math.max(...rates);
  // MP4 timestamp quantization (microseconds) can make CFR 30 read 30.0003.
  // Snap only sub-millisecond quantization noise, never 30.01/59.94/60 FPS.
  return maximum > 30 && maximum < 30.001 ? 30 : maximum;
}

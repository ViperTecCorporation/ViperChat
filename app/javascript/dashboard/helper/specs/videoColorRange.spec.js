import { rgbaToLimitedI420 } from '../videoColorRange';

describe('pixel conversion to limited BT.709 I420', () => {
  it.each([
    [
      [0, 0, 0, 255],
      [16, 16, 16, 16, 128, 128],
    ],
    [
      [255, 255, 255, 255],
      [235, 235, 235, 235, 128, 128],
    ],
    [
      [255, 0, 0, 255],
      [63, 63, 63, 63, 102, 240],
    ],
    [
      [0, 0, 255, 255],
      [32, 32, 32, 32, 240, 118],
    ],
  ])(
    'converts %s pixels rather than changing a metadata tag',
    (pixel, expected) => {
      expect(
        Array.from(
          rgbaToLimitedI420(
            new Uint8Array([...pixel, ...pixel, ...pixel, ...pixel]),
            2,
            2
          )
        )
      ).toEqual(expected);
    }
  );
  it('averages chroma over a 2x2 block and retains per-pixel luma', () => {
    const rgba = new Uint8Array([
      0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255,
    ]);
    expect(Array.from(rgbaToLimitedI420(rgba, 2, 2))).toEqual([
      16, 235, 16, 235, 128, 128,
    ]);
  });
});

import { zoomPreview } from '../mediaPreviewZoom';
describe('preview camera (never image edits)', () => {
  it('zooms around the center without translating', () => {
    expect(
      zoomPreview(
        { zoom: 1, x: 0, y: 0 },
        2,
        { x: 100, y: 100 },
        { x: 100, y: 100 }
      )
    ).toEqual({ zoom: 2, x: 0, y: 0 });
  });
  it('keeps the touched image point anchored', () => {
    expect(
      zoomPreview(
        { zoom: 1, x: 0, y: 0 },
        2,
        { x: 150, y: 125 },
        { x: 100, y: 100 }
      )
    ).toEqual({ zoom: 2, x: -50, y: -25 });
  });
  it('resets pan at fit and limits magnification', () => {
    expect(
      zoomPreview(
        { zoom: 2, x: -50, y: 20 },
        0.5,
        { x: 0, y: 0 },
        { x: 100, y: 100 }
      )
    ).toEqual({ zoom: 1, x: 0, y: 0 });
    expect(
      zoomPreview(
        { zoom: 1, x: 0, y: 0 },
        10,
        { x: 100, y: 100 },
        { x: 100, y: 100 }
      ).zoom
    ).toBe(4);
  });
});

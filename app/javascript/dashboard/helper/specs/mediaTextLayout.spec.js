import { fitMediaText } from '../mediaTextLayout';

describe('content-sized media text selection', () => {
  it.each([
    ['emoji', 28],
    ['short text', 140],
  ])('uses measured bounds for %s without changing its size', (_, width) => {
    const node = {
      setAttrs: vi.fn(),
      width: () => width,
      scaleX: () => 1,
      fontSize: vi.fn(() => 28),
    };
    fitMediaText(node, 500);
    expect(node.setAttrs).toHaveBeenCalledWith({
      width: 'auto',
      height: 'auto',
    });
    expect(node.fontSize).not.toHaveBeenCalled();
  });
  it('fits long resized text while preserving its transform', () => {
    const node = {
      setAttrs: vi.fn(),
      width: () => 400,
      scaleX: () => 2,
      fontSize: vi.fn(() => 40),
    };
    fitMediaText(node, 600);
    expect(node.fontSize).toHaveBeenLastCalledWith(30);
    expect(node.setAttrs).toHaveBeenCalledTimes(1);
  });
});

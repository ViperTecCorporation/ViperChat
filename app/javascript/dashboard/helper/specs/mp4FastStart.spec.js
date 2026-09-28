import { Blob } from 'node:buffer';
import { hasMp4FastStart } from '../mp4FastStart';

const atom = type =>
  new Uint8Array([0, 0, 0, 8, ...Array.from(type, c => c.charCodeAt(0))]);
describe('MP4 fast start inspection', () => {
  it('accepts moov before media data', async () => {
    expect(
      await hasMp4FastStart(
        new Blob([atom('ftyp'), atom('moov'), atom('mdat')])
      )
    ).toBe(true);
  });
  it('rejects moov at the end so the worker prepares a fast-start output', async () => {
    expect(
      await hasMp4FastStart(
        new Blob([atom('ftyp'), atom('mdat'), atom('moov')])
      )
    ).toBe(false);
  });
  it('rejects truncated and invalid atom headers', async () => {
    expect(await hasMp4FastStart(new Blob(['bad']))).toBe(false);
    expect(
      await hasMp4FastStart(
        new Blob([new Uint8Array([0, 0, 0, 2, 109, 111, 111, 118])])
      )
    ).toBe(false);
  });
});

/* eslint-disable no-await-in-loop -- Atom offsets depend on the previous header. */
// Read only atom headers, never load an entire large video to inspect its layout.
export async function hasMp4FastStart(file) {
  let offset = 0;
  while (offset + 8 <= file.size) {
    // eslint-disable-next-line no-await-in-loop
    const header = new DataView(
      await file.slice(offset, offset + 16).arrayBuffer()
    );
    let size = header.getUint32(0);
    const type = String.fromCharCode(...new Uint8Array(header.buffer, 4, 4));
    if (size === 1) {
      if (header.byteLength < 16) return false;
      size = Number(header.getBigUint64(8));
    } else if (size === 0) size = file.size - offset;
    if (!Number.isSafeInteger(size) || size < 8 || offset + size > file.size)
      return false;
    if (type === 'moov') return true;
    if (type === 'mdat') return false;
    offset += size;
  }
  return false;
}

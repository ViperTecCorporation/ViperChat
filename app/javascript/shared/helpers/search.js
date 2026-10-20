import { picoSearch as fuzzySearch } from '@scmmishra/pico-search';

// Compare a folded copy; keep original names, IDs and selected objects intact.
export const normalizeForSearch = value =>
  String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();

export const includesNormalized = (value, query) =>
  normalizeForSearch(value).includes(normalizeForSearch(query));

export const picoSearch = (items, query, keys, options) => {
  if (!query || typeof query !== 'string') return items;
  const originals = new Map();
  const searchable = items.map(item => {
    const copy = { ...item };
    keys.forEach(key => {
      const name = typeof key === 'string' ? key : key.name;
      if (typeof item[name] === 'string') {
        // Pico handles case itself and uses capitals to score word boundaries.
        copy[name] = item[name]
          .normalize('NFD')
          .replace(/[\u0300-\u036f]/g, '');
      }
    });
    originals.set(copy, item);
    return copy;
  });
  return fuzzySearch(searchable, normalizeForSearch(query), keys, options).map(
    item => originals.get(item)
  );
};

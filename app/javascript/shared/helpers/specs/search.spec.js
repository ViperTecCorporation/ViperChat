import { includesNormalized, normalizeForSearch, picoSearch } from '../search';

describe('accent-insensitive search', () => {
  it.each([
    ['João', 'joao'],
    ['JOAO', 'João'],
    ['Cláudia', 'claudia'],
    ['Manutenção', 'manutencao'],
    ['Vôlei', 'volei'],
    ['Ca\u0302meras', 'CÂMERAS'],
    ['São Paulo', 'sao paulo'],
    ['Órçãõ_100%', 'orcao_100%'],
    ['العربية', 'العربية'],
  ])('finds %s using %s', (value, query) => {
    expect(includesNormalized(value, query)).toBe(true);
  });

  it('handles empty labels and keeps punctuation literal', () => {
    expect(normalizeForSearch(null)).toBe('');
    expect(includesNormalized(undefined, 'joao')).toBe(false);
    expect(includesNormalized('100 pessoas', '100%')).toBe(false);
    expect(normalizeForSearch('+5566996269251')).toBe('+5566996269251');
    expect(normalizeForSearch('BR.2339818310092335')).toBe(
      'br.2339818310092335'
    );
  });

  it('searches multiple fields and returns the original objects without mutation', () => {
    const item = Object.freeze({
      id: 1,
      name: 'João',
      description: 'Manutenção',
    });
    const items = Object.freeze([
      item,
      Object.freeze({ id: 2, name: 'Maria' }),
    ]);
    const result = picoSearch(items, 'joao manutencao', [
      'name',
      'description',
    ]);
    expect(result).toEqual([item]);
    expect(result[0]).toBe(item);
    expect(item.name).toBe('João');
  });

  it('keeps weighted keys, options, selection identity and empty queries working', () => {
    const items = [{ name: 'José' }, { name: 'Outro' }];
    expect(
      picoSearch(items, 'jose', [{ name: 'name', weight: 2 }], {
        threshold: 0.8,
      })
    ).toEqual([items[0]]);
    expect(picoSearch(items, '', ['name'])).toBe(items);
  });
});

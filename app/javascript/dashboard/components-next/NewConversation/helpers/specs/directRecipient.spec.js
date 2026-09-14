import { normalizeDirectRecipient } from '../directRecipient';

describe('normalizeDirectRecipient', () => {
  it.each([
    '(66) 99622-2472',
    '66996222472',
    '5566996222472',
    '+55 66 99622-2472',
  ])('normalizes %s without duplicating country code', input => {
    expect(normalizeDirectRecipient(input)).toEqual({
      phone_number: '+5566996222472',
    });
  });
  it('preserves international numbers', () => {
    expect(normalizeDirectRecipient('+1 415 555 2671')).toEqual({
      phone_number: '+14155552671',
    });
  });
  it('requires area code and explicit selection for numeric LIDs', () => {
    expect(normalizeDirectRecipient('996222472')).toBeNull();
    expect(normalizeDirectRecipient('212721190613051')).toBeNull();
    expect(normalizeDirectRecipient('212721190613051', 'bsuid')).toEqual({
      bsuid: '212721190613051',
    });
  });
  it.each(['212721190613051@lid', 'BR.4462342527311286'])(
    'preserves explicit identifier %s',
    value => {
      expect(normalizeDirectRecipient(value)).toEqual({ bsuid: value });
    }
  );
});

import { DuplicateContactException } from '../CustomErrors';

describe('DuplicateContactException', () => {
  it('returns correct exception', () => {
    const exception = new DuplicateContactException({
      attributes: ['email'],
    });
    expect(exception.message).toEqual('DUPLICATE_CONTACT');
    expect(exception.data).toEqual({
      attributes: ['email'],
    });
    expect(exception.contactErrorAttributes).toEqual(['email']);
  });

  it.each([
    [['phone_number'], ['phone_number']],
    ['email', ['email']],
    [{ phone_number: ['has already been taken'] }, ['phone_number']],
    [null, []],
  ])('normalizes duplicate attributes from %p', (data, expected) => {
    const exception = new DuplicateContactException(data);

    expect(exception.contactErrorAttributes).toEqual(expected);
  });
});

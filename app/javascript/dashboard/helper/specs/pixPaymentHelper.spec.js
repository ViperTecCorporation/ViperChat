import {
  hasPixPaymentConfiguration,
  pixPaymentDisplayType,
} from '../pixPaymentHelper';

describe('pixPaymentHelper', () => {
  it.each(['EMAIL', 'CNPJ', 'PHONE'])(
    'accepts a configured %s PIX key',
    pixKeyType => {
      expect(
        hasPixPaymentConfiguration({
          pix_key: 'configured-key',
          pix_key_type: pixKeyType,
        })
      ).toBe(true);
    }
  );

  it('rejects incomplete and unsupported configurations', () => {
    expect(
      hasPixPaymentConfiguration({ pix_key: '', pix_key_type: 'EMAIL' })
    ).toBe(false);
    expect(
      hasPixPaymentConfiguration({
        pix_key: 'configured-key',
        pix_key_type: 'CPF',
      })
    ).toBe(false);
  });

  it.each([
    ['EMAIL', 'Email'],
    ['CNPJ', 'Cnpj'],
    ['PHONE', 'Phone'],
  ])('formats %s for the synthetic message bubble', (keyType, displayType) => {
    expect(pixPaymentDisplayType(keyType)).toBe(displayType);
  });
});

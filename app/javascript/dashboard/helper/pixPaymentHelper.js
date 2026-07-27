export const PIX_KEY_TYPES = ['EMAIL', 'CNPJ', 'PHONE'];

export const hasPixPaymentConfiguration = providerConfig => {
  const config = providerConfig || {};
  return (
    Boolean(config.pix_key?.trim()) &&
    PIX_KEY_TYPES.includes(config.pix_key_type)
  );
};

export const pixPaymentDisplayType = keyType => {
  const normalizedType = keyType || '';
  return `${normalizedType.charAt(0)}${normalizedType.slice(1).toLowerCase()}`;
};

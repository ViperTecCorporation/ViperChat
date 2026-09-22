import { isValidPhoneNumber } from 'libphonenumber-js';

export const normalizeDirectRecipient = (input, mode = 'phone') => {
  const raw = input.trim().replace(/^@/, '');
  if (mode === 'bsuid' || /@lid$|^[A-Z]{2}\./.test(raw)) {
    return /^(?:[A-Z]{2}\.)?\d{5,}(?:@lid)?$/.test(raw) ? { bsuid: raw } : null;
  }
  if (!/^\+?[\d\s().-]+$/.test(raw)) return null;
  let digits = raw.replace(/\D/g, '');
  if (!raw.startsWith('+') && [10, 11].includes(digits.length)) {
    digits = `55${digits}`;
  } else if (!raw.startsWith('+') && !/^55\d{10,11}$/.test(digits)) {
    return null;
  }
  const phone = `+${digits}`;
  return isValidPhoneNumber(phone) ? { phone_number: phone } : null;
};

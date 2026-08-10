import { resolveNativeAccountId } from './nativeEnvironmentService';

describe('resolveNativeAccountId', () => {
  it('prefers the active account from the authenticated user', () => {
    expect(
      resolveNativeAccountId({ account_id: 9, accounts: [{ id: 3 }] })
    ).toBe(9);
  });

  it('falls back to the first available account', () => {
    expect(resolveNativeAccountId({ accounts: [{ id: 3 }] })).toBe(3);
  });

  it('returns null when the session has no valid account', () => {
    expect(resolveNativeAccountId({ accounts: [] })).toBeNull();
  });
});

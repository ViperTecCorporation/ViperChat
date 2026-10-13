import { resolveNativeAccountId } from './nativeEnvironmentService';

describe('resolveNativeAccountId', () => {
  it('keeps the explicitly selected account instead of restoring the previous one', () => {
    expect(
      resolveNativeAccountId(
        { account_id: 1, accounts: [{ id: 1 }, { id: 20 }] },
        '#/app/accounts/20/dashboard'
      )
    ).toBe(20);
  });

  it('does not select a route account outside the authenticated memberships', () => {
    expect(
      resolveNativeAccountId(
        { account_id: 1, accounts: [{ id: 1 }] },
        '#/app/accounts/20/dashboard'
      )
    ).toBe(1);
  });
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

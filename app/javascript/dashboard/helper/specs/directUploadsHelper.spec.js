import {
  getDirectUploadUrl,
  setDirectUploadAuthHeaders,
} from '../directUploadsHelper';
import Auth from 'dashboard/api/auth';

vi.mock('dashboard/api/auth', () => ({
  default: { getAuthData: vi.fn() },
}));

describe('setDirectUploadAuthHeaders', () => {
  const buildXhr = () => ({ setRequestHeader: vi.fn() });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('sets the five session auth headers from the auth cookie', () => {
    Auth.getAuthData.mockReturnValue({
      'access-token': 'token-123',
      'token-type': 'Bearer',
      client: 'client-123',
      expiry: '9999',
      uid: 'agent@example.com',
    });
    const xhr = buildXhr();

    setDirectUploadAuthHeaders(xhr);

    expect(xhr.setRequestHeader).toHaveBeenCalledTimes(5);
    expect(xhr.setRequestHeader).toHaveBeenCalledWith(
      'access-token',
      'token-123'
    );
    expect(xhr.setRequestHeader).toHaveBeenCalledWith('token-type', 'Bearer');
    expect(xhr.setRequestHeader).toHaveBeenCalledWith('client', 'client-123');
    expect(xhr.setRequestHeader).toHaveBeenCalledWith('expiry', '9999');
    expect(xhr.setRequestHeader).toHaveBeenCalledWith(
      'uid',
      'agent@example.com'
    );
  });

  it('does not set any header when there is no auth data', () => {
    Auth.getAuthData.mockReturnValue(false);
    const xhr = buildXhr();

    setDirectUploadAuthHeaders(xhr);

    expect(xhr.setRequestHeader).not.toHaveBeenCalled();
  });

  it('does not set any header when the access token is missing', () => {
    Auth.getAuthData.mockReturnValue({
      client: 'client-123',
      uid: 'agent@example.com',
    });
    const xhr = buildXhr();

    setDirectUploadAuthHeaders(xhr);

    expect(xhr.setRequestHeader).not.toHaveBeenCalled();
  });
});

describe('getDirectUploadUrl', () => {
  it('uses the remote installation origin in the native app', () => {
    window.chatwootConfig = { apiHost: 'https://chat.example.com' };

    expect(getDirectUploadUrl('/rails/active_storage/direct_uploads')).toBe(
      'https://chat.example.com/rails/active_storage/direct_uploads'
    );
  });
});

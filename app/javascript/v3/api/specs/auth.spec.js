import { setNewPassword, verifyPasswordToken } from '../auth';
import wootAPI from '../apiClient';
import { setAuthCredentials } from 'dashboard/store/utils/api';

vi.mock('../apiClient', () => ({
  default: { post: vi.fn(), put: vi.fn() },
}));

vi.mock('dashboard/store/utils/api', () => ({
  setAuthCredentials: vi.fn(),
  throwErrorMessage: vi.fn(error => {
    throw error;
  }),
  clearLocalStorageOnLogout: vi.fn(),
  parseAPIErrorResponse: vi.fn(),
}));

const credentials = {
  resetPasswordToken: 'token',
  password: 'Password1!',
  confirmPassword: 'Password1!',
};

describe('#setNewPassword', () => {
  beforeEach(() => vi.clearAllMocks());

  it('stores the session when the reset signs the user in', async () => {
    const response = { data: { data: { id: 1 } } };
    wootAPI.put.mockResolvedValue(response);

    expect(await setNewPassword(credentials)).toEqual({});
    expect(setAuthCredentials).toHaveBeenCalledWith(response);
  });

  it('returns the sign in redirect when two-factor authentication is required', async () => {
    wootAPI.put.mockResolvedValue({ data: { redirect_url: '/app/login' } });

    expect(await setNewPassword(credentials)).toEqual({
      redirectUrl: '/app/login',
    });
    expect(setAuthCredentials).not.toHaveBeenCalled();
  });
});

describe('#verifyPasswordToken', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns the sign in redirect when two-factor authentication is required', async () => {
    wootAPI.post.mockResolvedValue({ data: { redirect_url: '/app/login' } });

    expect(await verifyPasswordToken({ confirmationToken: 'token' })).toEqual({
      redirectUrl: '/app/login',
    });
    expect(setAuthCredentials).not.toHaveBeenCalled();
  });
});

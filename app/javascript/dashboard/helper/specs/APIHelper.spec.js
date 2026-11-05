import createAxios, { resetSessionCheck } from '../APIHelper';
import Auth from '../../api/auth';
import { clearCookiesOnLogout } from '../../store/utils/api';

vi.mock('../../api/auth', () => ({
  default: {
    hasAuthCookie: () => false,
    validityCheck: vi.fn(),
  },
}));
vi.mock('../../store/utils/api', () => ({ clearCookiesOnLogout: vi.fn() }));

describe('APIHelper', () => {
  let onError;

  const unauthorized = url => ({ response: { status: 401 }, config: { url } });
  const respond = async error => {
    await onError(error).catch(() => {});
    await new Promise(resolve => {
      setTimeout(resolve);
    });
  };

  beforeEach(() => {
    vi.clearAllMocks();
    resetSessionCheck();
    createAxios({
      create: () => ({
        defaults: { headers: { common: {} } },
        interceptors: {
          response: {
            use: (_, handler) => {
              onError = handler;
            },
          },
        },
      }),
    });
  });

  it('sends the tab to the login when its session ended', async () => {
    Auth.validityCheck.mockRejectedValue(unauthorized('/auth/validate_token'));

    await respond(unauthorized('/api/v1/accounts/1/inboxes'));

    expect(clearCookiesOnLogout).toHaveBeenCalledWith({
      redirectTo: '/app/login?error=session-ended',
    });
  });

  it('keeps the session when the 401 is a permission refusal', async () => {
    Auth.validityCheck.mockResolvedValue({});

    await respond(unauthorized('/api/v2/accounts/1/reports'));

    expect(clearCookiesOnLogout).not.toHaveBeenCalled();
  });

  it('checks the session once for many failed requests', async () => {
    Auth.validityCheck.mockResolvedValue({});

    await Promise.all([
      respond(unauthorized('/api/v1/accounts/1/inboxes')),
      respond(unauthorized('/api/v1/accounts/1/cache_keys')),
    ]);
    await respond(unauthorized('/api/v1/accounts/1/labels'));

    expect(Auth.validityCheck).toHaveBeenCalledTimes(1);
  });

  it('leaves failed sign-in and token checks alone', async () => {
    await respond(unauthorized('/auth/sign_in'));

    expect(Auth.validityCheck).not.toHaveBeenCalled();
  });

  it('ignores other errors', async () => {
    await respond({ response: { status: 500 }, config: { url: '/api/v1/x' } });

    expect(Auth.validityCheck).not.toHaveBeenCalled();
  });
});

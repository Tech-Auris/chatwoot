import { effectScope } from 'vue';
import { useSessionTimeout, IDLE_TIMEOUT_MS } from '../useSessionTimeout';
import Auth from 'dashboard/api/auth';
import { clearCookiesOnLogout } from 'dashboard/store/utils/api';

vi.mock('dashboard/api/auth', () => ({
  default: {
    hasAuthCookie: vi.fn(),
    getAuthData: vi.fn(),
    logout: vi.fn(),
  },
}));
vi.mock('dashboard/store/utils/api', () => ({
  clearCookiesOnLogout: vi.fn(),
  deleteIndexedDBOnLogout: vi.fn(),
  markUserActivity: () =>
    window.localStorage.setItem('lastUserActivityAt', Date.now().toString()),
}));

const HOUR = 60 * 60 * 1000;
const SESSION_ENDED_URL = '/app/login?error=session-ended';

describe('useSessionTimeout', () => {
  let scope;

  const start = () => {
    scope = effectScope();
    scope.run(() => useSessionTimeout());
  };
  const expiresIn = ms => {
    Auth.getAuthData.mockReturnValue({
      expiry: String(Math.floor((Date.now() + ms) / 1000)),
    });
  };

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    window.localStorage.clear();
    Auth.hasAuthCookie.mockReturnValue(true);
    Auth.logout.mockResolvedValue({});
    expiresIn(7 * 24 * HOUR);
  });

  afterEach(() => {
    scope?.stop();
    vi.useRealTimers();
  });

  it('keeps the session while the user is active', () => {
    start();
    vi.advanceTimersByTime(11 * HOUR);
    window.dispatchEvent(new Event('pointerdown'));
    vi.advanceTimersByTime(11 * HOUR);

    expect(Auth.logout).not.toHaveBeenCalled();
  });

  it('signs out and goes to the login after 12 hours without interaction', () => {
    start();
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS + 60 * 1000);

    expect(Auth.logout).toHaveBeenCalledTimes(1);
    expect(Auth.logout).toHaveBeenCalledWith({ redirectTo: SESSION_ENDED_URL });
  });

  it('ends a session left idle while the browser was closed', () => {
    window.localStorage.setItem(
      'lastUserActivityAt',
      String(Date.now() - 13 * HOUR)
    );
    start();

    expect(Auth.logout).toHaveBeenCalledWith({ redirectTo: SESSION_ENDED_URL });
  });

  it('does not let the first click after the limit revive the session', () => {
    start();
    vi.setSystemTime(Date.now() + 13 * HOUR);
    window.dispatchEvent(new Event('pointerdown'));

    expect(Auth.logout).toHaveBeenCalledTimes(1);
  });

  it('counts activity from another tab', () => {
    start();
    vi.advanceTimersByTime(11 * HOUR);
    window.localStorage.setItem('lastUserActivityAt', String(Date.now()));
    vi.advanceTimersByTime(11 * HOUR);

    expect(Auth.logout).not.toHaveBeenCalled();
  });

  it('goes to the login when the 7-day token expires', () => {
    expiresIn(30 * 60 * 1000);
    start();
    window.dispatchEvent(new Event('pointerdown'));
    vi.advanceTimersByTime(31 * 60 * 1000);

    expect(Auth.logout).toHaveBeenCalledWith({ redirectTo: SESSION_ENDED_URL });
  });

  it('clears the session locally when the token is already gone', async () => {
    Auth.logout.mockRejectedValue(new Error('401'));
    Auth.getAuthData.mockReturnValue(false);
    start();
    await vi.runOnlyPendingTimersAsync();

    expect(clearCookiesOnLogout).toHaveBeenCalledWith({
      redirectTo: SESSION_ENDED_URL,
    });
  });

  it('does nothing when signed out', () => {
    Auth.hasAuthCookie.mockReturnValue(false);
    start();
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS * 2);

    expect(Auth.logout).not.toHaveBeenCalled();
  });
});

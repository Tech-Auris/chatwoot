import { useEventListener, useIntervalFn, useThrottleFn } from '@vueuse/core';
import Auth from 'dashboard/api/auth';
import {
  clearCookiesOnLogout,
  deleteIndexedDBOnLogout,
  markUserActivity,
} from 'dashboard/store/utils/api';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

// Mirrors UserSession::IDLE_TIMEOUT. The 7-day limit is the token expiry.
export const IDLE_TIMEOUT_MS = 12 * 60 * 60 * 1000;
const CHECK_INTERVAL_MS = 60 * 1000;
const ACTIVITY_THROTTLE_MS = 10 * 1000;
const SESSION_ENDED_URL = '/app/login?error=session-ended';
// Only real interaction counts: background requests and incoming messages
// must not keep an unattended tab signed in.
const ACTIVITY_EVENTS = ['pointerdown', 'keydown', 'scroll', 'touchstart'];

const lastActivityAt = () =>
  Number(window.localStorage.getItem(LOCAL_STORAGE_KEYS.LAST_USER_ACTIVITY_AT));

const isIdle = () => Date.now() - lastActivityAt() >= IDLE_TIMEOUT_MS;

const isExpired = () => {
  const { expiry } = Auth.getAuthData() || {};
  return !expiry || Date.now() >= Number(expiry) * 1000;
};

let ending = false;

const endSession = async () => {
  if (ending) return;
  ending = true;
  try {
    await Auth.logout({ redirectTo: SESSION_ENDED_URL });
  } catch {
    // The token is already gone (expired, revoked or signed out elsewhere).
    deleteIndexedDBOnLogout();
    clearCookiesOnLogout({ redirectTo: SESSION_ENDED_URL });
  }
};

const checkSession = () => {
  if (isExpired() || isIdle()) endSession();
};

// Sends the dashboard to the login page when the session hits the 7-day limit
// or 12 hours pass without the user touching any tab.
export function useSessionTimeout() {
  if (!Auth.hasAuthCookie()) return;

  ending = false;
  if (!lastActivityAt()) markUserActivity();

  const throttledMark = useThrottleFn(markUserActivity, ACTIVITY_THROTTLE_MS);
  // Coming back after the limit must not count as activity and revive it.
  const onActivity = () => (isIdle() ? endSession() : throttledMark());

  ACTIVITY_EVENTS.forEach(event =>
    useEventListener(window, event, onActivity, {
      capture: true,
      passive: true,
    })
  );
  useEventListener(document, 'visibilitychange', checkSession);
  useEventListener(window, 'focus', checkSession);
  useIntervalFn(checkSession, CHECK_INTERVAL_MS);
  checkSession();
}

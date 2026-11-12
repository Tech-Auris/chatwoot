import SessionStorage from 'shared/helpers/sessionStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';

// An AI assistant (MCP connector) sends the user to the consent page; when
// they are not logged in yet, the page is remembered so the login returns
// there instead of the dashboard home.
const CONSENT_PATH = '/app/oauth/authorize?';

export const rememberOAuthReturn = fullPath => {
  SessionStorage.set(SESSION_STORAGE_KEYS.OAUTH_RETURN_TO, fullPath);
};

export const takeOAuthReturn = () => {
  const path = SessionStorage.get(SESSION_STORAGE_KEYS.OAUTH_RETURN_TO);
  SessionStorage.remove(SESSION_STORAGE_KEYS.OAUTH_RETURN_TO);
  return typeof path === 'string' && path.startsWith(CONSENT_PATH)
    ? path
    : null;
};

import Auth from '../api/auth';
import { clearCookiesOnLogout } from '../store/utils/api';

// A permission refusal answers 401 too, so a 401 only means "signed out" when
// the session itself no longer validates (logged out in another tab, revoked,
// expired). The tab then goes to the login instead of piling up 401s behind
// empty screens. One check at a time, and a valid session is not rechecked
// for a minute.
const SESSION_RECHECK_MS = 60 * 1000;
let sessionCheck = null;

const checkSessionEnded = () => {
  sessionCheck ??= Auth.validityCheck()
    .then(() => {
      setTimeout(() => {
        sessionCheck = null;
      }, SESSION_RECHECK_MS);
    })
    .catch(error => {
      if (error?.response?.status === 401) {
        clearCookiesOnLogout({ redirectTo: '/app/login?error=session-ended' });
      } else {
        sessionCheck = null;
      }
    });
};

export const resetSessionCheck = () => {
  sessionCheck = null;
};

const parseErrorCode = error => {
  if (
    error?.response?.status === 401 &&
    !error.config?.url?.includes('/auth/')
  ) {
    checkSessionEnded();
  }
  return Promise.reject(error);
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );
  return wootApi;
};

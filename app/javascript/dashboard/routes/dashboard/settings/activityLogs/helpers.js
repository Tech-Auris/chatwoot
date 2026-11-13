// Shared by the list and the detail drawer of the change history.

export const FILTERED = '[FILTERED]';

// i18n keys cannot carry "::" (Integrations::Hook).
export const typeKey = type => (type || '').replace(/::/g, '_');

export const formatDateTime = timestamp =>
  new Date(timestamp * 1000).toLocaleString(undefined, {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

export const formatValue = value => {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

export const SOURCE_CLASSES = {
  dashboard: 'bg-n-alpha-2 text-n-slate-12',
  api: 'bg-n-iris-3 text-n-iris-11',
  job: 'bg-n-blue-3 text-n-blue-11',
  super_admin: 'bg-n-amber-3 text-n-amber-11',
  login: 'bg-n-alpha-2 text-n-slate-11',
};

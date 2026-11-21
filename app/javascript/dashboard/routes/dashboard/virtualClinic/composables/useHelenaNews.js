import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

// What the manager tells each person on top of the clinic alerts: the
// notifications that arrived since they last opened her (the alerts of the
// AI team itself already show up as alerts) and a new version of the app,
// with a short summary. "Seen" is kept in this browser.
const RELEASE_FRESH_DAYS = 14;
const FIRST_LOOK_HOURS = 24;
const TEAM_ALERT = 'virtual_clinic_alert';

const read = key => {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
};
const write = (key, value) => {
  try {
    localStorage.setItem(key, value);
  } catch {
    // No storage (private window): she tells it again next time.
  }
};

// The bold titles of the release notes ("**Veja o agendamento…**"), or its
// first line when it has none.
export function releaseSummary(notes, limit = 3) {
  const titles = [...(notes || '').matchAll(/\*\*(.+?)\*\*/g)].map(match =>
    match[1].replace(/[.:]$/, '')
  );
  if (titles.length) return titles.slice(0, limit);
  const line = (notes || '')
    .split('\n')
    .map(text => text.replace(/^[#\-*\s]+/, '').trim())
    .find(Boolean);
  return line ? [line] : [];
}

export function useHelenaNews(userId) {
  const store = useStore();
  const { locale } = useI18n();
  const notifications = useMapGetter('notifications/getNotifications');
  const releases = useMapGetter('releases/getReleases');

  const seenKey = () => `virtual-clinic-news:${userId.value}`;
  const releaseKey = () => `virtual-clinic-release:${userId.value}`;
  const seenAt = ref(0);
  const seenRelease = ref('');

  const fresh = computed(() =>
    (notifications.value || []).filter(
      item =>
        !item.read_at &&
        item.notification_type !== TEAM_ALERT &&
        item.created_at > seenAt.value
    )
  );

  const release = computed(() => {
    const [latest] = releases.value || [];
    if (!latest || latest.tag === seenRelease.value) return null;
    const age = Date.now() - new Date(latest.published_at).getTime();
    if (age > RELEASE_FRESH_DAYS * 24 * 3600 * 1000) return null;
    const notes =
      latest.notes?.[locale.value === 'pt_BR' ? 'pt_BR' : 'en'] ||
      latest.notes?.pt_BR;
    return { tag: latest.tag, summary: releaseSummary(notes) };
  });

  const count = computed(() => fresh.value.length + (release.value ? 1 : 0));

  // Opening the manager: what she said is now seen.
  const markSeen = () => {
    seenAt.value = Math.floor(Date.now() / 1000);
    write(seenKey(), String(seenAt.value));
    if (release.value) {
      seenRelease.value = release.value.tag;
      write(releaseKey(), seenRelease.value);
    }
  };

  onMounted(() => {
    seenAt.value =
      Number(read(seenKey())) ||
      Math.floor(Date.now() / 1000) - FIRST_LOOK_HOURS * 3600;
    seenRelease.value = read(releaseKey()) || '';
    store.dispatch('notifications/index', { page: 1 });
    if (!releases.value?.length) store.dispatch('releases/fetch');
  });

  return { notifications: fresh, release, count, markSeen };
}

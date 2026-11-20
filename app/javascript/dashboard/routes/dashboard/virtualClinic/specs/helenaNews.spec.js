import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { releaseSummary, useHelenaNews } from '../composables/useHelenaNews';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ locale: { value: 'pt_BR' } }),
}));

const now = Math.floor(Date.now() / 1000);
const dispatch = vi.fn();
const notifications = [
  { id: 3, created_at: now - 60, notification_type: 'conversation_mention' },
  { id: 2, created_at: now - 120, notification_type: 'virtual_clinic_alert' },
  {
    id: 1,
    created_at: now - 3 * 24 * 3600,
    notification_type: 'conversation_assignment',
  },
  {
    id: 4,
    created_at: now - 30,
    read_at: now,
    notification_type: 'conversation_mention',
  },
];
const releases = [
  {
    tag: 'v1.83',
    published_at: new Date().toISOString(),
    notes: {
      pt_BR:
        '### Novidades\n\n- **Avatar no mapa.** Texto.\n- **Sentar.** Mais.',
    },
  },
];
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => ({
    value: key === 'releases/getReleases' ? releases : notifications,
  }),
}));

const mountNews = () => {
  let news;
  mount(
    defineComponent({
      setup() {
        news = useHelenaNews({ value: 1 });
        return () => h('div');
      },
    })
  );
  return news;
};

describe('Helena news', () => {
  beforeEach(() => localStorage.clear());

  it('summarizes the release notes by their bold titles', () => {
    expect(releaseSummary(releases[0].notes.pt_BR)).toEqual([
      'Avatar no mapa',
      'Sentar',
    ]);
    expect(releaseSummary('Correções de bugs e melhorias internas.')).toEqual([
      'Correções de bugs e melhorias internas.',
    ]);
  });

  it('counts the new notifications (not the team alerts) and the new version', () => {
    const news = mountNews();
    expect(news.notifications.value.map(item => item.id)).toEqual([3]);
    expect(news.release.value).toEqual({
      tag: 'v1.83',
      summary: ['Avatar no mapa', 'Sentar'],
    });
    expect(news.count.value).toBe(2);
    expect(dispatch).toHaveBeenCalledWith('notifications/index', { page: 1 });
  });

  it('forgets what was seen when the manager is opened', () => {
    const news = mountNews();
    news.markSeen();
    expect(news.count.value).toBe(0);
    expect(mountNews().count.value).toBe(0);
  });
});

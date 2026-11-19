import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import VirtualClinicShell from '../components/VirtualClinicShell.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'internal_chat_home', params: { accountId: '1' } }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 3 }),
}));

const mountShell = enabled =>
  mount(VirtualClinicShell, {
    props: { enabled },
    slots: { default: '<p>conteúdo</p>' },
    global: {
      stubs: { 'router-link': { template: '<a><slot /></a>' }, Icon: true },
    },
  });

describe('VirtualClinicShell', () => {
  it('shows the map/chat rail with the unread badge on released accounts', () => {
    const wrapper = mountShell(true);

    expect(wrapper.find('nav').exists()).toBe(true);
    expect(wrapper.find('nav').text()).toContain('3');
    expect(wrapper.text()).toContain('conteúdo');
  });

  it('renders only the content when the account is not released', () => {
    const wrapper = mountShell(false);

    expect(wrapper.find('nav').exists()).toBe(false);
    expect(wrapper.text()).toContain('conteúdo');
  });
});

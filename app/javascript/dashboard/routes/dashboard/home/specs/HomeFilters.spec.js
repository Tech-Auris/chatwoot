import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import HomeFilters from '../components/HomeFilters.vue';
import home from 'dashboard/i18n/locale/pt_BR/home.json';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: home },
});

const inboxes = [
  { id: 1, name: 'Clínica Centro' },
  { id: 2, name: 'Clínica Sul' },
  { id: 3, name: 'Clínica Norte' },
];

const mountFilters = (props = {}) =>
  mount(HomeFilters, {
    props: { period: '7d', inboxes, inboxIds: [], ...props },
    global: { plugins: [i18n] },
  });

const inboxButton = wrapper =>
  wrapper.findAll('button').find(button => button.text().startsWith('Caixas'));

describe('HomeFilters', () => {
  it('names the caixas behind the numbers instead of "Todas"', () => {
    expect(inboxButton(mountFilters()).text()).toContain(
      'Caixas: Clínica Centro + 2'
    );
    expect(inboxButton(mountFilters({ inboxIds: [1, 2] })).text()).toContain(
      'Caixas: Clínica Centro, Clínica Sul'
    );
  });

  it('unpicks a caixa from the full list', async () => {
    const wrapper = mountFilters();

    await inboxButton(wrapper).trigger('click');
    await wrapper.findAll('input[type="checkbox"]')[2].trigger('change');

    expect(wrapper.emitted('update:inboxIds')[0]).toEqual([[1, 2]]);
  });
});

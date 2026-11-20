import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import ChatChart from '../components/ChatChart.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-chartjs', () => ({
  Bar: { name: 'Bar', props: ['data', 'options'], template: '<canvas />' },
  Line: { name: 'Line', props: ['data', 'options'], template: '<canvas />' },
}));

const chart = {
  type: 'bar',
  title: 'Faltas por dia da semana',
  labels: ['seg', 'ter'],
  series: [{ name: 'Faltas', data: [3, 1] }],
};

describe('ChatChart', () => {
  it('draws the bars from the data and shows the numbers on demand', async () => {
    const wrapper = mount(ChatChart, { props: { chart } });

    const bar = wrapper.findComponent({ name: 'Bar' });
    expect(bar.props('data').labels).toEqual(['seg', 'ter']);
    expect(bar.props('data').datasets[0]).toMatchObject({
      label: 'Faltas',
      data: [3, 1],
    });
    expect(wrapper.find('table').exists()).toBe(false);

    await wrapper.find('button').trigger('click');
    expect(wrapper.find('table').text()).toContain('seg');
    expect(wrapper.find('table').text()).toContain('3');
  });

  it('draws a line for evolution over time', () => {
    const wrapper = mount(ChatChart, {
      props: { chart: { ...chart, type: 'line' } },
    });
    expect(wrapper.findComponent({ name: 'Line' }).exists()).toBe(true);
  });
});

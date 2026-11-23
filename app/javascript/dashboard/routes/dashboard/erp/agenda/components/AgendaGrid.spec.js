import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import AgendaGrid from './AgendaGrid.vue';
import AppointmentDialog from './AppointmentDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const appointment = {
  id: '10',
  starts_at: '2026-11-24T09:00:00-03:00',
  ends_at: '2026-11-24T09:30:00-03:00',
  patient_name: 'Maria Souza',
  professional_id: '25',
  professional_name: 'Dra. Ana',
  procedure_name: null,
  status: 'confirmed',
};

describe('AgendaGrid', () => {
  it('emits the appointment clicked', async () => {
    const wrapper = mount(AgendaGrid, {
      props: {
        columns: [
          { key: '25', label: 'Dra. Ana', appointments: [appointment] },
        ],
      },
      global: { mocks: { $t: key => key } },
    });

    await wrapper.find('button').trigger('click');

    expect(wrapper.emitted('select')).toEqual([[appointment]]);
  });
});

describe('AppointmentDialog', () => {
  it('shows the basic data of the appointment, with a dash for what the ERP lacks', async () => {
    const wrapper = mount(AppointmentDialog, {
      props: { locale: 'pt-BR' },
      global: {
        stubs: {
          Dialog: { template: '<div><slot /></div>', methods: { open() {} } },
        },
      },
    });

    wrapper.vm.open(appointment);
    await wrapper.vm.$nextTick();
    const text = wrapper.text();

    expect(text).toContain('Maria Souza');
    expect(text).toContain('Dra. Ana');
    expect(text).toContain('AGENDA.STATUS.CONFIRMED');
    expect(text).toContain('AGENDA.APPOINTMENT.PROCEDURE—');
  });
});

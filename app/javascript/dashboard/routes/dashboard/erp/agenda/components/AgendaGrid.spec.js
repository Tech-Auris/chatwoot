import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import AgendaGrid from './AgendaGrid.vue';
import AppointmentDialog from './AppointmentDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
}));

const RouterLink = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a><slot /></a>',
};

const appointment = {
  id: '10',
  starts_at: '2026-11-24T09:00:00-03:00',
  ends_at: '2026-11-24T09:30:00-03:00',
  patient_name: 'Maria Souza',
  professional_id: '25',
  professional_name: 'Dra. Ana',
  procedure_name: null,
  status: 'confirmed',
  auris_conversation_id: null,
};
const booked = { ...appointment, id: '11', auris_conversation_id: 42 };
const conversation42 = {
  name: 'inbox_conversation',
  params: { accountId: '1', conversation_id: 42 },
};

const mountGrid = appointments =>
  mount(AgendaGrid, {
    props: { columns: [{ key: '25', label: 'Dra. Ana', appointments }] },
    global: { mocks: { $t: key => key }, stubs: { RouterLink } },
  });

describe('AgendaGrid', () => {
  it('emits the appointment clicked', async () => {
    const wrapper = mountGrid([appointment]);

    await wrapper.find('[role="button"]').trigger('click');

    expect(wrapper.emitted('select')).toEqual([[appointment]]);
  });

  it('shows the Auris badge, linked to the conversation, only on what the AI booked', async () => {
    const wrapper = mountGrid([appointment, booked]);
    const links = wrapper.findAllComponents(RouterLink);

    expect(links).toHaveLength(1);
    expect(links[0].props('to')).toEqual(conversation42);
    expect(links[0].text()).toBe('AGENDA.AURIS.BADGE');

    await links[0].trigger('click');
    expect(wrapper.emitted('select')).toBeUndefined();
  });
});

describe('AppointmentDialog', () => {
  const mountDialog = item => {
    const wrapper = mount(AppointmentDialog, {
      props: { locale: 'pt-BR' },
      global: {
        stubs: {
          RouterLink,
          Dialog: { template: '<div><slot /></div>', methods: { open() {} } },
        },
      },
    });
    wrapper.vm.open(item);
    return wrapper.vm.$nextTick().then(() => wrapper);
  };

  it('shows the basic data of the appointment, with a dash for what the ERP lacks', async () => {
    const wrapper = await mountDialog(appointment);
    const text = wrapper.text();

    expect(text).toContain('Maria Souza');
    expect(text).toContain('Dra. Ana');
    expect(text).toContain('AGENDA.STATUS.CONFIRMED');
    expect(text).toContain('AGENDA.APPOINTMENT.PROCEDURE—');
    expect(text).not.toContain('AGENDA.AURIS.BOOKED');
  });

  it('opens the patient conversation of an appointment the AI booked', async () => {
    const wrapper = await mountDialog(booked);

    expect(wrapper.text()).toContain('AGENDA.AURIS.BOOKED');
    expect(wrapper.findComponent(RouterLink).props('to')).toEqual(
      conversation42
    );
  });
});

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import PeopleList from '../components/PeopleList.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, vars) => (vars ? `${key} ${JSON.stringify(vars)}` : key),
  }),
}));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push }),
}));

const now = Math.floor(Date.now() / 1000);
const dispatch = vi.fn(() => Promise.resolve({ id: 77 }));
const agents = [
  { id: 3, name: 'Juliana Reis', availability_status: 'offline' },
  { id: 2, name: 'Marcos Silva', availability_status: 'busy' },
  {
    id: 4,
    name: 'Ana Nova',
    availability_status: 'online',
    joined_at: now - 2 * 24 * 3600,
  },
  {
    id: 1,
    name: 'Dra. Paula',
    availability_status: 'online',
    joined_at: now - 90 * 24 * 3600,
  },
  {
    id: 10,
    name: 'IA | Auris',
    availability_status: 'online',
    is_ai_user: true,
  },
];
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await vi.importActual('vue');
  return {
    useStore: () => ({ dispatch }),
    useMapGetter: key => ref(key === 'getCurrentUserID' ? 1 : agents),
  };
});

// The row of each person (not the group headers or the row shortcuts).
const people = wrapper => wrapper.findAll('section > div > button');

describe('PeopleList', () => {
  beforeEach(() => vi.clearAllMocks());

  it('splits online and offline people, you first, without the AI user', () => {
    const wrapper = mount(PeopleList, { props: { peopleOnMap: [2] } });
    const [online, offline] = wrapper.findAll('section');

    expect(online.text()).toContain('GROUPS.ONLINE {"count":3}');
    const onlineNames = online.findAll('div > button');
    expect(onlineNames.map(b => b.text())).toEqual([
      expect.stringContaining('Dra. Paula'),
      expect.stringContaining('Ana Nova'),
      expect.stringContaining('Marcos Silva'),
    ]);
    expect(onlineNames[2].text()).toContain('PEOPLE.ON_MAP');
    expect(offline.text()).toContain('GROUPS.OFFLINE {"count":1}');
    expect(offline.text()).toContain('Juliana Reis');
    expect(wrapper.text()).not.toContain('IA | Auris');
  });

  it('marks who joined in the last two weeks as new', () => {
    const wrapper = mount(PeopleList);
    const [paula, ana] = people(wrapper);

    expect(ana.text()).toContain('PEOPLE.NEW');
    expect(paula.text()).not.toContain('PEOPLE.NEW');
  });

  it('searches by name and folds a group', async () => {
    const wrapper = mount(PeopleList);
    await wrapper.find('input').setValue('mar');
    expect(people(wrapper).map(b => b.text())).toEqual([
      expect.stringContaining('Marcos Silva'),
    ]);

    await wrapper.find('input').setValue('');
    await wrapper.findAll('section')[1].find('button').trigger('click');
    expect(wrapper.text()).not.toContain('Juliana Reis');
  });

  it('opens the DM, or your profile and avatar on yourself', async () => {
    const wrapper = mount(PeopleList);
    const [paula, ana] = people(wrapper);

    await paula.trigger('click');
    expect(wrapper.emitted('editProfile')).toHaveLength(1);
    await wrapper
      .find('[title="VIRTUAL_CLINIC.PROFILE.TITLE"]')
      .trigger('click');
    await wrapper
      .find('[title="VIRTUAL_CLINIC.AVATAR.TITLE"]')
      .trigger('click');
    expect(wrapper.emitted('editProfile')).toHaveLength(2);
    expect(wrapper.emitted('editAvatar')).toHaveLength(1);

    await ana.trigger('click');
    await Promise.resolve();
    expect(dispatch).toHaveBeenCalledWith('internalChat/create', {
      channel: { channel_type: 'dm' },
      member_ids: [4],
    });
    expect(push).toHaveBeenCalledWith({
      name: 'internal_chat_dm',
      params: { accountId: '1', channelId: 77 },
    });
  });
});

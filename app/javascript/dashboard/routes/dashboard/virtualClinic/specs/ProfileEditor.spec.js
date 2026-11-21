import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import ProfileEditor from '../components/ProfileEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const updateUISettings = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings }),
}));
vi.mock('../composables/useAvatarArt', () => ({
  useAvatarArt: () => ({ thumbnail: () => '' }),
}));

const dispatch = vi.fn(() => Promise.resolve());
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await vi.importActual('vue');
  return {
    useStore: () => ({ dispatch }),
    useMapGetter: () =>
      ref({ id: 1, name: 'Fábio Rocha', display_name: '', avatar_url: '' }),
  };
});

const DialogStub = defineComponent({
  emits: ['close'],
  setup(_, { slots, emit, expose }) {
    expose({ open: () => {}, close: () => emit('close') });
    return () => h('div', slots.default?.());
  },
});

const mountEditor = props =>
  mount(ProfileEditor, { props, global: { stubs: { Dialog: DialogStub } } });

describe('ProfileEditor', () => {
  it('saves the names to the profile and closes', async () => {
    const wrapper = mountEditor();
    const [name, displayName] = wrapper.findAll('input:not([type="file"])');
    await name.setValue('Fábio F. Rocha');
    await displayName.setValue('Fábio');

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await Promise.resolve();

    expect(dispatch).toHaveBeenCalledWith('updateProfile', {
      name: 'Fábio F. Rocha',
      displayName: 'Fábio',
      avatar: null,
    });
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('saves the look picked in the avatar editor with the profile', async () => {
    const look = { sheet: '8_pessoas/pessoa_03.png' };
    const wrapper = mountEditor({ avatar: look, newAvatar: look });

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await Promise.resolve();
    await Promise.resolve();

    expect(updateUISettings).toHaveBeenCalledWith({
      virtual_clinic_avatar: look,
    });
  });

  it('opens the avatar editor and stays open to come back to', async () => {
    const wrapper = mountEditor();
    await wrapper
      .find('[title="VIRTUAL_CLINIC.AVATAR.TITLE"]')
      .trigger('click');

    expect(wrapper.emitted('editAvatar')).toHaveLength(1);
    expect(wrapper.emitted('close')).toBeUndefined();
  });
});

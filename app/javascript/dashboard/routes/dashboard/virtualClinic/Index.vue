<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useEmitter } from 'dashboard/composables/emitter';
import VirtualClinicShell from './components/VirtualClinicShell.vue';
import TeamPanel from './components/TeamPanel.vue';
import AiChatPanel from './components/AiChatPanel.vue';
import ClinicMap from './components/ClinicMap.vue';
import EditorPanel from './components/EditorPanel.vue';
import AvatarEditor from './components/AvatarEditor.vue';
import { FLOORS, TEAM_AVATARS, sheetForUser } from './engine/layout';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useClinicLayout } from './composables/useClinicLayout';
import { useVirtualClinicConfig } from './composables/useVirtualClinicConfig';
import { useVirtualClinicStatus } from './composables/useVirtualClinicStatus';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { currentAccount } = useAccount();
const { configs, load } = useVirtualClinicConfig();
const selectedMember = ref('');
const map = ref(null);
// The clinic as the account arranged it, and the editor.
const editor = reactive(useClinicLayout());
const thinking = ref('');
const peopleOnMap = ref([]);
// Open alerts per AI teammate (the "❗"), kept live by the cable.
const alertCounts = useMapGetter('virtualClinic/getAlertCounts');
// The manager asking the secretary something (delegation), for the map.
const consulting = ref(null);
useEmitter('virtualClinicActivity', data => {
  consulting.value =
    data.state === 'asking'
      ? { persona: data.persona, target: data.target }
      : null;
});
const currentUser = useMapGetter('getCurrentUser');
const { uiSettings, updateUISettings } = useUISettings();

// The avatar of whoever opened the clinic.
const me = computed(() =>
  currentUser.value?.id
    ? {
        id: currentUser.value.id,
        name:
          currentUser.value.available_name ||
          currentUser.value.display_name ||
          currentUser.value.name,
        accountId: Number(route.params.accountId),
        pubsubToken: currentUser.value.pubsub_token,
        avatar: uiSettings.value.virtual_clinic_avatar || null,
      }
    : null
);

const clinicName = computed(() => currentAccount.value?.name || '');
const aiTeam = computed(() => configs.value[route.params.accountId] || null);
const { status } = useVirtualClinicStatus(
  computed(() => aiTeam.value?.visible === true)
);
// The avatar editor, for the user's own look (`{ persona: null }`) or for
// an AI teammate's (from the team panel, or while editing the clinic).
const avatarFor = ref(null);
const avatarEditor = computed(() => {
  if (!avatarFor.value) return null;
  const floor = editor.layout.floors[0].block;
  const { persona } = avatarFor.value;
  if (!persona) {
    return {
      title: t('VIRTUAL_CLINIC.AVATAR.TITLE'),
      name: me.value?.name,
      avatar: me.value?.avatar || { sheet: sheetForUser(me.value?.id) },
      floor,
    };
  }
  const member = aiTeam.value?.members.find(m => m.persona === persona);
  const spot = editor.layout.team[persona];
  const name = spot.name || member?.name || '';
  return {
    title: t('VIRTUAL_CLINIC.AVATAR.TITLE_TEAM', { name }),
    name,
    avatar: spot.avatar || { sheet: spot.sheet },
    base: TEAM_AVATARS[persona],
    floor,
  };
});
// A teammate in a premade character keeps it as `sheet`.
const teamLook = look =>
  look.sheet ? { sheet: look.sheet, avatar: undefined } : { avatar: look };
const saveAvatar = look => {
  const { persona } = avatarFor.value;
  if (!persona) updateUISettings({ virtual_clinic_avatar: look });
  else if (editor.editing) editor.setTeam(persona, teamLook(look));
  else editor.saveTeam(persona, teamLook(look));
};

const openMember = computed(() => {
  if (!aiTeam.value?.chat_enabled || editor.editing) return null;
  return aiTeam.value.members.find(m => m.persona === selectedMember.value);
});

const closeChat = () => {
  selectedMember.value = '';
  if (route.query.member) router.replace({ query: {} });
};

// The chat list sends people here with `?member=` to open an AI teammate.
watch(
  () => route.query.member,
  member => {
    if (member) selectedMember.value = member;
  },
  { immediate: true }
);

const startEditing = () => {
  closeChat();
  editor.start();
};

// Saved by someone (maybe in another tab): draw it again, with the names.
const reloadLayout = () => {
  editor.load();
  load(route.params.accountId);
};

const saveLayout = async () => {
  const saved = await editor.save(
    map.value.check(editor.layout),
    t('VIRTUAL_CLINIC.EDITOR.ERRORS.SAVE')
  );
  if (saved) load(route.params.accountId);
};

// A new piece goes in the middle of the room it belongs to.
const ROOM_OF_FOLDER = {
  '1_recepcao': 0,
  '2_sala_de_espera': 1,
  '3_gerencia': 2,
  '4_copa': 3,
};
const addItem = sprite => {
  const room = FLOORS[ROOM_OF_FOLDER[sprite.split('/')[0]]];
  editor.addItem(sprite, room.x + room.w / 2 - 16, room.y + room.h / 2 - 16);
};

onMounted(() => {
  load(route.params.accountId);
  editor.load();
  store.dispatch('agents/get');
});
</script>

<template>
  <VirtualClinicShell>
    <EditorPanel
      v-if="editor.editing"
      :editor="editor"
      :members="aiTeam?.members || []"
      @save="saveLayout"
      @add-item="addItem"
      @edit-avatar="avatarFor = { persona: $event }"
    />
    <TeamPanel
      v-else
      :clinic-name="clinicName"
      :ai-team="aiTeam"
      :status="status"
      :selected="selectedMember"
      :people-on-map="peopleOnMap"
      :alert-counts="alertCounts"
      @select-member="selectedMember = $event"
      @edit="startEditing"
      @edit-avatar="avatarFor = { persona: $event || null }"
    />
    <ClinicMap
      ref="map"
      :ai-team="aiTeam"
      :status="status"
      :thinking="thinking"
      :focused="openMember?.persona || ''"
      :me="me"
      :layout="editor.layout"
      :editor="editor"
      :consulting="consulting"
      :alert-counts="alertCounts"
      @select-member="selectedMember = $event"
      @people-on-map="peopleOnMap = $event"
      @layout-changed="reloadLayout"
    />
    <AiChatPanel
      v-if="openMember"
      :key="openMember.persona"
      :member="openMember"
      :alert-count="alertCounts[openMember.persona] || 0"
      @thinking="thinking = $event"
      @close="closeChat"
    />
    <AvatarEditor
      v-if="avatarEditor"
      v-bind="avatarEditor"
      @save="saveAvatar"
      @close="avatarFor = null"
    />
  </VirtualClinicShell>
</template>

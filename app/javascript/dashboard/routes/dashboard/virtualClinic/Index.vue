<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import VirtualClinicShell from './components/VirtualClinicShell.vue';
import TeamPanel from './components/TeamPanel.vue';
import AiChatPanel from './components/AiChatPanel.vue';
import ClinicMap from './components/ClinicMap.vue';
import EditorPanel from './components/EditorPanel.vue';
import { FLOORS } from './engine/layout';
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
const currentUser = useMapGetter('getCurrentUser');

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
      }
    : null
);

const clinicName = computed(() => currentAccount.value?.name || '');
const aiTeam = computed(() => configs.value[route.params.accountId] || null);
const { status } = useVirtualClinicStatus(
  computed(() => aiTeam.value?.visible === true)
);
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
    />
    <TeamPanel
      v-else
      :clinic-name="clinicName"
      :ai-team="aiTeam"
      :status="status"
      :selected="selectedMember"
      :people-on-map="peopleOnMap"
      @select-member="selectedMember = $event"
      @edit="startEditing"
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
      @select-member="selectedMember = $event"
      @people-on-map="peopleOnMap = $event"
      @layout-changed="reloadLayout"
    />
    <AiChatPanel
      v-if="openMember"
      :key="openMember.persona"
      :member="openMember"
      @thinking="thinking = $event"
      @close="closeChat"
    />
  </VirtualClinicShell>
</template>

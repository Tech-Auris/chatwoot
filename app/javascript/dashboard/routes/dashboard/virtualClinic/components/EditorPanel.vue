<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAssetThumbnails } from '../composables/useAssetThumbnails';
import { useAvatarArt } from '../composables/useAvatarArt';

// Left panel while editing the clinic: the AI team (name and look), room
// names, floors and walls, and the furniture catalog. Pieces and teammates
// are moved on the map itself.
const props = defineProps({
  editor: { type: Object, required: true },
  members: { type: Array, default: () => [] },
});
const emit = defineEmits(['save', 'addItem', 'editAvatar']);

const { t } = useI18n();
const { thumbnail } = useAssetThumbnails();
const avatarArt = useAvatarArt();
const paths = ref([]);
const confirmingRestore = ref(false);

const FURNITURE_FOLDERS = [
  '1_recepcao',
  '2_sala_de_espera',
  '3_gerencia',
  '4_copa',
];
const ROOM_OF_FOLDER = ['RECEPTION', 'WAITING_ROOM', 'MANAGEMENT', 'KITCHEN'];

const inFolder = pattern => paths.value.filter(path => pattern.test(path));
const floors = computed(() => inFolder(/^5_pisos\//));
const walls = computed(() => inFolder(/^6_paredes\//));
const catalog = computed(() =>
  FURNITURE_FOLDERS.map((folder, index) => ({
    folder,
    room: ROOM_OF_FOLDER[index],
    paths: inFolder(new RegExp(`^${folder}/`)),
  }))
);

const layout = computed(() => props.editor.layout);
const roomLabel = key => t(`VIRTUAL_CLINIC.MAP.ROOMS.${key}`);
const selectedItem = computed(() => props.editor.selected?.kind === 'item');

// The teammate standing: their look from the avatar editor, or the art.
const lookOf = persona => {
  const { avatar, sheet } = layout.value.team[persona];
  return avatar ? avatarArt.thumbnail(avatar) : thumbnail(sheet);
};

const rename = (persona, value) =>
  props.editor.setTeam(persona, { name: value.trim() || undefined });

const restore = async () => {
  if (!confirmingRestore.value) {
    confirmingRestore.value = true;
    return;
  }
  confirmingRestore.value = false;
  await props.editor.restore();
};

onMounted(async () => {
  const { data } = await VirtualClinicAPI.listAssets();
  paths.value = data.paths;
});
</script>

<template>
  <section
    class="flex flex-col w-72 shrink-0 border-r border-n-weak bg-n-solid-1"
  >
    <header class="flex flex-col gap-2 p-4 border-b border-n-weak">
      <h1 class="text-base font-semibold text-n-slate-12">
        {{ t('VIRTUAL_CLINIC.EDITOR.TITLE') }}
      </h1>
      <p class="text-xs text-n-slate-11">
        {{ t('VIRTUAL_CLINIC.EDITOR.HINT') }}
      </p>
      <div class="flex gap-2">
        <Button
          :label="t('VIRTUAL_CLINIC.EDITOR.SAVE')"
          size="sm"
          :is-loading="editor.saving"
          @click="emit('save')"
        />
        <Button
          :label="t('VIRTUAL_CLINIC.EDITOR.DISCARD')"
          size="sm"
          variant="faded"
          color="slate"
          @click="editor.discard()"
        />
      </div>
      <p v-if="editor.error" class="text-xs text-n-ruby-11">
        {{ editor.error }}
      </p>
      <div v-if="selectedItem" class="flex flex-wrap items-center gap-1 pt-1">
        <span class="w-full text-xs font-medium text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.EDITOR.SELECTED') }}
        </span>
        <Button
          :label="t('VIRTUAL_CLINIC.EDITOR.FLIP')"
          size="xs"
          variant="ghost"
          icon="i-lucide-flip-horizontal-2"
          @click="editor.flipSelected()"
        />
        <Button
          :label="t('VIRTUAL_CLINIC.EDITOR.REMOVE')"
          size="xs"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          @click="editor.removeSelected()"
        />
      </div>
    </header>

    <div class="flex flex-col flex-1 gap-5 p-4 overflow-y-auto">
      <div class="flex flex-col gap-3">
        <h2 class="text-xs font-medium text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.EDITOR.TEAM') }}
        </h2>
        <div
          v-for="member in members"
          :key="member.persona"
          class="flex flex-col gap-2"
        >
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
            <input
              :value="layout.team[member.persona].name || ''"
              :placeholder="member.name"
              maxlength="40"
              class="px-2 py-1 text-sm border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12"
              @change="rename(member.persona, $event.target.value)"
            />
          </label>
          <div class="flex items-center gap-3">
            <div
              class="grid w-10 h-16 overflow-hidden border rounded-lg place-items-center border-n-weak bg-n-alpha-1"
            >
              <img
                v-if="lookOf(member.persona)"
                :src="lookOf(member.persona)"
                alt=""
                class="object-contain w-8 [image-rendering:pixelated]"
              />
            </div>
            <Button
              :label="t('VIRTUAL_CLINIC.AVATAR.EDIT')"
              size="xs"
              variant="faded"
              color="slate"
              icon="i-lucide-shirt"
              @click="emit('editAvatar', member.persona)"
            />
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <h2 class="text-xs font-medium text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.EDITOR.ROOMS') }}
        </h2>
        <input
          v-for="room in layout.rooms"
          :key="room.key"
          :value="room.name || ''"
          :placeholder="roomLabel(room.key)"
          maxlength="40"
          class="px-2 py-1 text-sm border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12"
          @change="editor.renameRoom(room.key, $event.target.value)"
        />
      </div>

      <div class="flex flex-col gap-2">
        <h2 class="text-xs font-medium text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.EDITOR.FLOORS') }}
        </h2>
        <div
          v-for="(floor, index) in layout.floors"
          :key="`floor-${index}`"
          class="flex flex-col gap-1"
        >
          <span class="text-xs text-n-slate-11">
            {{ roomLabel(ROOM_OF_FOLDER[index]) }}
          </span>
          <div class="flex flex-wrap gap-1">
            <button
              v-for="block in floors"
              :key="block"
              type="button"
              class="w-12 h-8 overflow-hidden border rounded"
              :class="
                floor.block === block
                  ? 'border-n-brand ring-1 ring-n-brand'
                  : 'border-n-weak hover:border-n-slate-8'
              "
              @click="editor.setBlock('floors', index, block)"
            >
              <img
                v-if="thumbnail(block)"
                :src="thumbnail(block)"
                alt=""
                class="object-cover w-full h-full [image-rendering:pixelated]"
              />
            </button>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <h2 class="text-xs font-medium text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.EDITOR.WALLS') }}
        </h2>
        <div
          v-for="(wall, index) in layout.walls"
          :key="`wall-${index}`"
          class="flex flex-col gap-1"
        >
          <span class="text-xs text-n-slate-11">
            {{ t(`VIRTUAL_CLINIC.EDITOR.WALL_AREAS.${index}`) }}
          </span>
          <div class="flex flex-wrap gap-1">
            <button
              v-for="block in walls"
              :key="block"
              type="button"
              class="w-12 h-8 overflow-hidden border rounded"
              :class="
                wall.block === block
                  ? 'border-n-brand ring-1 ring-n-brand'
                  : 'border-n-weak hover:border-n-slate-8'
              "
              @click="editor.setBlock('walls', index, block)"
            >
              <img
                v-if="thumbnail(block)"
                :src="thumbnail(block)"
                alt=""
                class="object-cover w-full h-full [image-rendering:pixelated]"
              />
            </button>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <h2 class="text-xs font-medium text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.EDITOR.FURNITURE') }}
        </h2>
        <p class="text-xs text-n-slate-10">
          {{ t('VIRTUAL_CLINIC.EDITOR.FURNITURE_HINT') }}
        </p>
        <div
          v-for="group in catalog"
          :key="group.folder"
          class="flex flex-col gap-1"
        >
          <span class="text-xs text-n-slate-11">{{
            roomLabel(group.room)
          }}</span>
          <div class="grid grid-cols-5 gap-1">
            <button
              v-for="sprite in group.paths"
              :key="sprite"
              type="button"
              class="grid border rounded aspect-square place-items-center border-n-weak bg-n-alpha-1 hover:border-n-slate-8"
              @click="emit('addItem', sprite)"
            >
              <img
                v-if="thumbnail(sprite)"
                :src="thumbnail(sprite)"
                alt=""
                class="object-contain max-w-full max-h-full p-0.5 [image-rendering:pixelated]"
              />
            </button>
          </div>
        </div>
      </div>

      <Button
        :label="
          confirmingRestore
            ? t('VIRTUAL_CLINIC.EDITOR.RESTORE_CONFIRM')
            : t('VIRTUAL_CLINIC.EDITOR.RESTORE')
        "
        size="sm"
        variant="faded"
        color="ruby"
        icon="i-lucide-rotate-ccw"
        @click="restore"
      />
    </div>
  </section>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  PARTS,
  avatarCatalog,
  colorsOf,
  optionsOf,
  randomAvatar,
} from '../engine/avatar';
import {
  IDLE_FRONT,
  drawLook,
  loadArt,
  useAvatarArt,
} from '../composables/useAvatarArt';

// Gather-style avatar editor: the parts on the left, the choices of the
// part in the middle (style, then color dots) and, on the right, the look
// standing on the clinic floor with its name tag.
const props = defineProps({
  title: { type: String, required: true },
  // Name shown over the head in the preview.
  name: { type: String, default: '' },
  // The look to start from (`{ body, eyes, outfit, hair?, accessory? }`),
  // or null for a random one.
  avatar: { type: Object, default: null },
  // Floor art under the preview.
  floor: { type: String, default: '' },
});
const emit = defineEmits(['save', 'close']);

const { t } = useI18n();
const { thumbnail, swatch } = useAvatarArt();
const dialog = ref(null);
const catalog = ref(null);
const look = ref(props.avatar ? { ...props.avatar } : null);
const part = ref('body');

const ICONS = {
  body: 'i-lucide-hand',
  eyes: 'i-lucide-eye',
  outfit: 'i-lucide-shirt',
  hair: 'i-lucide-scissors',
  accessory: 'i-lucide-glasses',
};
const currentPart = computed(() => PARTS.find(({ key }) => key === part.value));
const options = computed(() =>
  catalog.value ? optionsOf(catalog.value, part.value, look.value) : []
);
const colors = computed(() =>
  catalog.value ? colorsOf(catalog.value, part.value, look.value) : []
);
const sameStyle = (a, b) =>
  a && b && a.split('_32x32_')[0] === b.split('_32x32_')[0];
const isPicked = option =>
  options.value.length && colors.value.length
    ? sameStyle(look.value[part.value], option)
    : look.value[part.value] === option;

const choose = layer => {
  const next = { ...look.value };
  if (layer) next[part.value] = layer;
  else delete next[part.value];
  look.value = next;
};
const shuffle = () => {
  look.value = randomAvatar(catalog.value);
};
const preview = option => ({ ...look.value, [part.value]: option });

// The preview: the floor, and the look breathing (standing frames).
const canvas = ref(null);
// 56×104 world px: four times that fills the preview column.
const PREVIEW = { width: 56, height: 104 };
const STAND = { x: 12, y: 28 };
let frames = null;
let floorArt = null;
let timer = null;
let tick = 0;
const paint = () => {
  const context = canvas.value?.getContext('2d');
  if (!context) return;
  context.imageSmoothingEnabled = false;
  context.clearRect(0, 0, PREVIEW.width, PREVIEW.height);
  if (floorArt) {
    context.fillStyle = context.createPattern(floorArt, 'repeat');
    context.fillRect(0, 0, PREVIEW.width, PREVIEW.height);
  }
  if (frames) {
    context.drawImage(
      frames,
      (tick % 6) * 32,
      0,
      32,
      IDLE_FRONT.height,
      STAND.x,
      STAND.y,
      32,
      IDLE_FRONT.height
    );
  }
};
watch(
  look,
  async value => {
    if (!value) return;
    const drawn = await drawLook(value, IDLE_FRONT);
    if (value === look.value) {
      frames = drawn;
      paint();
    }
  },
  { immediate: true }
);

const save = () => {
  emit('save', look.value);
  dialog.value.close();
};

onMounted(async () => {
  dialog.value.open();
  const { data } = await VirtualClinicAPI.listAssets();
  catalog.value = avatarCatalog(data.paths);
  look.value ||= randomAvatar(catalog.value);
  if (props.floor) {
    floorArt = await loadArt(props.floor);
    paint();
  }
  timer = setInterval(() => {
    tick += 1;
    paint();
  }, 160);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="title"
    :confirm-button-label="t('VIRTUAL_CLINIC.AVATAR.DONE')"
    :disable-confirm-button="!look"
    @confirm="save"
    @close="emit('close')"
  >
    <div class="flex gap-4 h-[26rem]">
      <nav class="flex flex-col w-36 gap-1 shrink-0">
        <button
          v-for="{ key } in PARTS"
          :key="key"
          type="button"
          class="flex items-center gap-2 px-3 py-2 text-sm text-left rounded-lg"
          :class="
            part === key
              ? 'bg-n-brand text-white'
              : 'text-n-slate-12 hover:bg-n-alpha-2'
          "
          @click="part = key"
        >
          <Icon :icon="ICONS[key]" class="size-4" />
          {{ t(`VIRTUAL_CLINIC.AVATAR.PARTS.${key.toUpperCase()}`) }}
        </button>
      </nav>

      <div class="flex flex-col flex-1 min-w-0 gap-3">
        <div
          class="grid content-start flex-1 grid-cols-4 gap-2 p-3 overflow-y-auto rounded-xl bg-n-alpha-1"
        >
          <button
            v-if="currentPart.optional"
            type="button"
            class="grid rounded-lg aspect-[32/52] place-items-center bg-n-solid-1"
            :class="
              look && !look[part]
                ? 'ring-2 ring-n-brand'
                : 'hover:ring-1 hover:ring-n-slate-7'
            "
            :title="t('VIRTUAL_CLINIC.AVATAR.NONE')"
            @click="choose(null)"
          >
            <Icon icon="i-lucide-ban" class="size-6 text-n-slate-10" />
          </button>
          <button
            v-for="option in look ? options : []"
            :key="option"
            type="button"
            class="grid p-1 rounded-lg aspect-[32/52] place-items-center bg-n-solid-1"
            :class="
              isPicked(option)
                ? 'ring-2 ring-n-brand'
                : 'hover:ring-1 hover:ring-n-slate-7'
            "
            @click="choose(option)"
          >
            <img
              v-if="thumbnail(preview(option))"
              :src="thumbnail(preview(option))"
              alt=""
              class="object-contain w-full h-full [image-rendering:pixelated]"
            />
          </button>
        </div>
        <div
          v-if="colors.length"
          class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-xl bg-n-alpha-1"
        >
          <button
            v-for="color in colors"
            :key="color"
            type="button"
            class="w-7 h-7 p-0 overflow-hidden rounded-full shrink-0 ring-offset-2 ring-offset-n-solid-1"
            :class="
              look[part] === color
                ? 'ring-2 ring-n-brand'
                : 'ring-1 ring-n-weak'
            "
            @click="choose(color)"
          >
            <img
              v-if="swatch(color)"
              :src="swatch(color)"
              alt=""
              class="w-full h-full"
            />
          </button>
        </div>
      </div>

      <div
        class="relative flex flex-col items-center w-56 overflow-hidden shrink-0 rounded-xl bg-n-alpha-1"
      >
        <span
          v-if="name"
          class="absolute flex items-center gap-1.5 px-2 py-1 text-xs font-medium text-white rounded-lg top-36 bg-n-slate-12 dark:bg-n-solid-3"
        >
          <span class="rounded-full size-2 bg-n-teal-9" />
          {{ name }}
        </span>
        <canvas
          ref="canvas"
          :width="PREVIEW.width"
          :height="PREVIEW.height"
          class="w-full h-full [image-rendering:pixelated]"
        />
        <Button
          v-tooltip="t('VIRTUAL_CLINIC.AVATAR.RANDOM')"
          type="button"
          icon="i-lucide-dices"
          size="sm"
          color="slate"
          variant="faded"
          class="absolute bottom-3 right-3"
          :disabled="!catalog"
          @click="shuffle"
        />
      </div>
    </div>
  </Dialog>
</template>

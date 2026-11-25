<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  PARTS,
  PREMADE_LOOKS,
  avatarCatalog,
  colorOf,
  colorsOf,
  optionsOf,
  randomAvatar,
  splitLayer,
} from '../engine/avatar';
import { premadeSheets } from '../engine/layout';
import { hiddenAccessories } from '../engine/seasons';
import {
  IDLE_FRONT,
  drawLook,
  loadArt,
  useAvatarArt,
} from '../composables/useAvatarArt';

// Gather-style avatar editor: "Avatar" (premade characters) and the parts
// on the left, the choices in the middle (style, then color dots) and, on
// the right, the look standing on the clinic floor with its name tag.
const props = defineProps({
  title: { type: String, required: true },
  // Name shown over the head in the preview.
  name: { type: String, default: '' },
  // The look worn now: a premade character (`{ sheet }`) or the parts
  // (`{ body, eyes, outfit, hair?, accessory? }`).
  avatar: { type: Object, required: true },
  // Floor art under the preview.
  floor: { type: String, default: '' },
  // Decoration packs (clinic config): accessories out of season are hidden.
  seasons: { type: Object, default: null },
});
const emit = defineEmits(['save', 'close']);

const { t } = useI18n();
const { thumbnail, swatch } = useAvatarArt();
const dialog = ref(null);
const catalog = ref(null);
const premades = ref([]);
const look = ref({ ...props.avatar });
// The look as parts: what the premade character picked is made of, so
// changing a part keeps the rest of it.
const partsOf = worn =>
  worn.sheet ? PREMADE_LOOKS[worn.sheet] || null : { ...worn };
const parts = ref(partsOf(props.avatar));
const part = ref(props.avatar.sheet ? 'premade' : 'body');

const MENU = [{ key: 'premade' }, ...PARTS];
const ICONS = {
  premade: 'i-lucide-user-round',
  body: 'i-lucide-hand',
  eyes: 'i-lucide-eye',
  outfit: 'i-lucide-shirt',
  hair: 'i-lucide-scissors',
  accessory: 'i-lucide-glasses',
};
const currentPart = computed(() => PARTS.find(({ key }) => key === part.value));
// The color picked last for each part, kept when the part is left out ("none")
// so the grid and the dots stay in it.
const tints = ref({});
const tint = computed(() =>
  colorOf(parts.value || {}, part.value, tints.value[part.value])
);
const options = computed(() =>
  catalog.value && parts.value
    ? optionsOf(catalog.value, part.value, parts.value, tint.value)
    : []
);
const colors = computed(() =>
  catalog.value && parts.value
    ? colorsOf(catalog.value, part.value, parts.value)
    : []
);
const sameStyle = (a, b) =>
  a && b && a.split('_32x32_')[0] === b.split('_32x32_')[0];
const isPicked = option =>
  colors.value.length
    ? sameStyle(parts.value[part.value], option)
    : parts.value[part.value] === option;

const wear = next => {
  parts.value = next;
  look.value = next;
};
const choose = layer => {
  tints.value = { ...tints.value, [part.value]: tint.value };
  const next = { ...parts.value };
  if (layer) next[part.value] = layer;
  else delete next[part.value];
  wear(next);
};
// A dot: the color of the part worn now, or of the grid when it is left out.
const pickColor = layer => {
  if (parts.value[part.value]) choose(layer);
  else tints.value = { ...tints.value, [part.value]: splitLayer(layer).color };
};
const choosePremade = sheet => {
  look.value = { sheet };
  parts.value = partsOf(look.value) || parts.value;
};
const shuffle = () => wear(randomAvatar(catalog.value));
const preview = option => ({ ...parts.value, [part.value]: option });

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
  const hidden = hiddenAccessories(props.seasons);
  catalog.value = avatarCatalog(
    data.paths.filter(
      path => !hidden.some(accessory => path.includes(`/${accessory}_32x32_`))
    )
  );
  premades.value = premadeSheets(data.paths);
  parts.value ||= randomAvatar(catalog.value);
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
    @confirm="save"
    @close="emit('close')"
  >
    <div class="flex gap-4 h-[26rem]">
      <nav class="flex flex-col w-36 gap-1 shrink-0">
        <button
          v-for="{ key } in MENU"
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
          <template v-if="part === 'premade'">
            <button
              v-for="sheet in premades"
              :key="sheet"
              type="button"
              class="grid p-1 rounded-lg aspect-[32/52] place-items-center bg-n-solid-1"
              :class="
                look.sheet === sheet
                  ? 'ring-2 ring-n-brand'
                  : 'hover:ring-1 hover:ring-n-slate-7'
              "
              @click="choosePremade(sheet)"
            >
              <img
                v-if="thumbnail({ sheet })"
                :src="thumbnail({ sheet })"
                alt=""
                class="object-contain w-full h-full [image-rendering:pixelated]"
              />
            </button>
          </template>
          <button
            v-if="currentPart?.optional"
            type="button"
            class="grid rounded-lg aspect-[32/52] place-items-center bg-n-solid-1"
            :class="
              parts && !parts[part]
                ? 'ring-2 ring-n-brand'
                : 'hover:ring-1 hover:ring-n-slate-7'
            "
            :title="t('VIRTUAL_CLINIC.AVATAR.NONE')"
            @click="choose(null)"
          >
            <Icon icon="i-lucide-ban" class="size-6 text-n-slate-10" />
          </button>
          <button
            v-for="option in part === 'premade' ? [] : options"
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
          v-if="part !== 'premade' && colors.length"
          class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-xl bg-n-alpha-1"
        >
          <button
            v-for="color in colors"
            :key="color"
            type="button"
            class="w-7 h-7 p-0 overflow-hidden rounded-full shrink-0 ring-offset-2 ring-offset-n-solid-1"
            :class="
              splitLayer(color).color === tint
                ? 'ring-2 ring-n-brand'
                : 'ring-1 ring-n-weak'
            "
            @click="pickColor(color)"
          >
            <img
              v-if="swatch(color, colors)"
              :src="swatch(color, colors)"
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

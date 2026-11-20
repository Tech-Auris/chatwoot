<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  CHARACTERS,
  ENTRANCE,
  ITEMS,
  ROOMS,
  SPRITE_PATHS,
  TILE,
  WORLD,
  sheetForUser,
} from '../engine/layout';
import { loadSprites } from '../engine/sprites';
import { createRenderer, hitTest } from '../engine/renderer';
import { createTeamBehavior } from '../engine/behavior';
import {
  buildCollision,
  cellOf,
  centerOf,
  feetOf,
  frameAt,
  isFree,
} from '../engine/collision';
import { corners, findPath } from '../engine/pathfinding';
import { createAvatar } from '../engine/movement';
import { useClinicPresence } from '../composables/useClinicPresence';
import { isOffDuty, offDutyReason } from '../teamStatus';

const props = defineProps({
  aiTeam: { type: Object, default: null },
  status: { type: Object, default: null },
  thinking: { type: String, default: '' },
  focused: { type: String, default: '' },
  // The user's own avatar: `{ id, name, accountId, pubsubToken }`.
  me: { type: Object, default: null },
});
const emit = defineEmits(['selectMember', 'peopleOnMap']);

const { t } = useI18n();
const FRAME_MS = 100;
const ROTATE_MS = 10000;

const viewport = ref(null);
const canvas = ref(null);
const loading = ref(true);
const failed = ref(false);
const scale = ref(1);
const fitScale = ref(1);
const userZoomed = ref(false);
const MAX_SCALE = 4;
const minScale = computed(() => Math.min(1, fitScale.value * 0.75));
const tick = ref(0);
const rotation = ref(0);
let draw = null;
let behavior = null;
const positions = ref({});
let rotateTimer = null;
let resizeObserver = null;
let animationFrame = null;
let lastFrame = null;

// The user's avatar and everyone else walking around (Gather-style).
let sprites = null;
let grid = null;
let avatar = null;
const mine = ref(null);
const presence = useClinicPresence();
const loadingSheets = new Set();
// The counter keeps people about three tiles from Clara.
const NEAR = 4 * TILE;
// The "how to walk" hint goes away once the user has walked.
const hasWalked = ref(false);

const members = computed(() =>
  props.aiTeam?.visible ? props.aiTeam.members : []
);
// Talking to them needs the clinic's OpenAI key; Clara is only faded when
// she is not serving patients (the n8n secretary), which is another switch.
const chatEnabled = computed(() => props.aiTeam?.chat_enabled === true);
const secretaryBusy = computed(
  () => (props.status?.secretary?.active_conversations || 0) > 0
);

// Where each teammate is now (they take little walks, see engine/trips.js).
const placeOf = persona => {
  const spot = CHARACTERS[persona];
  return positions.value[persona] || { x: spot.x, y: spot.y };
};

const team = computed(() =>
  members.value.map(member => {
    const place = placeOf(member.persona);
    return {
      persona: member.persona,
      x: place.x,
      y: place.y,
      direction: place.direction || 'down',
      moving: place.moving,
      talking: place.talking,
      sitting: place.sitting,
      phone:
        member.persona === 'secretary' && secretaryBusy.value && !place.away,
      faded: isOffDuty(member.persona, props.status),
    };
  })
);

const people = computed(() => {
  const list = Object.entries(presence.others.value).map(([id, place]) => ({
    ...place,
    userId: Number(id),
    sheet: sheetForUser(Number(id)),
  }));
  if (mine.value && props.me) {
    list.push({
      ...mine.value,
      userId: props.me.id,
      name: props.me.name,
      sheet: sheetForUser(props.me.id),
      self: true,
    });
  }
  return list;
});

const characters = computed(() => [...team.value, ...people.value]);

// The AI teammate within four tiles of the avatar: "Conversar com a Clara (E)".
const nearMember = computed(() => {
  if (!mine.value || !chatEnabled.value) return null;
  const feet = feetOf(mine.value);
  const member = members.value.find(({ persona }) => {
    const other = feetOf(placeOf(persona));
    return Math.hypot(other.x - feet.x, other.y - feet.y) <= NEAR;
  });
  return member && member.persona !== props.focused ? member : null;
});

// Name (and status above it) sit right over the head, like in Gather, and
// follow the teammate around. The frame is 32×64 with the head from ~y+18.
const overHead = persona => {
  const place = placeOf(persona);
  return { x: place.x + 16, y: place.y + 18 };
};

// Nobody leaves while the user talks to them or when off duty.
const canLeave = persona =>
  persona !== props.focused &&
  persona !== props.thinking &&
  !isOffDuty(persona, props.status);

watch(
  () => members.value.map(member => member.persona).join(),
  personaList => {
    behavior = personaList
      ? createTeamBehavior({ personas: personaList.split(','), canLeave })
      : null;
    positions.value = {};
  },
  { immediate: true }
);

// What each teammate is doing, over their head (hidden while away).
const bubble = persona => {
  if (props.thinking === persona) return t('VIRTUAL_CLINIC.MAP.THINKING');
  if (placeOf(persona).away) return '';
  if (!props.status) return '';
  if (isOffDuty(persona, props.status)) {
    return t('VIRTUAL_CLINIC.MAP.OFF_DUTY', {
      reason: offDutyReason(props.status, t),
    });
  }
  if (persona === 'secretary') {
    const { active_conversations: active, in_follow_up: followUps } =
      props.status.secretary;
    return active || followUps
      ? t('VIRTUAL_CLINIC.MAP.SECRETARY', { active, followUps })
      : t('VIRTUAL_CLINIC.MAP.IDLE');
  }
  const {
    leads,
    appointments,
    conversion_rate: rate,
  } = props.status.manager.month;
  const lines = [
    t('VIRTUAL_CLINIC.MAP.LEADS', { leads }),
    t('VIRTUAL_CLINIC.MAP.APPOINTMENTS', { appointments }),
    ...(rate === null ? [] : [t('VIRTUAL_CLINIC.MAP.CONVERSION', { rate })]),
  ];
  return lines[rotation.value % lines.length];
};

const at = point => ({
  left: `${point.x * scale.value}px`,
  top: `${point.y * scale.value}px`,
});
const worldSize = computed(() => ({
  width: `${WORLD.width * scale.value}px`,
  height: `${WORLD.height * scale.value}px`,
}));

const render = () => draw?.(characters.value, tick.value);
watch([characters, tick], render);

const ensureSheet = async path => {
  if (!sprites || sprites[path] || loadingSheets.has(path)) return;
  loadingSheets.add(path);
  const loaded = await loadSprites([path], file =>
    VirtualClinicAPI.getAsset(file)
  );
  Object.assign(sprites, loaded);
};

watch(
  () => people.value.map(person => person.userId).join(),
  ids => {
    const list = ids ? ids.split(',').map(Number) : [];
    list.forEach(id => ensureSheet(sheetForUser(id)));
    emit('peopleOnMap', list);
  }
);

// Keeps the avatar in sight when the map is zoomed in.
const FOLLOW_MARGIN = 96;
const follow = () => {
  const box = viewport.value;
  if (!mine.value?.moving || !box) return;
  const feet = feetOf(mine.value);
  const left = feet.x * scale.value - box.scrollLeft;
  const top = feet.y * scale.value - box.scrollTop;
  if (left < FOLLOW_MARGIN) box.scrollLeft -= FOLLOW_MARGIN - left;
  if (left > box.clientWidth - FOLLOW_MARGIN) {
    box.scrollLeft += left - (box.clientWidth - FOLLOW_MARGIN);
  }
  if (top < FOLLOW_MARGIN) box.scrollTop -= FOLLOW_MARGIN - top;
  if (top > box.clientHeight - FOLLOW_MARGIN) {
    box.scrollTop += top - (box.clientHeight - FOLLOW_MARGIN);
  }
};

const animate = now => {
  animationFrame = requestAnimationFrame(animate);
  const seconds =
    lastFrame === null ? 0 : Math.min(0.1, (now - lastFrame) / 1000);
  lastFrame = now;
  if (behavior) {
    behavior.update(now);
    positions.value = Object.fromEntries(
      Object.entries(behavior.state).map(([persona, place]) => [
        persona,
        { ...place },
      ])
    );
  }
  if (avatar) {
    avatar.update(seconds);
    mine.value = { ...avatar.state };
    if (avatar.state.moving) hasWalked.value = true;
    presence.send(avatar.state);
    follow();
  }
  presence.step(seconds);
  tick.value = Math.floor(now / FRAME_MS);
};

const startAvatar = async () => {
  if (!props.me) return;
  await ensureSheet(sheetForUser(props.me.id));
  avatar = createAvatar({
    ...ENTRANCE,
    canStand: place => isFree(grid, feetOf(place)),
  });
  mine.value = { ...avatar.state };
  presence.connect({
    userId: props.me.id,
    accountId: props.me.accountId,
    pubsubToken: props.me.pubsubToken,
    position: () => avatar.state,
  });
};

const walkTowards = point => {
  if (!avatar) return;
  const path = findPath(grid, cellOf(feetOf(avatar.state)), cellOf(point));
  if (!path) return;
  avatar.walkTo(
    corners(path)
      .slice(1)
      .map(cell => frameAt(centerOf(cell)))
  );
};

// Typing in the chat must not walk the avatar around.
const typing = target =>
  target?.closest?.('input, textarea, select, [contenteditable="true"]');

const onKeyDown = event => {
  if (!avatar || typing(event.target)) return;
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.key.toLowerCase() === 'e' && nearMember.value) {
    event.preventDefault();
    emit('selectMember', nearMember.value.persona);
    return;
  }
  if (avatar.press(event.key)) event.preventDefault();
};
const onKeyUp = event => avatar?.release(event.key);
const onBlur = () => avatar?.releaseAll();

// The map fills the area by default; the user can zoom in and out from
// there (wheel or the +/- control), like in Gather.
const fit = () => {
  const width = viewport.value?.clientWidth || WORLD.width;
  const height = viewport.value?.clientHeight || WORLD.height;
  fitScale.value = Math.min(width / WORLD.width, height / WORLD.height);
  if (!userZoomed.value) scale.value = fitScale.value;
};

// Keeps the point under the cursor (or the center) in place while zooming.
const zoomTo = (next, anchor) => {
  const target = Math.min(MAX_SCALE, Math.max(minScale.value, next));
  const box = viewport.value;
  const rect = box.getBoundingClientRect();
  const point = anchor || {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
  const worldX = (box.scrollLeft + point.x - rect.left) / scale.value;
  const worldY = (box.scrollTop + point.y - rect.top) / scale.value;
  userZoomed.value = true;
  scale.value = target;
  requestAnimationFrame(() => {
    box.scrollLeft = worldX * target - (point.x - rect.left);
    box.scrollTop = worldY * target - (point.y - rect.top);
  });
};
const zoom = factor => zoomTo(scale.value * factor);
const onWheel = event => {
  zoomTo(scale.value * (event.deltaY < 0 ? 1.1 : 1 / 1.1), {
    x: event.clientX,
    y: event.clientY,
  });
};
const resetZoom = () => {
  userZoomed.value = false;
  scale.value = fitScale.value;
};

// Drag the map around when it is bigger than the screen; a drag is not a
// click on the floor.
let drag = null;
let dragged = false;
const startDrag = event => {
  dragged = false;
  drag = {
    x: event.clientX,
    y: event.clientY,
    left: viewport.value.scrollLeft,
    top: viewport.value.scrollTop,
  };
};
const moveDrag = event => {
  if (!drag) return;
  const dx = event.clientX - drag.x;
  const dy = event.clientY - drag.y;
  if (Math.hypot(dx, dy) > 4) dragged = true;
  viewport.value.scrollLeft = drag.left - dx;
  viewport.value.scrollTop = drag.top - dy;
};

// Clicking a teammate opens the chat; clicking the floor walks there.
const onClick = event => {
  if (dragged) return;
  const rect = canvas.value.getBoundingClientRect();
  const point = {
    x: (event.clientX - rect.left) / scale.value,
    y: (event.clientY - rect.top) / scale.value,
  };
  const persona = hitTest(point.x, point.y, characters.value);
  if (persona) {
    if (chatEnabled.value) emit('selectMember', persona);
    return;
  }
  walkTowards(point);
};
const endDrag = () => {
  drag = null;
};

onMounted(async () => {
  fit();
  resizeObserver = new ResizeObserver(fit);
  resizeObserver.observe(viewport.value);
  try {
    sprites = await loadSprites(SPRITE_PATHS, path =>
      VirtualClinicAPI.getAsset(path)
    );
    grid = buildCollision(
      Object.fromEntries(
        ITEMS.map(({ sprite }) => [
          sprite,
          { width: sprites[sprite].width, height: sprites[sprite].height },
        ])
      )
    );
    draw = createRenderer(canvas.value, sprites);
    render();
    await startAvatar();
    animationFrame = requestAnimationFrame(animate);
    rotateTimer = setInterval(() => {
      rotation.value += 1;
    }, ROTATE_MS);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
});

onBeforeUnmount(() => {
  cancelAnimationFrame(animationFrame);
  clearInterval(rotateTimer);
  resizeObserver?.disconnect();
  window.removeEventListener('keydown', onKeyDown);
  window.removeEventListener('keyup', onKeyUp);
  window.removeEventListener('blur', onBlur);
});
</script>

<template>
  <div class="relative flex-1 min-w-0 overflow-hidden bg-n-alpha-1">
    <div
      class="absolute z-10 flex flex-col overflow-hidden text-white shadow-lg bottom-4 right-4 rounded-xl bg-n-slate-12/90"
    >
      <button
        type="button"
        class="grid size-10 place-items-center hover:bg-white/10 disabled:opacity-40"
        :title="t('VIRTUAL_CLINIC.MAP.ZOOM_IN')"
        :disabled="scale >= MAX_SCALE"
        @click="zoom(1.25)"
      >
        <Icon icon="i-lucide-plus" class="size-5" />
      </button>
      <button
        type="button"
        class="grid size-10 place-items-center hover:bg-white/10"
        :title="t('VIRTUAL_CLINIC.MAP.ZOOM_FIT')"
        @click="resetZoom"
      >
        <Icon icon="i-lucide-scan" class="size-4" />
      </button>
      <button
        type="button"
        class="grid size-10 place-items-center hover:bg-white/10 disabled:opacity-40"
        :title="t('VIRTUAL_CLINIC.MAP.ZOOM_OUT')"
        :disabled="scale <= minScale"
        @click="zoom(0.8)"
      >
        <Icon icon="i-lucide-minus" class="size-5" />
      </button>
    </div>
    <div
      ref="viewport"
      class="flex w-full h-full overflow-auto cursor-grab active:cursor-grabbing"
      @wheel.prevent="onWheel"
      @mousedown="startDrag"
      @mousemove="moveDrag"
      @mouseup="endDrag"
      @mouseleave="endDrag"
    >
      <div class="relative m-auto shrink-0" :style="worldSize">
        <canvas
          ref="canvas"
          :width="WORLD.width"
          :height="WORLD.height"
          class="block w-full h-full [image-rendering:pixelated]"
          @click="onClick"
        />
        <template v-if="!loading && !failed">
          <span
            v-for="room in ROOMS"
            :key="room.key"
            class="absolute px-2 py-0.5 text-xs font-semibold text-white rounded-md pointer-events-none bg-n-slate-12/80"
            :class="{ '-translate-x-full': room.alignRight }"
            :style="at(room)"
          >
            {{ t(`VIRTUAL_CLINIC.MAP.ROOMS.${room.key}`) }}
          </span>
          <div
            v-for="member in members"
            :key="member.persona"
            class="absolute flex flex-col items-center gap-1 -translate-x-1/2 -translate-y-full pointer-events-none"
            :style="at(overHead(member.persona))"
          >
            <span
              v-if="bubble(member.persona)"
              class="px-2 py-1 text-xs font-medium bg-white rounded-lg shadow-md whitespace-nowrap text-n-slate-12"
            >
              {{ bubble(member.persona) }}
            </span>
            <button
              type="button"
              class="px-2 py-0.5 text-xs font-semibold text-white rounded-full shadow whitespace-nowrap pointer-events-auto"
              :class="[
                member.persona === 'secretary' ? 'bg-n-blue-9' : 'bg-n-iris-9',
                chatEnabled ? '' : 'cursor-default',
                isOffDuty(member.persona, status) ? 'opacity-50' : '',
              ]"
              @click="chatEnabled && emit('selectMember', member.persona)"
            >
              {{ member.name }} ·
              {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
            </button>
          </div>
          <span
            v-for="person in people"
            :key="`person-${person.userId}`"
            class="absolute px-2 py-0.5 text-xs font-semibold text-white rounded-full shadow pointer-events-none whitespace-nowrap -translate-x-1/2 -translate-y-full"
            :class="person.self ? 'bg-n-brand' : 'bg-n-slate-12/80'"
            :style="at({ x: person.x + 16, y: person.y + 18 })"
          >
            {{ person.name }}
          </span>
        </template>
      </div>
    </div>
    <div
      v-if="!loading && !failed && mine"
      class="absolute z-10 flex flex-col items-center gap-2 -translate-x-1/2 bottom-4 left-1/2"
    >
      <button
        v-if="nearMember"
        type="button"
        class="px-3 py-1.5 text-sm font-medium text-white rounded-full shadow-lg bg-n-slate-12/90 hover:bg-n-slate-12"
        @click="emit('selectMember', nearMember.persona)"
      >
        {{ t('VIRTUAL_CLINIC.MAP.TALK_TO', { name: nearMember.name }) }}
      </button>
      <span
        v-else-if="!hasWalked"
        class="px-3 py-1 text-xs rounded-full pointer-events-none text-white/90 bg-n-slate-12/70"
      >
        {{ t('VIRTUAL_CLINIC.MAP.MOVE_HINT') }}
      </span>
    </div>
    <div
      v-if="loading || failed"
      class="absolute inset-0 grid place-items-center text-sm text-n-slate-11"
    >
      <Spinner v-if="loading" />
      <span v-else>{{ t('VIRTUAL_CLINIC.MAP.LOAD_ERROR') }}</span>
    </div>
  </div>
</template>

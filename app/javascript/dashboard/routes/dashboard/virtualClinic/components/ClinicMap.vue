<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  DEFAULT_LAYOUT,
  ENTRANCE,
  GARDEN,
  GARDEN_ITEMS,
  SCENE,
  TILE,
  WORLD,
  sheetForUser,
  spritePaths,
} from '../engine/layout';
import { lookSheet } from '../engine/avatar';
import { loadSprites } from '../engine/sprites';
import { createRenderer, hitTest, itemAt } from '../engine/renderer';
import { createTeamBehavior } from '../engine/behavior';
import { planTrip } from '../engine/trips';
import { checkLayout } from '../engine/layoutCheck';
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
import { seatAt, seatsOf, withoutSeats } from '../engine/seats';
import { inSeason } from '../engine/seasons';
import { useClinicPresence } from '../composables/useClinicPresence';
import { faceLines, formatReais, isFaded } from '../teamStatus';

const props = defineProps({
  aiTeam: { type: Object, default: null },
  status: { type: Object, default: null },
  thinking: { type: String, default: '' },
  focused: { type: String, default: '' },
  // The user's own avatar: `{ id, name, accountId, pubsubToken, avatar }`,
  // `avatar` being the look made in the avatar editor (if any).
  me: { type: Object, default: null },
  // The clinic as arranged by the account (or the editor draft).
  layout: { type: Object, default: () => DEFAULT_LAYOUT },
  // The clinic editor (useClinicLayout) while the user edits the clinic.
  editor: { type: Object, default: null },
  // One AI teammate asking another right now: `{ persona, target }`.
  consulting: { type: Object, default: null },
  // Open alerts per teammate: they "raise their hand" (❗).
  alertCounts: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['selectMember', 'peopleOnMap', 'layoutChanged']);

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
// "Fit" frames the clinic only; zooming out shows the garden around it
// (all of it at `sceneScale`) and then the plan view.
const sceneScale = ref(1);
const minScale = computed(() => Math.min(1, sceneScale.value * 0.6));
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
// The avatar walks on its own grid, where seats are free to step on.
let walkGrid = null;
let seats = [];
let avatar = null;
const mine = ref(null);
const presence = useClinicPresence();
const { passive } = presence;
const loadingSheets = new Set();
// The counter keeps people about three tiles from Clara.
const NEAR = 4 * TILE;
// The "how to walk" hint goes away once the user has walked.
const hasWalked = ref(false);

const members = computed(() =>
  props.aiTeam?.visible ? props.aiTeam.members : []
);
// Talking to them needs the clinic's OpenAI key (their "Assistente"); they
// are only faded when every face is off (see teamStatus.js).
const chatEnabled = computed(() => props.aiTeam?.chat_enabled === true);
const secretaryBusy = computed(
  () => (props.status?.secretary?.active_conversations || 0) > 0
);

const editing = computed(() => props.editor?.editing === true);

// Where each teammate is now (they take little walks, see engine/trips.js).
const placeOf = persona => {
  const spot = props.layout.team[persona];
  return positions.value[persona] || { x: spot.x, y: spot.y };
};

// The name the clinic gave a teammate (the editor draft while editing).
const nameOf = member => props.layout.team[member.persona]?.name || member.name;

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
      faded: isFaded(member.persona, props.status, props.aiTeam),
    };
  })
);

const mySheet = computed(() =>
  props.me?.avatar ? lookSheet(props.me.avatar) : sheetForUser(props.me?.id)
);

const people = computed(() => {
  if (editing.value) return [];
  const list = Object.entries(presence.others.value).map(([id, place]) => ({
    ...place,
    userId: Number(id),
    sheet: place.avatar ? lookSheet(place.avatar) : sheetForUser(Number(id)),
  }));
  if (mine.value && props.me && !passive.value) {
    list.push({
      ...mine.value,
      userId: props.me.id,
      name: props.me.name,
      sheet: mySheet.value,
      self: true,
    });
  }
  return list;
});

const characters = computed(() => [...team.value, ...people.value]);

// The AI teammate within four tiles of the avatar: "Conversar com a Clara (E)".
const nearMember = computed(() => {
  if (!mine.value || !chatEnabled.value || editing.value) return null;
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

// Nobody leaves while the user talks to them or when faded.
const canLeave = persona =>
  persona !== props.focused &&
  persona !== props.thinking &&
  !isFaded(persona, props.status, props.aiTeam);

// The team walks around unless the clinic is being edited.
const restartBehavior = () => {
  const personas = members.value.map(member => member.persona);
  const { layout } = props;
  behavior =
    personas.length && grid && !editing.value
      ? createTeamBehavior({
          personas,
          layout,
          canLeave,
          plan: trip => planTrip(trip, { layout, grid }),
        })
      : null;
  positions.value = {};
};
watch(
  () => members.value.map(member => member.persona).join(),
  restartBehavior
);

// The month numbers over the teammate's head, one at a time (agents don't
// get the manager's).
const monthLine = persona => {
  if (persona === 'marketing' && props.status?.marketing) {
    const { active_campaigns: campaigns, cost_per_appointment: cost } =
      props.status.marketing;
    const ads = [t('VIRTUAL_CLINIC.MAP.CAMPAIGNS', { campaigns })];
    if (cost !== null) {
      ads.push(
        t('VIRTUAL_CLINIC.MAP.COST_PER_APPOINTMENT', {
          cost: formatReais(cost),
        })
      );
    }
    return [{ key: 'month', text: ads[rotation.value % ads.length] }];
  }
  if (persona !== 'manager' || !props.status?.manager) return [];
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
  return [{ key: 'month', text: lines[rotation.value % lines.length] }];
};

// What each teammate is doing, over their head (hidden while away): the
// month numbers and one line per face, with its on/off dot.
const bubble = persona => {
  if (editing.value) return [];
  if (props.consulting?.persona === persona) {
    const teammate = members.value.find(
      m => m.persona === props.consulting.target
    );
    const name = teammate ? nameOf(teammate) : '';
    return [{ key: 'asking', text: t('VIRTUAL_CLINIC.MAP.ASKING', { name }) }];
  }
  if (props.thinking === persona) {
    return [{ key: 'thinking', text: t('VIRTUAL_CLINIC.MAP.THINKING') }];
  }
  if (placeOf(persona).away) return [];
  return [
    ...monthLine(persona),
    ...faceLines(persona, props.status, props.aiTeam, t),
  ];
};

// World coordinates (the clinic's) to pixels on the scene, garden included.
const at = point => ({
  left: `${(point.x - SCENE.x) * scale.value}px`,
  top: `${(point.y - SCENE.y) * scale.value}px`,
});
const worldSize = computed(() => ({
  width: `${SCENE.width * scale.value}px`,
  height: `${SCENE.height * scale.value}px`,
}));

// The box around what the editor has selected.
const selectedBox = computed(() => {
  const target = editing.value && props.editor.selected;
  if (!target || !sprites) return null;
  if (target.kind === 'team') {
    const seat = props.layout.team[target.persona];
    return { x: seat.x, y: seat.y, width: 32, height: 64 };
  }
  const item = props.layout.items[target.index];
  const image = item && sprites[item.sprite];
  return image
    ? { x: item.x, y: item.y, width: image.width, height: image.height }
    : null;
});

// Zoomed well out: the plan view, with people as photo bubbles (Gather).
const overview = computed(
  () => !editing.value && scale.value < sceneScale.value * 0.9
);
const agents = useMapGetter('agents/getAgents');
const photoOf = userId =>
  (agents.value || []).find(agent => agent.id === userId)?.thumbnail || '';

const render = () =>
  draw?.(characters.value, tick.value, selectedBox.value, overview.value);
watch([characters, tick, selectedBox, overview], render);

const sizesOf = items =>
  Object.fromEntries(
    items
      .filter(({ sprite }) => sprites[sprite])
      .map(({ sprite }) => [
        sprite,
        { width: sprites[sprite].width, height: sprites[sprite].height },
      ])
  );

// Draws the clinic again after the layout changed (or the art arrived):
// loads any new art, then the walk grid, the background and the team.
const rebuild = async () => {
  const { layout } = props;
  const missing = spritePaths(layout).filter(path => !sprites[path]);
  if (missing.length) {
    Object.assign(
      sprites,
      await loadSprites(missing, path => VirtualClinicAPI.getAsset(path))
    );
  }
  // The clinic changed while the art loaded (the saved layout arrived):
  // build the latest one instead.
  if (layout !== props.layout) {
    await rebuild();
    return;
  }
  // Decoration out of season stays saved but off the map (the editor shows
  // it, to move or remove it).
  const items = editing.value
    ? layout.items
    : layout.items.filter(item => inSeason(item.sprite, props.aiTeam?.seasons));
  const sizes = sizesOf([...GARDEN_ITEMS, ...items]);
  grid = buildCollision(sizes, items);
  seats = seatsOf([...GARDEN_ITEMS, ...items], sizes, layout.team);
  walkGrid = buildCollision(
    sizes,
    withoutSeats(items, seats),
    withoutSeats(GARDEN_ITEMS, seats)
  );
  draw = createRenderer(canvas.value, sprites, { ...layout, items });
  restartBehavior();
  render();
};
watch(
  () => props.layout,
  () => sprites && rebuild()
);
watch(editing, () => (sprites ? rebuild() : restartBehavior()));
watch(
  () => props.aiTeam?.seasons,
  () => sprites && rebuild()
);

// The manager walks to the secretary's desk while she asks her something.
watch(
  () => props.consulting,
  consulting => {
    if (consulting) {
      behavior?.consult(
        consulting.persona,
        consulting.target,
        performance.now()
      );
    } else {
      behavior?.release(performance.now());
    }
  }
);

// Editor check before saving, as a message (empty when all is fine).
const check = layout => {
  const result = checkLayout(layout, sizesOf(layout.items));
  if (!result) return '';
  if (result.problem === 'entrance') {
    return t('VIRTUAL_CLINIC.EDITOR.ERRORS.ENTRANCE');
  }
  const member = members.value.find(m => m.persona === result.persona);
  return t('VIRTUAL_CLINIC.EDITOR.ERRORS.UNREACHABLE', {
    name: layout.team[result.persona].name || member?.name || result.persona,
  });
};
defineExpose({ check });

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
  ids => emit('peopleOnMap', ids ? ids.split(',').map(Number) : [])
);
// Loads the look of whoever shows up (or changes their avatar).
watch(
  () => people.value.map(person => person.sheet).join('|'),
  () => people.value.forEach(person => ensureSheet(person.sheet))
);
// A new look of my own: everybody else sees it right away.
watch(mySheet, () => avatar && presence.send(mine.value, true));

// Keeps the avatar in sight when the map is zoomed in.
const FOLLOW_MARGIN = 96;
const follow = () => {
  const box = viewport.value;
  if (!mine.value?.moving || !box) return;
  const feet = feetOf(mine.value);
  const left = (feet.x - SCENE.x) * scale.value - box.scrollLeft;
  const top = (feet.y - SCENE.y) * scale.value - box.scrollTop;
  if (left < FOLLOW_MARGIN) box.scrollLeft -= FOLLOW_MARGIN - left;
  if (left > box.clientWidth - FOLLOW_MARGIN) {
    box.scrollLeft += left - (box.clientWidth - FOLLOW_MARGIN);
  }
  if (top < FOLLOW_MARGIN) box.scrollTop -= FOLLOW_MARGIN - top;
  if (top > box.clientHeight - FOLLOW_MARGIN) {
    box.scrollTop += top - (box.clientHeight - FOLLOW_MARGIN);
  }
};

// Where the avatar was left, so it is back there after a reload or a trip
// to another page (in this browser).
const spotKey = () =>
  `virtual-clinic-spot:${props.me.accountId}:${props.me.id}`;
const savedSpot = () => {
  try {
    return JSON.parse(localStorage.getItem(spotKey()));
  } catch {
    return null;
  }
};
const saveSpot = () => {
  if (!avatar || !props.me) return;
  try {
    localStorage.setItem(
      spotKey(),
      JSON.stringify({
        x: Math.round(avatar.state.x),
        y: Math.round(avatar.state.y),
        direction: avatar.state.direction,
      })
    );
  } catch {
    // No storage (private window): the avatar starts at the door.
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
  // In another tab the clinic is open too and that one is the person.
  if (avatar && !passive.value) {
    const wasMoving = avatar.state.moving;
    avatar.update(seconds);
    // Standing still on a chair: sit on it, facing where it faces.
    const seat = !avatar.state.moving && seatAt(seats, avatar.state);
    mine.value = seat
      ? {
          ...avatar.state,
          ...seat.frame,
          direction: seat.face,
          sitting: true,
          compact: seat.compact,
        }
      : { ...avatar.state };
    if (avatar.state.moving) hasWalked.value = true;
    if (wasMoving && !avatar.state.moving) saveSpot();
    presence.send(mine.value);
    follow();
  }
  presence.step(seconds);
  tick.value = Math.floor(now / FRAME_MS);
};

const startAvatar = async () => {
  if (!props.me) return;
  await ensureSheet(mySheet.value);
  const spot = savedSpot();
  const canStand = place => isFree(walkGrid, feetOf(place));
  avatar = createAvatar({
    ...(spot && canStand(spot) ? spot : ENTRANCE),
    canStand,
  });
  if (spot?.direction) avatar.state.direction = spot.direction;
  mine.value = { ...avatar.state };
  presence.connect({
    userId: props.me.id,
    accountId: props.me.accountId,
    pubsubToken: props.me.pubsubToken,
    position: () => avatar.state,
    look: () => props.me?.avatar || null,
    layoutChanged: () => emit('layoutChanged'),
  });
};

const walkTowards = point => {
  if (!avatar) return;
  const path = findPath(walkGrid, cellOf(feetOf(avatar.state)), cellOf(point));
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

// Editor keys: Del removes the selected piece, R turns it around, Esc
// drops the selection.
const onEditorKey = event => {
  const key = event.key.toLowerCase();
  if (key === 'delete' || key === 'backspace') props.editor.removeSelected();
  else if (key === 'r') props.editor.flipSelected();
  else if (key === 'escape') props.editor.select(null);
  else return;
  event.preventDefault();
};

const onKeyDown = event => {
  if (typing(event.target)) return;
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (editing.value) {
    onEditorKey(event);
    return;
  }
  if (!avatar) return;
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
// Scrolls so the clinic sits in the middle of the view.
const centerClinic = () =>
  requestAnimationFrame(() => {
    const box = viewport.value;
    if (!box) return;
    box.scrollLeft =
      GARDEN * scale.value - (box.clientWidth - WORLD.width * scale.value) / 2;
    box.scrollTop =
      GARDEN * scale.value -
      (box.clientHeight - WORLD.height * scale.value) / 2;
  });
const fit = () => {
  const width = viewport.value?.clientWidth || WORLD.width;
  const height = viewport.value?.clientHeight || WORLD.height;
  fitScale.value = Math.min(width / WORLD.width, height / WORLD.height);
  sceneScale.value = Math.min(width / SCENE.width, height / SCENE.height);
  if (!userZoomed.value) {
    scale.value = fitScale.value;
    centerClinic();
  }
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
  centerClinic();
};

const toWorld = event => {
  const rect = canvas.value.getBoundingClientRect();
  return {
    x: (event.clientX - rect.left) / scale.value + SCENE.x,
    y: (event.clientY - rect.top) / scale.value + SCENE.y,
  };
};

// In the editor, pressing on a teammate or a piece selects it and drags it
// around; pressing on the floor drops the selection.
const pickForEditing = event => {
  const point = toWorld(event);
  const persona = hitTest(point.x, point.y, team.value);
  const index = persona
    ? -1
    : itemAt(point.x, point.y, props.layout.items, sprites);
  if (!persona && index === -1) {
    props.editor.select(null);
    return null;
  }
  const target = persona ? { kind: 'team', persona } : { kind: 'item', index };
  props.editor.select(target);
  const origin = persona
    ? props.layout.team[persona]
    : props.layout.items[index];
  const image = persona ? null : sprites[origin.sprite];
  return {
    x: event.clientX,
    y: event.clientY,
    origin: { x: origin.x, y: origin.y },
    size: image
      ? { width: image.width, height: image.height }
      : { width: 32, height: 64 },
  };
};

// Drag the map around when it is bigger than the screen; a drag is not a
// click on the floor.
let drag = null;
let moving = null;
let dragged = false;
const startDrag = event => {
  dragged = false;
  if (editing.value && event.target === canvas.value) {
    moving = pickForEditing(event);
    if (moving) return;
  }
  drag = {
    x: event.clientX,
    y: event.clientY,
    left: viewport.value.scrollLeft,
    top: viewport.value.scrollTop,
  };
};
const moveDrag = event => {
  if (moving) {
    props.editor.moveSelected(
      moving.origin.x + (event.clientX - moving.x) / scale.value,
      moving.origin.y + (event.clientY - moving.y) / scale.value,
      moving.size
    );
    return;
  }
  if (!drag) return;
  const dx = event.clientX - drag.x;
  const dy = event.clientY - drag.y;
  if (Math.hypot(dx, dy) > 4) dragged = true;
  viewport.value.scrollLeft = drag.left - dx;
  viewport.value.scrollTop = drag.top - dy;
};

// Clicking a teammate opens the chat; clicking the floor walks there.
const onClick = event => {
  if (dragged || editing.value) return;
  const point = toWorld(event);
  const persona = hitTest(point.x, point.y, characters.value);
  if (persona) {
    // The manager also opens without the chat: she has the person's news.
    if (chatEnabled.value || persona === 'manager') {
      emit('selectMember', persona);
    }
    return;
  }
  walkTowards(point);
};
const endDrag = () => {
  drag = null;
  moving = null;
};

onMounted(async () => {
  fit();
  resizeObserver = new ResizeObserver(fit);
  resizeObserver.observe(viewport.value);
  try {
    sprites = {};
    await rebuild();
    await startAvatar();
    animationFrame = requestAnimationFrame(animate);
    rotateTimer = setInterval(() => {
      rotation.value += 1;
    }, ROTATE_MS);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);
    window.addEventListener('pagehide', saveSpot);
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
});

onBeforeUnmount(() => {
  saveSpot();
  cancelAnimationFrame(animationFrame);
  clearInterval(rotateTimer);
  resizeObserver?.disconnect();
  window.removeEventListener('keydown', onKeyDown);
  window.removeEventListener('keyup', onKeyUp);
  window.removeEventListener('blur', onBlur);
  window.removeEventListener('pagehide', saveSpot);
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
          :width="SCENE.width"
          :height="SCENE.height"
          class="block w-full h-full [image-rendering:pixelated]"
          @click="onClick"
        />
        <template v-if="!loading && !failed">
          <span
            v-for="room in layout.rooms"
            :key="room.key"
            class="absolute px-2 py-0.5 text-xs font-semibold text-white rounded-md pointer-events-none whitespace-nowrap bg-n-slate-12/80"
            :class="{ '-translate-x-full': room.alignRight }"
            :style="at(room)"
          >
            {{ room.name || t(`VIRTUAL_CLINIC.MAP.ROOMS.${room.key}`) }}
          </span>
          <div
            v-for="member in members"
            :key="member.persona"
            class="absolute flex flex-col items-center gap-1 -translate-x-1/2 -translate-y-full pointer-events-none"
            :style="at(overHead(member.persona))"
          >
            <span
              v-if="bubble(member.persona).length && !overview"
              class="flex flex-col gap-0.5 px-2 py-1 text-xs font-medium bg-white rounded-lg shadow-md whitespace-nowrap text-n-slate-12"
            >
              <span
                v-for="line in bubble(member.persona)"
                :key="line.key"
                class="flex items-center gap-1.5"
              >
                <span
                  v-if="line.on !== undefined"
                  class="rounded-full size-1.5 shrink-0"
                  :class="line.on ? 'bg-n-teal-9' : 'bg-n-slate-8'"
                />
                {{ line.text }}
              </span>
            </span>
            <button
              type="button"
              class="px-2 py-0.5 text-xs font-semibold text-white rounded-full shadow whitespace-nowrap pointer-events-auto bg-n-iris-9"
              :class="[
                chatEnabled ? '' : 'cursor-default',
                isFaded(member.persona, status, aiTeam) ? 'opacity-50' : '',
              ]"
              @click="
                chatEnabled && !editing && emit('selectMember', member.persona)
              "
            >
              <span
                v-if="alertCounts[member.persona] && !editing"
                class="inline-grid mr-1 font-bold rounded-full size-4 place-items-center bg-n-ruby-9 animate-pulse"
              >
                {{ t('VIRTUAL_CLINIC.MAP.RAISED_HAND') }}
              </span>
              {{ nameOf(member) }} ·
              {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
            </button>
          </div>
          <span
            v-for="person in people"
            v-show="!overview"
            :key="`person-${person.userId}`"
            class="absolute px-2 py-0.5 text-xs font-semibold rounded-full shadow pointer-events-none whitespace-nowrap -translate-x-1/2 -translate-y-full"
            :class="
              person.self ? 'bg-n-blue-9 text-white' : 'bg-n-slate-9 text-white'
            "
            :style="at({ x: person.x + 16, y: person.y + 18 })"
          >
            {{ person.name }}
          </span>
          <template v-if="overview">
            <div
              v-for="person in people"
              :key="`bubble-${person.userId}`"
              class="absolute flex flex-col items-center gap-1 -translate-x-1/2 -translate-y-full pointer-events-none"
              :style="at({ x: person.x + 16, y: person.y + 60 })"
            >
              <span
                class="px-2 py-0.5 text-xs font-semibold rounded-full shadow whitespace-nowrap"
                :class="
                  person.self
                    ? 'bg-n-blue-9 text-white'
                    : 'bg-n-slate-9 text-white'
                "
              >
                {{ person.name }}
              </span>
              <span
                class="rounded-full shadow-md ring-2"
                :class="person.self ? 'ring-n-blue-9' : 'ring-n-slate-6'"
              >
                <Avatar
                  :name="person.name"
                  :src="photoOf(person.userId)"
                  :size="32"
                  rounded-full
                />
              </span>
            </div>
            <div
              v-for="member in members"
              :key="`bubble-${member.persona}`"
              class="absolute grid text-sm font-semibold text-white -translate-x-1/2 -translate-y-full rounded-full shadow-md pointer-events-none size-8 place-items-center bg-n-iris-9"
              :style="
                at({
                  x: placeOf(member.persona).x + 16,
                  y: placeOf(member.persona).y + 60,
                })
              "
            >
              {{ nameOf(member).charAt(0) }}
            </div>
          </template>
        </template>
      </div>
    </div>
    <div
      v-if="!loading && !failed && mine && !editing"
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
      v-if="passive && !editing"
      class="absolute z-20 flex items-center gap-3 px-4 py-2 text-sm -translate-x-1/2 rounded-xl shadow-lg top-4 left-1/2 bg-n-solid-1 text-n-slate-12"
    >
      <Icon icon="i-lucide-copy" class="size-4 text-n-slate-11" />
      {{ t('VIRTUAL_CLINIC.MAP.OTHER_TAB') }}
      <button
        type="button"
        class="px-2.5 py-1 text-xs font-medium text-white rounded-lg bg-n-brand"
        @click="presence.takeOver()"
      >
        {{ t('VIRTUAL_CLINIC.MAP.USE_HERE') }}
      </button>
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

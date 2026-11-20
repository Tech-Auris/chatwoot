import { computed, ref } from 'vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import { WORLD, applySaved, toSaved } from '../engine/layout';

const SNAP = 4;
const snap = value => Math.round(value / SNAP) * SNAP;
const clone = value => JSON.parse(JSON.stringify(value));

// The clinic as this account arranged it, and the editor on top of it:
// while editing, `layout` is the draft; Save sends it, Discard drops it and
// Restore goes back to the default clinic.
export function useClinicLayout() {
  const saved = ref(null);
  const draft = ref(null);
  const selected = ref(null); // { kind: 'item', index } | { kind: 'team', persona }
  const error = ref('');
  const saving = ref(false);

  const editing = computed(() => draft.value !== null);
  const layout = computed(() => draft.value || applySaved(saved.value));

  const load = async () => {
    const { data } = await VirtualClinicAPI.getLayout();
    saved.value = data.layout;
  };

  const start = () => {
    draft.value = clone(applySaved(saved.value));
    selected.value = null;
    error.value = '';
  };

  const discard = () => {
    draft.value = null;
    selected.value = null;
    error.value = '';
  };

  const update = change => {
    const next = clone(draft.value);
    change(next);
    draft.value = next;
  };

  // `problem` is the editor check done on the map (who can't be reached);
  // `fallback` the message when the API gives no reason.
  const save = async (problem, fallback = '') => {
    if (problem) {
      error.value = problem;
      return false;
    }
    saving.value = true;
    try {
      const { data } = await VirtualClinicAPI.saveLayout(toSaved(draft.value));
      saved.value = data.layout;
      discard();
      return true;
    } catch (failure) {
      error.value = failure.response?.data?.message || fallback;
      return false;
    } finally {
      saving.value = false;
    }
  };

  // Changes one teammate right away, outside the editor (the team panel).
  const saveTeam = async (persona, patch) => {
    const next = clone(applySaved(saved.value));
    Object.assign(next.team[persona], patch);
    const { data } = await VirtualClinicAPI.saveLayout(toSaved(next));
    saved.value = data.layout;
  };

  const restore = async () => {
    await VirtualClinicAPI.resetLayout();
    saved.value = null;
    discard();
  };

  const select = target => {
    selected.value = target;
  };

  // Moves the selected piece or teammate to a frame/sprite position.
  const moveSelected = (x, y, size) => {
    const target = selected.value;
    if (!target) return;
    const place = {
      x: Math.min(Math.max(0, snap(x)), WORLD.width - size.width),
      y: Math.min(Math.max(0, snap(y)), WORLD.height - size.height),
    };
    update(next => {
      if (target.kind === 'team') {
        Object.assign(next.team[target.persona], place);
        return;
      }
      const item = next.items[target.index];
      if (item.sortY !== undefined) item.sortY += place.y - item.y;
      Object.assign(item, place);
    });
  };

  const removeSelected = () => {
    const target = selected.value;
    if (target?.kind !== 'item') return;
    update(next => next.items.splice(target.index, 1));
    selected.value = null;
  };

  const flipSelected = () => {
    const target = selected.value;
    if (target?.kind !== 'item') return;
    update(next => {
      const item = next.items[target.index];
      item.flip = !item.flip;
    });
  };

  const addItem = (sprite, x, y) => {
    update(next => next.items.push({ sprite, x: snap(x), y: snap(y) }));
    selected.value = { kind: 'item', index: draft.value.items.length - 1 };
  };

  const setBlock = (kind, index, block) =>
    update(next => {
      next[kind][index].block = block;
    });

  const renameRoom = (key, name) =>
    update(next => {
      next.rooms.find(room => room.key === key).name = name.trim() || undefined;
    });

  const setTeam = (persona, patch) =>
    update(next => {
      Object.assign(next.team[persona], patch);
    });

  return {
    saved,
    layout,
    editing,
    selected,
    error,
    saving,
    load,
    start,
    discard,
    save,
    saveTeam,
    restore,
    select,
    moveSelected,
    removeSelected,
    flipSelected,
    addItem,
    setBlock,
    renameRoom,
    setTeam,
  };
}

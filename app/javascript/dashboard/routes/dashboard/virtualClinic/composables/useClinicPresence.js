import { onBeforeUnmount, ref } from 'vue';
import { createConsumer } from '@rails/actioncable';

const SEND_MS = 200; // at most 5 positions per second
const HEARTBEAT_MS = 5000;
const GONE_MS = 15000;
const SPEED = 160; // others glide to their last known spot, world px/s

// Everyone else walking on the map of this account (VirtualClinicChannel).
// Each open map is a session: with the clinic open in two tabs, the one
// opened (or taken back) last is the person; the other goes `passive`
// (stops sending) until `takeOver`, and the others ignore the older one.
// `others` maps user id → `{ name, x, y, direction, moving, sitting, avatar }`, x/y being
// where they are drawn now; positions arrive a few times per second and
// are smoothed in `step`.
export function useClinicPresence() {
  const others = ref({});
  const passive = ref(false);
  const session = Math.random().toString(36).slice(2) + Date.now().toString(36);
  let since = Date.now();
  let consumer = null;
  let subscription = null;
  let me = null;
  let lastSent = { at: 0, key: '' };
  let onLayout = () => {};
  const targets = {};

  const send = (position, force = false) => {
    if (!subscription || passive.value) return;
    const now = Date.now();
    const key = `${Math.round(position.x)},${Math.round(position.y)},${position.direction},${position.moving},${position.sitting}`;
    const changed = key !== lastSent.key;
    if (!force && now - lastSent.at < (changed ? SEND_MS : HEARTBEAT_MS)) {
      return;
    }
    lastSent = { at: now, key };
    subscription.perform('move', {
      x: Math.round(position.x),
      y: Math.round(position.y),
      direction: position.direction,
      moving: position.moving,
      sitting: position.sitting === true,
      compact: position.compact === true,
      avatar: me.look(),
      since,
    });
  };

  const received = ({ event, data }) => {
    // Someone saved the clinic in the editor: draw it again.
    if (event === 'virtual_clinic.layout') {
      onLayout();
      return;
    }
    if (event !== 'virtual_clinic.presence') return;
    if (data.user_id === me?.userId) {
      // The clinic opened in another tab after this one: that one is me now.
      if (data.session !== session && !data.left && data.since > since) {
        passive.value = true;
      }
      return;
    }
    const current = targets[data.user_id];
    // A tab of theirs older than the one already seen: ignore it.
    if (current && data.session !== current.session) {
      if (data.left || (data.since || 0) < (current.since || 0)) return;
    }
    if (data.left) {
      delete targets[data.user_id];
      const rest = { ...others.value };
      delete rest[data.user_id];
      others.value = rest;
      return;
    }
    const known = data.user_id in targets;
    targets[data.user_id] = { ...data, seenAt: Date.now() };
    if (!known) {
      // Someone just arrived: show them where they are and say hello back,
      // so they see us without waiting for the next heartbeat.
      others.value = { ...others.value, [data.user_id]: { ...data } };
      if (me?.position) send(me.position(), true);
    }
  };

  const connect = ({
    userId,
    accountId,
    pubsubToken,
    position,
    look = () => null,
    layoutChanged,
  }) => {
    me = { userId, position, look };
    onLayout = layoutChanged || onLayout;
    const { websocketURL = '' } = window.chatwootConfig || {};
    consumer = createConsumer(
      websocketURL ? `${websocketURL}/cable` : undefined
    );
    subscription = consumer.subscriptions.create(
      {
        channel: 'VirtualClinicChannel',
        pubsub_token: pubsubToken,
        account_id: accountId,
        user_id: userId,
        session,
      },
      { received, connected: () => send(position(), true) }
    );
  };

  // Moves everyone a bit closer to their last known spot and drops whoever
  // went quiet (closed the laptop without leaving the page).
  const step = seconds => {
    const now = Date.now();
    const next = {};
    Object.entries(targets).forEach(([id, target]) => {
      if (now - target.seenAt > GONE_MS) {
        delete targets[id];
        return;
      }
      const shown = others.value[id] || target;
      const dx = target.x - shown.x;
      const dy = target.y - shown.y;
      const distance = Math.hypot(dx, dy);
      const reach = SPEED * seconds;
      const ratio = distance <= reach || distance > 200 ? 1 : reach / distance;
      next[id] = {
        ...target,
        x: shown.x + dx * ratio,
        y: shown.y + dy * ratio,
        moving: target.moving || ratio < 1,
      };
    });
    others.value = next;
  };

  // Use the clinic in this tab again: the other one goes quiet.
  const takeOver = () => {
    since = Date.now();
    passive.value = false;
    if (me?.position) send(me.position(), true);
  };

  const disconnect = () => {
    consumer?.disconnect();
    consumer = null;
    subscription = null;
  };

  onBeforeUnmount(disconnect);
  return { others, passive, connect, send, step, takeOver };
}

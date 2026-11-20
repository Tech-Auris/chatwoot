import { onBeforeUnmount, ref } from 'vue';
import { createConsumer } from '@rails/actioncable';

const SEND_MS = 200; // at most 5 positions per second
const HEARTBEAT_MS = 5000;
const GONE_MS = 15000;
const SPEED = 160; // others glide to their last known spot, world px/s

// Everyone else walking on the map of this account (VirtualClinicChannel).
// `others` maps user id → `{ name, x, y, direction, moving, avatar }`, x/y being
// where they are drawn now; positions arrive a few times per second and
// are smoothed in `step`.
export function useClinicPresence() {
  const others = ref({});
  let consumer = null;
  let subscription = null;
  let me = null;
  let lastSent = { at: 0, key: '' };
  let onLayout = () => {};
  const targets = {};

  const send = (position, force = false) => {
    if (!subscription) return;
    const now = Date.now();
    const key = `${Math.round(position.x)},${Math.round(position.y)},${position.direction},${position.moving}`;
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
      avatar: me.look(),
    });
  };

  const received = ({ event, data }) => {
    // Someone saved the clinic in the editor: draw it again.
    if (event === 'virtual_clinic.layout') {
      onLayout();
      return;
    }
    if (event !== 'virtual_clinic.presence' || data.user_id === me?.userId) {
      return;
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

  const disconnect = () => {
    consumer?.disconnect();
    consumer = null;
    subscription = null;
  };

  onBeforeUnmount(disconnect);
  return { others, connect, send, step };
}

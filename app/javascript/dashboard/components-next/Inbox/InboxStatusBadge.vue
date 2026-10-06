<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  qualityKey,
  qualityStyle,
  accountStatusDot,
} from 'dashboard/helper/whatsappHealth';

// Official API numbers: account status + quality, refreshed from Meta every
// 30 minutes. Baileys / Z-API numbers: whether the phone is connected.
// Any other inbox renders nothing.
const props = defineProps({
  inbox: {
    type: Object,
    default: null,
  },
  // "Status: Aprovada - Qualidade: Média" where the badge stands on its own
  // (the "Via:" picker); the inbox grid already names the column.
  labeled: {
    type: Boolean,
    default: false,
  },
});

const { t, te } = useI18n();

const translateValue = (group, value) => {
  const key = `INBOX_MGMT.ACCOUNT_HEALTH.VALUES.${group}.${value}`;
  return te(key) ? t(key) : value;
};

const CONNECTION_DOTS = {
  open: 'bg-n-teal-9',
  connecting: 'bg-n-amber-9',
  close: 'bg-n-ruby-9',
};

const isWhatsapp = computed(
  () => props.inbox?.channel_type === 'Channel::Whatsapp'
);
const connection = computed(() => props.inbox?.provider_connection || {});

const badges = computed(() => {
  if (!isWhatsapp.value) return [];

  if (['baileys', 'zapi'].includes(props.inbox.provider)) {
    const state = CONNECTION_DOTS[connection.value.connection]
      ? connection.value.connection
      : 'close';
    return [
      {
        key: 'connection',
        prefix: 'STATUS',
        label: t(`INBOX_MGMT.CONNECTION_STATUS.${state.toUpperCase()}`),
        badge: 'bg-n-alpha-2 text-n-slate-12',
        dot: CONNECTION_DOTS[state],
      },
    ];
  }

  const health = connection.value.health;
  if (!health) return [];

  const quality = qualityKey(health);
  const list = [];
  if (health.account_review_status) {
    list.push({
      key: 'account',
      prefix: 'STATUS',
      label: translateValue(
        'ACCOUNT_REVIEW_STATUSES',
        health.account_review_status
      ),
      badge: 'bg-n-alpha-2 text-n-slate-12',
      dot: accountStatusDot(health.account_review_status),
    });
  }
  list.push({
    key: 'quality',
    prefix: 'QUALITY',
    label: translateValue('QUALITY_RATINGS', quality),
    ...qualityStyle(quality),
  });
  return list;
});
</script>

<template>
  <span v-if="badges.length" class="inline-flex items-center gap-1 shrink-0">
    <template v-for="(item, index) in badges" :key="item.key">
      <span v-if="labeled && index > 0" class="text-xs text-n-slate-11">-</span>
      <span
        class="inline-flex items-center gap-1.5 px-1.5 h-5 text-xs rounded-md whitespace-nowrap"
        :class="item.badge"
      >
        <span class="size-1.5 rounded-full" :class="item.dot" />
        <template v-if="labeled">
          {{ $t(`INBOX_MGMT.CONNECTION_STATUS.LABELS.${item.prefix}`) }}
        </template>
        {{ item.label }}
      </span>
    </template>
  </span>
</template>

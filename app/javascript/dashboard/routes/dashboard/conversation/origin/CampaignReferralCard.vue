<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

// Reads what `Whatsapp::IncomingMessageBaseService#attach_campaign_referral_to_conversation`
// persists on `Conversation.additional_attributes.campaign_referral` — the same
// normalized shape the message-bubble ReferralCard consumes, so a future move to
// display it inside the bubble too can pull from the same payload without a
// second serialization contract.
const props = defineProps({
  referral: {
    type: Object,
    default: () => null,
    // Webhook-derived payload — guard the string fields the template renders so a
    // malformed referral warns in dev instead of silently rendering a broken card.
    validator: value =>
      value == null ||
      (typeof value === 'object' &&
        ['title', 'body', 'source_url', 'thumbnail_url'].every(
          key => value[key] == null || typeof value[key] === 'string'
        )),
  },
});

const { t } = useI18n();

// Restricting both href and img src to http(s) keeps a webhook that carries an
// unsafe scheme (e.g. javascript:) out of the link and stops arbitrary URLs
// from triggering the agent's browser through the image.
const toHttpUrl = url => {
  if (!url) return null;
  try {
    return ['http:', 'https:'].includes(new URL(url).protocol) ? url : null;
  } catch {
    return null;
  }
};

const adUrl = computed(() => toHttpUrl(props.referral?.source_url));
const imageUrl = computed(() => toHttpUrl(props.referral?.thumbnail_url));

const hasImageError = ref(false);
const showImage = computed(
  () => Boolean(imageUrl.value) && !hasImageError.value
);

const capturedAt = computed(() => {
  const value = props.referral?.captured_at;
  if (!value) return null;
  const ms = value * 1000;
  const date = new Date(ms);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
});
</script>

<template>
  <div class="mt-2">
    <template v-if="referral">
      <div class="flex items-center gap-2 mb-2 text-xs text-n-slate-11">
        <Icon icon="i-lucide-megaphone" class="size-3.5" />
        <span class="font-medium">
          {{ t('CAMPAIGN_REFERRAL_CARD.TITLE') }}
        </span>
      </div>
      <component
        :is="adUrl ? 'a' : 'div'"
        :href="adUrl || undefined"
        :target="adUrl ? '_blank' : undefined"
        rel="noopener noreferrer"
        class="flex flex-col gap-2 p-3 overflow-hidden no-underline rounded-lg bg-n-alpha-black1"
        :class="adUrl ? 'cursor-pointer hover:bg-n-alpha-black2' : ''"
      >
        <img
          v-if="showImage"
          :src="imageUrl || undefined"
          :alt="referral.title || ''"
          class="object-cover w-full rounded max-h-32 skip-context-menu"
          @error="hasImageError = true"
        />
        <div class="min-w-0">
          <p
            v-if="referral.title"
            class="mb-0 text-sm font-medium line-clamp-2 text-n-slate-12"
          >
            {{ referral.title }}
          </p>
          <p
            v-if="referral.body"
            class="mb-0 mt-1 text-xs text-n-slate-11 line-clamp-2"
          >
            {{ referral.body }}
          </p>
        </div>
        <div
          v-if="capturedAt"
          class="text-2xs text-n-slate-10 font-mono tracking-tight"
        >
          {{ capturedAt }}
        </div>
        <div
          v-if="adUrl"
          class="flex items-center gap-1 text-xs font-medium text-n-slate-12"
        >
          <Icon icon="i-lucide-external-link" class="size-3 shrink-0" />
          <span>{{ t('CAMPAIGN_REFERRAL_CARD.VIEW_AD') }}</span>
        </div>
      </component>
    </template>
  </div>
</template>

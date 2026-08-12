<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import StatusBadge from './StatusBadge.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import MetaTemplatesAPI from 'dashboard/api/metaTemplates';

const props = defineProps({
  template: { type: Object, default: null },
  inboxId: { type: [Number, String], default: null },
  open: { type: Boolean, default: false },
  deleting: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'delete', 'edit']);

const { t } = useI18n();

// Delete surface follows the backend policy: manager + admin only.
// Agents see the full detail but no destructive action.
const currentRole = useMapGetter('getCurrentRole');
const canDelete = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

// Meta only accepts template edits when the template is APPROVED. Any
// other status (PENDING, REJECTED, PAUSED, DISABLED, IN_APPEAL, FLAGGED)
// makes the /message_templates edit endpoint fail with #100 "Invalid
// parameter — status of this template cannot be changed". Rather than
// letting the operator fill the form and only find out at submit,
// disable the Edit button and explain why in a tooltip.
const canEdit = computed(() => {
  if (!canDelete.value) return false;
  return (props.template?.status || '').toUpperCase() === 'APPROVED';
});

const editDisabledReason = computed(() => {
  if (canEdit.value) return null;
  return t('META_TEMPLATES.DETAIL.EDIT_DISABLED_REASON', {
    status: (props.template?.status || 'UNKNOWN').toUpperCase(),
  });
});

// Meta templates use a `components` array with typed entries. Pull each
// section into its own computed so the template markup stays flat.
// Header, footer and buttons are optional; body is mandatory in Meta's
// contract and therefore assumed present here.
const componentByType = type => {
  return (props.template?.components || []).find(
    c => (c?.type || '').toUpperCase() === type
  );
};

const header = computed(() => componentByType('HEADER'));
const body = computed(() => componentByType('BODY'));
const footer = computed(() => componentByType('FOOTER'));
const buttonsComponent = computed(() => componentByType('BUTTONS'));
const buttons = computed(() => buttonsComponent.value?.buttons || []);

const bodyText = computed(() => body.value?.text || '');
const footerText = computed(() => footer.value?.text || '');

// Header can be TEXT / IMAGE / VIDEO / DOCUMENT / LOCATION. For TEXT we
// show the string with placeholder highlighting via the body renderer;
// for media types we just label the format — Fatia 5 will add rich
// preview.
const headerFormat = computed(() =>
  (header.value?.format || 'TEXT').toUpperCase()
);
const headerText = computed(() => header.value?.text || '');

const rejectedReason = computed(() => props.template?.rejected_reason);

// Usage funnel: fetched from the backend when the drawer opens on a
// template. Keeps its own state so switching the period doesn't clobber
// the (heavier) template data already in the drawer.
const PERIOD_OPTIONS = ['7d', '30d', '90d'];
const period = ref('30d');
const analytics = ref(null);
const analyticsLoading = ref(false);
const analyticsError = ref(false);

const funnelSteps = computed(() => {
  const f = analytics.value?.funnel;
  if (!f) return [];
  const pct = (num, base) => (base > 0 ? Math.round((num / base) * 100) : null);
  return [
    { key: 'SENT', value: f.sent, ratio: null, tone: 'neutral' },
    {
      key: 'ACCEPTED',
      value: f.accepted_by_meta,
      ratio: pct(f.accepted_by_meta, f.sent),
      tone: f.failed_sync > 0 && f.sent > 0 ? 'warn' : 'neutral',
    },
    {
      key: 'DELIVERED',
      value: f.delivered,
      ratio: pct(f.delivered, f.accepted_by_meta),
      tone: 'neutral',
    },
    {
      key: 'READ',
      value: f.read,
      ratio: pct(f.read, f.delivered),
      tone: 'neutral',
    },
    {
      key: 'FAILED_AFTER',
      value: f.failed_after_accept,
      ratio: pct(f.failed_after_accept, f.accepted_by_meta),
      tone: f.failed_after_accept > 0 ? 'warn' : 'neutral',
    },
  ];
});

const fetchAnalytics = async () => {
  if (!props.template?.id || !props.inboxId) {
    analytics.value = null;
    return;
  }
  analyticsLoading.value = true;
  analyticsError.value = false;
  try {
    const { data } = await MetaTemplatesAPI.analytics({
      inboxId: props.inboxId,
      templateId: props.template.id,
      period: period.value,
    });
    analytics.value = data;
  } catch (_err) {
    analytics.value = null;
    analyticsError.value = true;
  } finally {
    analyticsLoading.value = false;
  }
};

// Refetch whenever the target template changes (opening a different row)
// or the period changes. Only fires when the drawer is open — no point
// hitting the API for a template the operator can't see.
watch(
  [() => props.template?.id, period, () => props.open],
  ([id, , isOpen]) => {
    if (isOpen && id) fetchAnalytics();
  },
  { immediate: true }
);
</script>

<template>
  <transition name="slide">
    <aside
      v-if="open && template"
      class="fixed top-0 right-0 h-full w-full max-w-xl bg-n-solid-1 border-l border-n-weak shadow-2xl z-40 flex flex-col"
    >
      <header
        class="flex items-start justify-between p-5 border-b border-n-weak gap-3"
      >
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-n-slate-12 truncate">
            {{ template.name }}
          </h2>
          <p class="text-xs text-n-slate-11 mt-0.5">
            {{ template.category }}
            {{ t('META_TEMPLATES.DETAIL.SUBTITLE_SEPARATOR') }}
            {{ template.language }}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <StatusBadge :status="template.status" />
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12 text-sm leading-none px-2 py-1 rounded hover:bg-n-alpha-1"
            @click="emit('close')"
          >
            {{ t('META_TEMPLATES.DETAIL.CLOSE') }}
          </button>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto p-5 space-y-4">
        <div
          v-if="rejectedReason"
          class="px-3 py-2 rounded-md bg-n-ruby-3 text-n-ruby-12 text-sm"
        >
          <strong>{{
            t('META_TEMPLATES.DETAIL.REJECTED_REASON_LABEL')
          }}</strong>
          {{ rejectedReason }}
        </div>

        <section v-if="header" class="border border-n-weak rounded-lg p-3">
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{
              t('META_TEMPLATES.DETAIL.HEADER_FORMAT_LABEL', {
                label: t('META_TEMPLATES.DETAIL.HEADER'),
                format: headerFormat,
              })
            }}
          </div>
          <p
            v-if="headerFormat === 'TEXT'"
            class="text-sm text-n-slate-12 whitespace-pre-wrap"
          >
            {{ headerText || '—' }}
          </p>
          <p v-else class="text-xs text-n-slate-11">
            {{
              t('META_TEMPLATES.DETAIL.MEDIA_HEADER_NOTE', {
                format: headerFormat,
              })
            }}
          </p>
        </section>

        <section class="border border-n-weak rounded-lg p-3">
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{ t('META_TEMPLATES.DETAIL.BODY') }}
          </div>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
            {{ bodyText || '—' }}
          </p>
        </section>

        <section v-if="footerText" class="border border-n-weak rounded-lg p-3">
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{ t('META_TEMPLATES.DETAIL.FOOTER') }}
          </div>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
            {{ footerText }}
          </p>
        </section>

        <section
          v-if="buttons.length"
          class="border border-n-weak rounded-lg p-3"
        >
          <div class="text-xxs uppercase tracking-wide text-n-slate-11 mb-2">
            {{ t('META_TEMPLATES.DETAIL.BUTTONS') }}
          </div>
          <ul class="grid gap-2">
            <li
              v-for="(button, idx) in buttons"
              :key="idx"
              class="px-3 py-1.5 bg-n-alpha-1 rounded-md text-sm text-n-slate-12"
            >
              <span
                class="text-xxs uppercase tracking-wide text-n-slate-11 mr-2"
              >
                {{ button.type }}
              </span>
              {{ button.text }}
              <span v-if="button.url" class="text-xs text-n-slate-11 ml-2">
                {{ t('META_TEMPLATES.DETAIL.URL_PREFIX') }} {{ button.url }}
              </span>
              <span
                v-if="button.phone_number"
                class="text-xs text-n-slate-11 ml-2"
              >
                {{ t('META_TEMPLATES.DETAIL.PHONE_PREFIX') }}
                {{ button.phone_number }}
              </span>
            </li>
          </ul>
        </section>

        <section class="border border-n-weak rounded-lg p-3">
          <div class="flex items-center justify-between mb-3">
            <div class="text-xxs uppercase tracking-wide text-n-slate-11">
              {{ t('META_TEMPLATES.ANALYTICS.TITLE') }}
            </div>
            <div class="flex items-center gap-1">
              <button
                v-for="option in PERIOD_OPTIONS"
                :key="option"
                type="button"
                class="px-2 py-1 text-xs rounded-md"
                :class="
                  period === option
                    ? 'bg-n-brand text-white'
                    : 'text-n-slate-11 hover:bg-n-alpha-1'
                "
                @click="period = option"
              >
                {{ t(`META_TEMPLATES.ANALYTICS.PERIODS.${option}`) }}
              </button>
            </div>
          </div>

          <div
            v-if="analyticsLoading"
            class="flex items-center justify-center py-6"
          >
            <Spinner class="!w-5 !h-5 !p-0" />
          </div>
          <div v-else-if="analyticsError" class="text-sm text-n-ruby-11 py-3">
            {{ t('META_TEMPLATES.ANALYTICS.ERROR') }}
          </div>
          <div
            v-else-if="!analytics || analytics.funnel.sent === 0"
            class="text-sm text-n-slate-11 py-3"
          >
            {{ t('META_TEMPLATES.ANALYTICS.EMPTY') }}
          </div>
          <ul v-else class="grid grid-cols-2 gap-2">
            <li
              v-for="step in funnelSteps"
              :key="step.key"
              class="px-3 py-2 rounded-md bg-n-alpha-1"
            >
              <div class="text-xxs uppercase tracking-wide text-n-slate-11">
                {{ t(`META_TEMPLATES.ANALYTICS.STEPS.${step.key}`) }}
              </div>
              <div class="flex items-baseline gap-2">
                <span
                  class="text-lg font-semibold"
                  :class="
                    step.tone === 'warn' ? 'text-n-amber-11' : 'text-n-slate-12'
                  "
                >
                  {{ step.value }}
                </span>
                <span
                  v-if="step.ratio !== null"
                  class="text-xs text-n-slate-11"
                >
                  {{ `${step.ratio}%` }}
                </span>
              </div>
            </li>
          </ul>
        </section>
      </div>

      <footer
        v-if="canDelete"
        class="border-t border-n-weak p-4 flex flex-col items-end gap-2"
      >
        <span
          v-if="editDisabledReason"
          class="text-xxs text-n-slate-11 max-w-full text-right"
        >
          {{ editDisabledReason }}
        </span>
        <div class="flex items-center gap-2">
          <Button
            faded
            slate
            sm
            :disabled="!canEdit"
            :label="t('META_TEMPLATES.DETAIL.EDIT')"
            @click="emit('edit', template)"
          />
          <Button
            faded
            ruby
            sm
            :disabled="deleting"
            :label="t('META_TEMPLATES.DETAIL.DELETE')"
            @click="emit('delete', template)"
          />
        </div>
      </footer>
    </aside>
  </transition>
</template>

<style scoped>
.slide-enter-active,
.slide-leave-active {
  transition: transform 0.2s ease;
}
.slide-enter-from,
.slide-leave-to {
  transform: translateX(100%);
}
</style>

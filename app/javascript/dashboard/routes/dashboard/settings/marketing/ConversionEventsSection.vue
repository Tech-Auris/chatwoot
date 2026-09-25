<script setup>
// Inline CRUD for ConversionEvent — no separate popup / route so the operator
// can see the whole configuration on one screen. Each row can be expanded
// to edit; the "new" row uses the same form shape.
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import MarketingIntegrationsAPI from 'dashboard/api/marketingIntegrations';

// `automation_action` foi removido do dropdown enquanto a operação não
// usa esse gatilho. A i18n do label e o resolver do `triggerLabel` ficam
// intactos pra render correto de eventos antigos que porventura tenham
// sido salvos com esse tipo antes.
const TRIGGER_TYPES = ['funnel_stage_reached', 'label_added'];

const { t } = useI18n();
const store = useStore();
const events = useMapGetter('conversionEvents/getConversionEvents');
const uiFlags = useMapGetter('conversionEvents/getUIFlags');
// Namespaces were `funnel/getStages` and never resolved — the module is
// registered as `funnelStages` with a `getFunnelStages` getter, so the
// dropdown stayed empty and the CTA "Etapa do funil" was unusable.
// Labels never had a fetch here at all and the "Etiqueta aplicada"
// gatilho left the operator typing the label name by hand.
const funnelStages = useMapGetter('funnelStages/getFunnelStages');
const labels = useMapGetter('labels/getLabels');
const marketingIntegrations = useMapGetter(
  'marketingIntegrations/getMarketingIntegrations'
);

// A conversion event dispatches to exactly one provider per row on the
// form — Meta CAPI or Google Ads — so the operator picks the destination
// first and the form reveals the relevant event-name field. On edit the
// destination is derived from whichever field is populated; a rare row
// that carries both defaults to Meta (Meta is the default destination
// for new records too).
const DESTINATIONS = ['meta', 'google'];

const metaIntegration = computed(() =>
  (marketingIntegrations.value || []).find(i => i.provider === 'meta_capi')
);
const metaEventSuggestions = ref([]);

const editing = ref(null);
const draft = reactive({
  id: null,
  name: '',
  trigger_type: 'funnel_stage_reached',
  trigger_config: {},
  destination: 'meta',
  meta_event_name: '',
  google_event_name: '',
  enabled: true,
});

const resetDraft = () => {
  Object.assign(draft, {
    id: null,
    name: '',
    trigger_type: 'funnel_stage_reached',
    trigger_config: {},
    destination: 'meta',
    meta_event_name: '',
    google_event_name: '',
    enabled: true,
  });
};

const startCreate = () => {
  resetDraft();
  editing.value = 'new';
};

// Both `meta_event_name` populated → default to Meta.
// Only `google_event_name` → Google.
// Neither / just `meta_event_name` → Meta.
const destinationFromRow = event => {
  if (event.google_event_name && !event.meta_event_name) return 'google';
  return 'meta';
};

const startEdit = event => {
  Object.assign(draft, {
    ...event,
    trigger_config: { ...(event.trigger_config || {}) },
    destination: destinationFromRow(event),
  });
  editing.value = event.id;
};

const cancelEdit = () => {
  editing.value = null;
  resetDraft();
};

const triggerConfigForBackend = () => {
  const cfg = draft.trigger_config || {};
  if (draft.trigger_type === 'funnel_stage_reached') {
    return {
      funnel_stage_id: cfg.funnel_stage_id ? Number(cfg.funnel_stage_id) : null,
    };
  }
  if (draft.trigger_type === 'label_added') return { label: cfg.label || '' };
  return {};
};

const currentEventName = computed(() =>
  draft.destination === 'meta' ? draft.meta_event_name : draft.google_event_name
);

const canSave = computed(() => {
  if (!draft.name.trim()) return false;
  if (!(currentEventName.value || '').trim()) return false;
  if (
    draft.trigger_type === 'funnel_stage_reached' &&
    !draft.trigger_config.funnel_stage_id
  )
    return false;
  if (
    draft.trigger_type === 'label_added' &&
    !(draft.trigger_config.label || '').trim()
  )
    return false;
  return true;
});

const save = async () => {
  // Persist only the field paired with the chosen destination; the other
  // is cleared so switching destinations doesn't leave an orphan value
  // that the dispatcher would still act on.
  const payload = {
    name: draft.name.trim(),
    trigger_type: draft.trigger_type,
    trigger_config: triggerConfigForBackend(),
    meta_event_name:
      draft.destination === 'meta' ? draft.meta_event_name || null : null,
    google_event_name:
      draft.destination === 'google' ? draft.google_event_name || null : null,
    enabled: draft.enabled,
  };
  try {
    if (draft.id) {
      await store.dispatch('conversionEvents/update', {
        id: draft.id,
        ...payload,
      });
    } else {
      await store.dispatch('conversionEvents/create', payload);
    }
    useAlert(t('MARKETING_ANALYTICS.EVENTS.SAVE_SUCCESS'));
    cancelEdit();
  } catch (error) {
    useAlert(error?.message || t('MARKETING_ANALYTICS.EVENTS.SAVE_ERROR'));
  }
};

const remove = async event => {
  if (
    !window.confirm(
      t('MARKETING_ANALYTICS.EVENTS.DELETE_CONFIRM', { name: event.name })
    )
  )
    return;
  try {
    await store.dispatch('conversionEvents/delete', event.id);
    useAlert(t('MARKETING_ANALYTICS.EVENTS.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('MARKETING_ANALYTICS.EVENTS.SAVE_ERROR'));
  }
};

const triggerLabel = event => {
  const cfg = event.trigger_config || {};
  if (event.trigger_type === 'funnel_stage_reached') {
    const stage = (funnelStages.value || []).find(
      s => s.id === Number(cfg.funnel_stage_id)
    );
    return `${t('MARKETING_ANALYTICS.EVENTS.TRIGGER_TYPES.FUNNEL_STAGE_REACHED')}: ${stage?.name || cfg.funnel_stage_id}`;
  }
  if (event.trigger_type === 'label_added') {
    return `${t('MARKETING_ANALYTICS.EVENTS.TRIGGER_TYPES.LABEL_ADDED')}: ${cfg.label}`;
  }
  return t('MARKETING_ANALYTICS.EVENTS.TRIGGER_TYPES.AUTOMATION_ACTION');
};

const loadMetaEventSuggestions = async () => {
  if (!metaIntegration.value?.id) {
    metaEventSuggestions.value = [];
    return;
  }
  try {
    const { data } = await MarketingIntegrationsAPI.fetchPixelEvents(
      metaIntegration.value.id
    );
    metaEventSuggestions.value = [
      ...(data.standard || []),
      ...(data.custom || []),
    ];
  } catch {
    // A broken Meta call (missing credentials, expired token, network
    // hiccup) must not lock the operator out — the datalist becomes
    // empty and the field stays a free-text input.
    metaEventSuggestions.value = [];
  }
};

onMounted(async () => {
  store.dispatch('conversionEvents/get');
  // Both stores are idempotent (their own `get` short-circuits when
  // already fetched), so dispatching every mount is cheap.
  store.dispatch('funnelStages/get');
  store.dispatch('labels/get');
  // `IntegrationsSection` on the same screen fires this too — the store
  // shares the single fetch. Re-fires here so opening the page directly
  // on the Conversion Events section (or on a variant that hides the
  // integrations section) still populates the Meta combobox.
  await store.dispatch('marketingIntegrations/get');
  loadMetaEventSuggestions();
});

watch(
  () => draft.trigger_type,
  () => {
    draft.trigger_config = {};
  }
);

// Refresh the suggestions if the Meta integration gets connected /
// re-credentialed while the operator is on the screen (e.g., a manager
// pastes the Meta token in the section above and comes down to fill an
// event — the combobox has to catch up).
watch(
  () => metaIntegration.value?.id,
  id => {
    if (id) loadMetaEventSuggestions();
  }
);
</script>

<template>
  <section class="rounded-lg border border-n-strong bg-n-solid-1 p-6">
    <header class="flex items-start justify-between gap-4 mb-4">
      <div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('MARKETING_ANALYTICS.EVENTS.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('MARKETING_ANALYTICS.EVENTS.DESCRIPTION') }}
        </p>
      </div>
      <button
        v-if="editing !== 'new'"
        type="button"
        class="rounded bg-n-brand hover:bg-n-brand/90 text-white px-3 py-1.5 text-sm font-medium"
        @click="startCreate"
      >
        {{ t('MARKETING_ANALYTICS.EVENTS.NEW') }}
      </button>
    </header>

    <div class="flex flex-col gap-2">
      <!-- Inline form (new / edit) -->
      <form
        v-if="editing !== null"
        class="rounded-md border border-n-brand-solid/40 bg-n-alpha-1 p-4 grid grid-cols-1 md:grid-cols-2 gap-3 text-sm"
        @submit.prevent="save"
      >
        <label class="flex flex-col gap-1">
          <span class="text-n-slate-11">
            {{ t('MARKETING_ANALYTICS.EVENTS.NAME') }}
            <span class="text-n-ruby-10">*</span>
          </span>
          <input
            v-model="draft.name"
            type="text"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-n-slate-11">{{
            t('MARKETING_ANALYTICS.EVENTS.TRIGGER')
          }}</span>
          <select
            v-model="draft.trigger_type"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          >
            <option v-for="tt in TRIGGER_TYPES" :key="tt" :value="tt">
              {{
                t(
                  `MARKETING_ANALYTICS.EVENTS.TRIGGER_TYPES.${tt.toUpperCase()}`
                )
              }}
            </option>
          </select>
        </label>

        <label
          v-if="draft.trigger_type === 'funnel_stage_reached'"
          class="flex flex-col gap-1"
        >
          <span class="text-n-slate-11">
            {{ t('MARKETING_ANALYTICS.EVENTS.FUNNEL_STAGE') }}
            <span class="text-n-ruby-10">*</span>
          </span>
          <select
            v-model="draft.trigger_config.funnel_stage_id"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          >
            <option :value="null" disabled>—</option>
            <option
              v-for="stage in funnelStages || []"
              :key="stage.id"
              :value="stage.id"
            >
              {{ stage.name }}
            </option>
          </select>
        </label>

        <label
          v-else-if="draft.trigger_type === 'label_added'"
          class="flex flex-col gap-1"
        >
          <span class="text-n-slate-11">
            {{ t('MARKETING_ANALYTICS.EVENTS.LABEL') }}
            <span class="text-n-ruby-10">*</span>
          </span>
          <!-- Picker over the account's existing labels — pareado com o
               que a automação usa como gatilho de "label added". Digitar
               à mão dava falso match silencioso (o backend compara pelo
               `title`; um typo passava despercebido até o operador
               reparar que o Meta CAPI nunca disparava). -->
          <select
            v-model="draft.trigger_config.label"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          >
            <option :value="undefined" disabled>—</option>
            <option
              v-for="label in labels || []"
              :key="label.id"
              :value="label.title"
            >
              {{ label.title }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-n-slate-11">
            {{ t('MARKETING_ANALYTICS.EVENTS.DESTINATION') }}
            <span class="text-n-ruby-10">*</span>
          </span>
          <select
            v-model="draft.destination"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          >
            <option v-for="dst in DESTINATIONS" :key="dst" :value="dst">
              {{
                t(
                  `MARKETING_ANALYTICS.EVENTS.DESTINATIONS.${dst.toUpperCase()}`
                )
              }}
            </option>
          </select>
        </label>

        <!-- Combobox (input + datalist) para o Meta: aceita valores
             livres (o operador pode digitar um Custom Event novo) mas
             sugere Standard Events + eventos que o pixel já recebeu
             nos últimos 30 dias (via `pixel_events` endpoint). -->
        <label v-if="draft.destination === 'meta'" class="flex flex-col gap-1">
          <span class="text-n-slate-11">
            {{ t('MARKETING_ANALYTICS.EVENTS.META_EVENT') }}
            <span class="text-n-ruby-10">*</span>
          </span>
          <input
            v-model="draft.meta_event_name"
            list="meta-event-suggestions"
            type="text"
            :placeholder="
              t('MARKETING_ANALYTICS.EVENTS.META_EVENT_PLACEHOLDER')
            "
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          />
          <datalist id="meta-event-suggestions">
            <option
              v-for="name in metaEventSuggestions"
              :key="name"
              :value="name"
            />
          </datalist>
        </label>

        <label
          v-else-if="draft.destination === 'google'"
          class="flex flex-col gap-1"
        >
          <span class="text-n-slate-11">
            {{ t('MARKETING_ANALYTICS.EVENTS.GOOGLE_EVENT') }}
            <span class="text-n-ruby-10">*</span>
          </span>
          <input
            v-model="draft.google_event_name"
            type="text"
            :placeholder="
              t('MARKETING_ANALYTICS.EVENTS.GOOGLE_EVENT_PLACEHOLDER')
            "
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          />
        </label>

        <label class="col-span-full flex items-center gap-2">
          <input v-model="draft.enabled" type="checkbox" />
          <span class="text-n-slate-11">{{
            t('MARKETING_ANALYTICS.EVENTS.ENABLED')
          }}</span>
        </label>

        <div class="col-span-full flex justify-end gap-2">
          <button
            type="button"
            class="rounded border border-n-strong text-n-slate-12 px-3 py-1.5 text-sm"
            @click="cancelEdit"
          >
            {{ t('MARKETING_ANALYTICS.CANCEL') }}
          </button>
          <button
            type="submit"
            :disabled="!canSave || uiFlags.isCreating || uiFlags.isUpdating"
            class="rounded bg-n-brand hover:bg-n-brand/90 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-50"
          >
            {{ t('MARKETING_ANALYTICS.SAVE') }}
          </button>
        </div>
      </form>

      <!-- List -->
      <div
        v-if="!events.length && editing === null"
        class="text-sm text-n-slate-11 text-center py-8"
      >
        {{ t('MARKETING_ANALYTICS.EVENTS.EMPTY') }}
      </div>

      <div
        v-for="event in events"
        :key="event.id"
        class="rounded-md border border-n-strong p-3 flex items-center justify-between gap-3 text-sm"
      >
        <div class="min-w-0 flex flex-col gap-0.5">
          <div class="flex items-center gap-2">
            <span class="font-medium text-n-slate-12">{{ event.name }}</span>
            <span
              v-if="!event.enabled"
              class="text-[11px] text-n-slate-11 border border-n-strong rounded-full px-2 py-0.5"
            >
              {{ t('MARKETING_ANALYTICS.EVENTS.DISABLED_TAG') }}
            </span>
          </div>
          <span class="text-xs text-n-slate-11 truncate">{{
            triggerLabel(event)
          }}</span>
          <!-- Um evento novo carrega só um destino (Meta ou Google), então
               o `META_LABEL` / `GOOGLE_LABEL` aparece sem prefixo. Linhas
               legadas com os dois campos preenchidos ainda podem existir;
               nesse caso, colocamos um "·" antes do Google só como
               separador visual. -->
          <span class="text-xs text-n-slate-11">
            <template v-if="event.meta_event_name">
              {{ t('MARKETING_ANALYTICS.EVENTS.META_LABEL') }}:
              <code class="text-n-slate-12">{{ event.meta_event_name }}</code>
            </template>
            <template v-if="event.google_event_name">
              <span v-if="event.meta_event_name"> · </span>
              {{ t('MARKETING_ANALYTICS.EVENTS.GOOGLE_LABEL') }}:
              <code class="text-n-slate-12">{{ event.google_event_name }}</code>
            </template>
          </span>
        </div>
        <div class="shrink-0 flex gap-2">
          <button
            type="button"
            class="text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="startEdit(event)"
          >
            {{ t('MARKETING_ANALYTICS.EDIT') }}
          </button>
          <button
            type="button"
            class="text-xs text-n-ruby-10 hover:underline"
            @click="remove(event)"
          >
            {{ t('MARKETING_ANALYTICS.DELETE') }}
          </button>
        </div>
      </div>
    </div>
  </section>
</template>

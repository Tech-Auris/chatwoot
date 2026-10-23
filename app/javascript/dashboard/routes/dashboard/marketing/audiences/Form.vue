<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import AudiencesAPI from 'dashboard/api/audiences';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AudienceConditionRow from './components/AudienceConditionRow.vue';
import { useAudienceFields } from './useAudienceFields';

// Create or edit an audience: name, kind, who enters (every condition), the
// window on when the conversation started and who stays out (any
// condition). The size beside it follows every change.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { fields, optionsFor, operatorsFor, describe, describeWindow } =
  useAudienceFields();

const audienceId = computed(() => route.params.audienceId);
const isEditing = computed(() => !!audienceId.value);

const state = reactive({
  name: '',
  kind: 'dynamic',
  rule: [],
  exclusion: [],
  window: { type: 'all', days: 30, from: '', to: '' },
});
const isLoading = ref(false);
const isSaving = ref(false);
const size = ref(null);
const isCounting = ref(false);

const newCondition = () => ({
  attribute_key: 'labels',
  filter_operator: 'equal_to',
  values: [],
});

const complete = conditions =>
  conditions.filter(c => c.attribute_key && c.values?.length);

// Every rule condition must hold (AND); any exclusion condition removes the
// contact (OR).
const chained = (conditions, operator) =>
  complete(conditions).map((condition, index, list) => ({
    ...condition,
    query_operator: index < list.length - 1 ? operator : null,
  }));

const windowPayload = computed(() => {
  const { type, days, from, to } = state.window;
  if (type === 'last_days') return { type, days: Number(days) };
  if (type === 'range') return { type, from, to };
  return { type: 'all' };
});

const isWindowValid = computed(() => {
  const { type, days, from, to } = state.window;
  if (type === 'last_days') return Number(days) > 0;
  if (type === 'range') return !!from && !!to;
  return true;
});

const payload = computed(() => ({
  name: state.name,
  kind: state.kind,
  rule: chained(state.rule, 'AND'),
  exclusion: chained(state.exclusion, 'OR'),
  window: windowPayload.value,
}));

const canSave = computed(
  () => state.name.trim() && isWindowValid.value && !isSaving.value
);

const refreshSize = useDebounceFn(async () => {
  if (!isWindowValid.value) return;
  isCounting.value = true;
  try {
    const { data } = await AudiencesAPI.preview(payload.value);
    size.value = data.contacts_count;
  } finally {
    isCounting.value = false;
  }
}, 400);

watch(
  () => [state.rule, state.exclusion, state.window],
  () => refreshSize(),
  { deep: true }
);

const windowTypes = computed(() => [
  { value: 'all', label: t('AUDIENCES.FORM.WINDOW_ALL') },
  { value: 'last_days', label: t('AUDIENCES.FORM.WINDOW_LAST_DAYS') },
  { value: 'range', label: t('AUDIENCES.FORM.WINDOW_RANGE') },
]);

const summaryRule = computed(() => complete(state.rule).map(describe));
const summaryExclusion = computed(() =>
  complete(state.exclusion).map(describe)
);

const goBack = () =>
  router.push(
    isEditing.value
      ? {
          name: 'marketing_audiences_show',
          params: { audienceId: audienceId.value },
        }
      : { name: 'marketing_audiences_index' }
  );

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = isEditing.value
      ? await AudiencesAPI.update(audienceId.value, payload.value)
      : await AudiencesAPI.create(payload.value);
    const saved = data.payload;
    if (saved.ignored_conditions?.length) {
      useAlert(
        t('AUDIENCES.FORM.IGNORED', {
          fields: saved.ignored_conditions.join(', '),
        })
      );
    } else {
      useAlert(t('AUDIENCES.FORM.SAVED'));
    }
    router.push({
      name: 'marketing_audiences_show',
      params: { audienceId: saved.id },
    });
  } catch {
    useAlert(t('AUDIENCES.FORM.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  if (!isEditing.value) {
    refreshSize();
    return;
  }
  isLoading.value = true;
  try {
    const { data } = await AudiencesAPI.show(audienceId.value);
    const audience = data.payload;
    Object.assign(state, {
      name: audience.name,
      kind: audience.kind,
      rule: audience.rule || [],
      exclusion: audience.exclusion || [],
      window: { days: 30, from: '', to: '', ...audience.window },
    });
    size.value = audience.contacts_count;
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <button
        type="button"
        class="mb-2 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="goBack"
      >
        {{ t('AUDIENCES.SHOW.BACK') }}
      </button>
      <h1 class="mb-1 text-heading-1 text-n-slate-12">
        {{
          isEditing
            ? t('AUDIENCES.FORM.EDIT_TITLE')
            : t('AUDIENCES.FORM.NEW_TITLE')
        }}
      </h1>
      <p class="mb-6 text-sm text-n-slate-11">
        {{ t('AUDIENCES.FORM.DESCRIPTION') }}
        {{ t('AUDIENCES.FORM.REQUIRED_NOTE') }}
      </p>

      <div v-if="isLoading" class="flex justify-center py-10">
        <Spinner />
      </div>

      <div v-else class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div class="flex flex-col gap-6 lg:col-span-2">
          <div class="flex flex-col gap-2">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('AUDIENCES.FORM.STEP_NAME') }}
            </h2>
            <Input
              v-model="state.name"
              :label="t('AUDIENCES.FORM.NAME_LABEL')"
              :placeholder="t('AUDIENCES.FORM.NAME_PLACEHOLDER')"
              :message="t('AUDIENCES.FORM.NAME_HELP')"
            />
          </div>

          <div v-if="!isEditing" class="flex flex-col gap-2">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('AUDIENCES.FORM.STEP_KIND') }}
            </h2>
            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <RadioCard
                id="dynamic"
                :label="t('AUDIENCES.KIND.DYNAMIC')"
                :description="t('AUDIENCES.FORM.KIND_DYNAMIC_HELP')"
                :is-active="state.kind === 'dynamic'"
                @select="state.kind = 'dynamic'"
              />
              <RadioCard
                id="static"
                :label="t('AUDIENCES.KIND.STATIC')"
                :description="t('AUDIENCES.FORM.KIND_STATIC_HELP')"
                :is-active="state.kind === 'static'"
                @select="state.kind = 'static'"
              />
            </div>
          </div>

          <template v-if="state.kind === 'dynamic' || !isEditing">
            <div class="flex flex-col gap-2">
              <h2 class="text-sm font-medium text-n-slate-12">
                {{ t('AUDIENCES.FORM.STEP_RULE') }}
              </h2>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.FORM.RULE_HELP') }}
              </p>
              <template v-for="(condition, index) in state.rule" :key="index">
                <span v-if="index" class="text-xs text-n-slate-11">
                  {{ t('AUDIENCES.FORM.AND') }}
                </span>
                <AudienceConditionRow
                  v-model="state.rule[index]"
                  :fields="fields"
                  :operators="operatorsFor(condition.attribute_key)"
                  :options="optionsFor(condition.attribute_key)"
                  @remove="state.rule.splice(index, 1)"
                />
              </template>
              <Button
                :label="t('AUDIENCES.FORM.ADD_CONDITION')"
                icon="i-lucide-plus"
                variant="faded"
                color="slate"
                size="sm"
                class="self-start"
                @click="state.rule.push(newCondition())"
              />
            </div>

            <div class="flex flex-col gap-2">
              <h2 class="text-sm font-medium text-n-slate-12">
                {{ t('AUDIENCES.FORM.STEP_WINDOW') }}
              </h2>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.FORM.WINDOW_HELP') }}
              </p>
              <div class="flex flex-wrap gap-2">
                <Button
                  v-for="option in windowTypes"
                  :key="option.value"
                  :label="option.label"
                  size="sm"
                  :variant="
                    state.window.type === option.value ? 'solid' : 'faded'
                  "
                  :color="state.window.type === option.value ? 'blue' : 'slate'"
                  @click="state.window.type = option.value"
                />
              </div>
              <Input
                v-if="state.window.type === 'last_days'"
                v-model="state.window.days"
                type="number"
                min="1"
                :label="t('AUDIENCES.FORM.DAYS_LABEL')"
                class="max-w-[12rem]"
              />
              <div
                v-if="state.window.type === 'range'"
                class="flex flex-wrap gap-3"
              >
                <Input
                  v-model="state.window.from"
                  type="date"
                  :label="t('AUDIENCES.FORM.FROM')"
                />
                <Input
                  v-model="state.window.to"
                  type="date"
                  :label="t('AUDIENCES.FORM.TO')"
                />
              </div>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.FORM.WINDOW_NOTE') }}
              </p>
            </div>

            <div class="flex flex-col gap-2">
              <h2 class="text-sm font-medium text-n-slate-12">
                {{ t('AUDIENCES.FORM.STEP_EXCLUSION') }}
                <span class="text-xs font-normal text-n-slate-11">
                  {{ t('AUDIENCES.FORM.OPTIONAL') }}
                </span>
              </h2>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.FORM.EXCLUSION_HELP') }}
              </p>
              <template
                v-for="(condition, index) in state.exclusion"
                :key="index"
              >
                <span v-if="index" class="text-xs text-n-slate-11">
                  {{ t('AUDIENCES.FORM.OR') }}
                </span>
                <AudienceConditionRow
                  v-model="state.exclusion[index]"
                  :fields="fields"
                  :operators="operatorsFor(condition.attribute_key)"
                  :options="optionsFor(condition.attribute_key)"
                  @remove="state.exclusion.splice(index, 1)"
                />
              </template>
              <Button
                :label="t('AUDIENCES.FORM.ADD_EXCLUSION')"
                icon="i-lucide-plus"
                variant="faded"
                color="slate"
                size="sm"
                class="self-start"
                @click="state.exclusion.push(newCondition())"
              />
            </div>
          </template>

          <div class="flex justify-end gap-2">
            <Button
              :label="t('AUDIENCES.FORM.CANCEL')"
              variant="faded"
              color="slate"
              @click="goBack"
            />
            <Button
              :label="
                isEditing
                  ? t('AUDIENCES.FORM.SAVE')
                  : t('AUDIENCES.FORM.CREATE')
              "
              :is-loading="isSaving"
              :disabled="!canSave"
              @click="save"
            />
          </div>
        </div>

        <aside
          class="flex flex-col self-start gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-2"
        >
          <div>
            <p class="mb-1 text-xs text-n-slate-11">
              {{ t('AUDIENCES.FORM.SIZE_TITLE') }}
            </p>
            <p class="mb-0 text-3xl font-semibold text-n-slate-12">
              {{ size ?? '—' }}
            </p>
            <p class="mb-0 text-xs text-n-slate-11">
              {{
                isCounting
                  ? t('AUDIENCES.FORM.SIZE_UPDATING')
                  : t('AUDIENCES.FORM.SIZE_HINT')
              }}
            </p>
          </div>
          <div class="flex flex-col gap-1">
            <p class="mb-0 text-xs font-medium text-n-slate-12">
              {{ t('AUDIENCES.FORM.SUMMARY') }}
            </p>
            <p
              v-for="line in summaryRule"
              :key="line"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{ line }}
            </p>
            <p v-if="!summaryRule.length" class="mb-0 text-xs text-n-slate-11">
              {{ t('AUDIENCES.RULE.EVERYONE') }}
            </p>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('AUDIENCES.SHOW.WINDOW_TITLE') }}:
              {{ describeWindow(windowPayload) }}
            </p>
            <p
              v-for="line in summaryExclusion"
              :key="line"
              class="mb-0 text-xs text-n-ruby-11"
            >
              {{ t('AUDIENCES.RULE.EXCEPT') }} {{ line }}
            </p>
          </div>
          <p class="mb-0 text-xs text-n-slate-11">
            {{
              state.kind === 'dynamic'
                ? t('AUDIENCES.FORM.AUTO_UPDATE_NOTE')
                : t('AUDIENCES.FORM.STATIC_NOTE')
            }}
            {{ t('AUDIENCES.FORM.LIVE_NOTE') }}
          </p>
        </aside>
      </div>
    </div>
  </section>
</template>

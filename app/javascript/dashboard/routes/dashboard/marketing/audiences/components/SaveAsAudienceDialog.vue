<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AudiencesAPI from 'dashboard/api/audiences';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import { useAudienceFields } from '../useAudienceFields';

// "Salvar como público" from what is on screen: the conversation filter in
// use, or a funnel column with its filters. The rule and the window come
// ready; the user names it and picks dynamic or static. With
// `pickLossReason` (the funnel's lost column) a loss reason can narrow it.
const props = defineProps({
  rule: { type: Array, required: true },
  window: { type: Object, default: () => ({ type: 'all' }) },
  pickLossReason: { type: Boolean, default: false },
});

const { t } = useI18n();
const router = useRouter();
const { describe, describeWindow, optionsFor } = useAudienceFields();

const dialogRef = ref(null);
const isSaving = ref(false);
const size = ref(null);
const state = reactive({ name: '', kind: 'dynamic', lossReasonId: '' });

const lossReasonOptions = computed(() => [
  { value: '', label: t('AUDIENCES.SAVE_AS.ANY_LOSS_REASON') },
  ...optionsFor('loss_reason_id'),
]);

const fullRule = computed(() => {
  const conditions = props.rule.map(condition => ({ ...condition }));
  if (state.lossReasonId) {
    conditions.push({
      attribute_key: 'loss_reason_id',
      filter_operator: 'equal_to',
      values: [Number(state.lossReasonId)],
    });
  }
  return conditions.map((condition, index) => ({
    ...condition,
    query_operator:
      index === conditions.length - 1
        ? null
        : condition.query_operator || 'and',
  }));
});

const countSize = async () => {
  size.value = null;
  const { data } = await AudiencesAPI.preview({
    rule: fullRule.value,
    exclusion: [],
    window: props.window,
  });
  size.value = data.contacts_count;
};

watch(() => state.lossReasonId, countSize);

const open = () => {
  Object.assign(state, { name: '', kind: 'dynamic', lossReasonId: '' });
  dialogRef.value?.open();
  countSize();
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await AudiencesAPI.create({
      name: state.name.trim(),
      kind: state.kind,
      source: 'filter',
      rule: fullRule.value,
      window: props.window,
    });
    const { id, ignored_conditions: ignored = [] } = data.payload;
    useAlert(
      ignored.length
        ? t('AUDIENCES.FORM.IGNORED', { fields: ignored.join(', ') })
        : t('AUDIENCES.FORM.SAVED')
    );
    dialogRef.value?.close();
    router.push({
      name: 'marketing_audiences_show',
      params: { audienceId: id },
    });
  } catch {
    useAlert(t('AUDIENCES.FORM.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AUDIENCES.SAVE_AS.TITLE')"
    width="2xl"
    :description="t('AUDIENCES.SAVE_AS.DESCRIPTION')"
    :confirm-button-label="t('AUDIENCES.FORM.CREATE')"
    :disable-confirm-button="!state.name.trim()"
    :is-loading="isSaving"
    overflow-y-auto
    @confirm="save"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="state.name"
        :label="t('AUDIENCES.FORM.NAME_LABEL')"
        :placeholder="t('AUDIENCES.FORM.NAME_PLACEHOLDER')"
      />
      <div class="grid grid-cols-1 gap-2 p-px sm:grid-cols-2">
        <RadioCard
          id="save-as-dynamic"
          :label="t('AUDIENCES.KIND.DYNAMIC')"
          :description="t('AUDIENCES.FORM.KIND_DYNAMIC_HELP')"
          :is-active="state.kind === 'dynamic'"
          @select="state.kind = 'dynamic'"
        />
        <RadioCard
          id="save-as-static"
          :label="t('AUDIENCES.KIND.STATIC')"
          :description="t('AUDIENCES.FORM.KIND_STATIC_HELP')"
          :is-active="state.kind === 'static'"
          @select="state.kind = 'static'"
        />
      </div>
      <label v-if="pickLossReason" class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-n-slate-12">
          {{ t('AUDIENCES.SAVE_AS.LOSS_REASON') }}
        </span>
        <Select
          v-model="state.lossReasonId"
          :options="lossReasonOptions"
          :placeholder="t('AUDIENCES.SAVE_AS.ANY_LOSS_REASON')"
        />
      </label>
      <div class="flex flex-col gap-1 p-3 text-sm rounded-lg bg-n-alpha-2">
        <span class="font-medium text-n-slate-12">
          {{ t('AUDIENCES.FORM.SUMMARY') }}
        </span>
        <span
          v-for="(condition, index) in fullRule"
          :key="index"
          class="text-n-slate-11"
        >
          {{ describe(condition) }}
        </span>
        <span class="text-n-slate-11">{{ describeWindow(window) }}</span>
        <span class="text-n-slate-12">
          {{
            size === null
              ? t('AUDIENCES.FORM.SIZE_UPDATING')
              : t('AUDIENCES.SAVE_AS.SIZE', { count: size })
          }}
        </span>
      </div>
    </div>
  </Dialog>
</template>

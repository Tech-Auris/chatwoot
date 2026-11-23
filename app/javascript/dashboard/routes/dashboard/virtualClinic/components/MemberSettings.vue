<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// The gear next to an AI teammate: their name in the Clínica virtual (for
// the whole clinic) and, for the manager, which of her summaries this person
// wants (daily, weekly, monthly; any of them) and at what hour of the clinic.
const props = defineProps({
  persona: { type: String, required: true },
  name: { type: String, required: true },
  // The clinic layout (useClinicLayout), where the name is saved.
  editor: { type: Object, required: true },
});
const emit = defineEmits(['close', 'renamed']);

const { t } = useI18n();
const dialog = ref(null);
const isManager = computed(() => props.persona === 'manager');
const PERIODS = ['daily', 'weekly', 'monthly'];
const newName = ref(props.name);
const form = ref({ daily: false, weekly: false, monthly: false, hour: 8 });
const saving = ref(false);

const hours = Array.from({ length: 24 }, (_, hour) => ({
  value: hour,
  label: `${String(hour).padStart(2, '0')}:00`,
}));
const anyChosen = computed(() => PERIODS.some(period => form.value[period]));

const savedMessage = () => {
  if (!isManager.value) return t('VIRTUAL_CLINIC.MEMBER_SETTINGS.SAVED');
  return anyChosen.value
    ? t('VIRTUAL_CLINIC.SUMMARY.SAVED')
    : t('VIRTUAL_CLINIC.SUMMARY.TURNED_OFF');
};

const save = async () => {
  saving.value = true;
  try {
    const name = newName.value.trim();
    if (name !== props.name) {
      // Blank goes back to the default name.
      await props.editor.saveTeam(props.persona, { name: name || undefined });
      emit('renamed');
    }
    if (isManager.value) await VirtualClinicAPI.saveSummary(form.value);
    useAlert(savedMessage());
    dialog.value.close();
  } catch {
    useAlert(t('VIRTUAL_CLINIC.MEMBER_SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

onMounted(async () => {
  dialog.value.open();
  if (!isManager.value) return;
  const { data } = await VirtualClinicAPI.getSummary();
  form.value = { ...form.value, ...data };
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="md"
    :title="t('VIRTUAL_CLINIC.MEMBER_SETTINGS.TITLE', { name })"
    :confirm-button-label="t('VIRTUAL_CLINIC.MEMBER_SETTINGS.SAVE')"
    :is-loading="saving"
    @confirm="save"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4 text-sm text-n-slate-12">
      <label class="flex flex-col gap-1">
        <span class="font-medium">
          {{ t('VIRTUAL_CLINIC.MEMBER_SETTINGS.NAME') }}
        </span>
        <input
          v-model="newName"
          maxlength="40"
          class="!mb-0 px-2 py-1.5 text-sm border rounded-lg border-n-weak bg-n-solid-2"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.MEMBER_SETTINGS.NAME_HINT') }}
        </span>
      </label>

      <template v-if="isManager">
        <p>{{ t('VIRTUAL_CLINIC.SUMMARY.QUESTION', { name }) }}</p>
        <div class="flex flex-col gap-2">
          <label
            v-for="period in PERIODS"
            :key="period"
            class="flex items-start gap-3 p-3 border rounded-lg cursor-pointer border-n-weak"
            :class="form[period] ? 'bg-n-alpha-2' : ''"
          >
            <input v-model="form[period]" type="checkbox" class="mt-1" />
            <span class="flex flex-col">
              <span class="font-medium">
                {{
                  t(`VIRTUAL_CLINIC.SUMMARY.PERIODS.${period.toUpperCase()}`)
                }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t(`VIRTUAL_CLINIC.SUMMARY.WHEN.${period.toUpperCase()}`) }}
              </span>
            </span>
          </label>
        </div>
        <label class="flex items-center gap-3">
          {{ t('VIRTUAL_CLINIC.SUMMARY.HOUR') }}
          <select
            v-model.number="form.hour"
            class="!mb-0 w-28 px-2 py-1.5 text-sm border rounded-lg border-n-weak bg-n-solid-2"
          >
            <option v-for="hour in hours" :key="hour.value" :value="hour.value">
              {{ hour.label }}
            </option>
          </select>
        </label>
        <p class="text-xs text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.SUMMARY.WHERE', { name }) }}
        </p>
      </template>
    </div>
  </Dialog>
</template>

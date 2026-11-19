<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Button from 'dashboard/components-next/button/Button.vue';

// Lives on Settings → Integrations → OpenAI: talking to Clara and Helena
// spends this key, so the clinic administrator caps the questions here.
const { t } = useI18n();
const { currentAccount } = useAccount();
const visible = ref(false);
const limit = ref('');
const saving = ref(false);

onMounted(async () => {
  if (currentAccount.value?.virtual_clinic_enabled !== true) return;
  const { data } = await VirtualClinicAPI.getConfig();
  visible.value = data.ai_team.can_manage_settings === true;
  limit.value = data.ai_team.daily_question_limit ?? '';
});

const save = async () => {
  saving.value = true;
  try {
    await VirtualClinicAPI.updateSettings({
      daily_question_limit: limit.value,
    });
    useAlert(t('VIRTUAL_CLINIC.SETTINGS.SAVED'));
  } catch {
    useAlert(t('VIRTUAL_CLINIC.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <section
    v-if="visible"
    class="flex flex-col gap-3 p-5 mt-6 border rounded-xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-1">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('VIRTUAL_CLINIC.SETTINGS.TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11">
        {{ t('VIRTUAL_CLINIC.SETTINGS.DESCRIPTION') }}
      </p>
    </div>
    <div class="flex items-end gap-3">
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('VIRTUAL_CLINIC.SETTINGS.DAILY_LIMIT') }}
        <input
          v-model="limit"
          type="number"
          min="1"
          class="w-40 px-3 py-2 text-sm border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12"
          :placeholder="t('VIRTUAL_CLINIC.SETTINGS.NO_LIMIT')"
        />
      </label>
      <Button
        :label="t('VIRTUAL_CLINIC.SETTINGS.SAVE')"
        :is-loading="saving"
        @click="save"
      />
    </div>
    <p class="text-xs text-n-slate-10">
      {{ t('VIRTUAL_CLINIC.SETTINGS.HINT') }}
    </p>
  </section>
</template>

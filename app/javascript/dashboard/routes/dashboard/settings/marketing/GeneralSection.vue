<script setup>
// The "Geral" group on Pixel e Dados. Currently one field: Average ticket
// (in BRL). The Analytics report and the Funnel campaign breakdown grid
// use this value to compute Revenue and ROAS when a per-Comparecimento
// value isn't stored on the conversation.
//
// Backend permits `average_ticket` on the account update endpoint
// (see PR F5 backend change) so the manager doesn't need super_admin
// access to update it.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const averageTicket = ref(0);
const isSaving = ref(false);

const syncFromAccount = () => {
  averageTicket.value = Number(currentAccount.value?.average_ticket) || 0;
};

watch(
  currentAccount,
  () => {
    syncFromAccount();
  },
  { immediate: true }
);

const isDirty = computed(
  () =>
    Number(averageTicket.value) !==
    (Number(currentAccount.value?.average_ticket) || 0)
);

const save = async () => {
  isSaving.value = true;
  try {
    await updateAccount({ average_ticket: Number(averageTicket.value) || 0 });
    useAlert(t('MARKETING_ANALYTICS.GENERAL.SAVE_SUCCESS'));
    syncFromAccount();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('MARKETING_ANALYTICS.GENERAL.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <section class="rounded-lg border border-n-strong bg-n-solid-1 p-6">
    <header class="flex items-start justify-between gap-4 mb-4">
      <div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('MARKETING_ANALYTICS.GENERAL.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('MARKETING_ANALYTICS.GENERAL.DESCRIPTION') }}
        </p>
      </div>
    </header>

    <form
      class="flex flex-col sm:flex-row items-start sm:items-end gap-3"
      @submit.prevent="save"
    >
      <label class="flex flex-col gap-1 flex-1 text-sm">
        <span class="text-n-slate-11">
          {{ t('MARKETING_ANALYTICS.GENERAL.AVERAGE_TICKET') }}
        </span>
        <div class="flex items-stretch">
          <span
            class="rounded-l border border-r-0 border-n-strong bg-n-alpha-2 px-2 py-1.5 text-n-slate-11 text-sm flex items-center"
          >
            {{ t('MARKETING_ANALYTICS.GENERAL.CURRENCY_PREFIX') }}
          </span>
          <input
            v-model.number="averageTicket"
            type="number"
            step="0.01"
            min="0"
            class="rounded-r border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12 flex-1"
          />
        </div>
      </label>
      <button
        type="submit"
        :disabled="!isDirty || isSaving"
        class="rounded bg-n-brand hover:bg-n-brand/90 text-white px-4 py-1.5 text-sm font-medium disabled:opacity-50"
      >
        {{ t('MARKETING_ANALYTICS.SAVE') }}
      </button>
    </form>
  </section>
</template>

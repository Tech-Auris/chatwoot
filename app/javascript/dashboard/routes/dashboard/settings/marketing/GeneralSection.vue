<script setup>
// The "Geral" group on Pixel e Dados. Currently one field: Average ticket
// (in BRL). The Analytics report and the Funnel campaign breakdown grid
// use this value to compute Revenue and ROAS when a per-Comparecimento
// value isn't stored on the conversation.
//
// Backend permits `average_ticket` on the account update endpoint
// (see PR G) so the manager doesn't need super_admin access to update it.
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

    <form class="grid grid-cols-1 md:grid-cols-2 gap-4" @submit.prevent="save">
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">
          {{ t('MARKETING_ANALYTICS.GENERAL.AVERAGE_TICKET') }}
        </span>
        <div class="relative">
          <span
            class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2 text-n-slate-11 text-sm"
          >
            {{ t('MARKETING_ANALYTICS.GENERAL.CURRENCY_PREFIX') }}
          </span>
          <input
            v-model.number="averageTicket"
            type="number"
            step="0.01"
            min="0"
            class="w-full rounded border border-n-strong bg-n-solid-2 pl-8 pr-2 py-1.5 text-n-slate-12"
          />
        </div>
      </label>

      <div class="col-span-full flex justify-end">
        <button
          type="submit"
          :disabled="!isDirty || isSaving"
          class="rounded bg-n-brand hover:bg-n-brand/90 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-50"
        >
          {{ t('MARKETING_ANALYTICS.SAVE') }}
        </button>
      </div>
    </form>
  </section>
</template>

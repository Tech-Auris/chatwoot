<script setup>
// The "Geral" group on Pixel e Dados. Currently one field: Average ticket
// (in BRL). The Analytics report and the Funnel campaign breakdown grid
// use this value to compute Revenue and ROAS when a per-Comparecimento
// value isn't stored on the conversation.
//
// The input is a masked text field: raw keystrokes are stripped to digits
// and reformatted as pt-BR decimal (dot thousands + comma decimals) on
// every keypress, so the operator types "150000" and sees "1.500,00".
// The unmasked Number is what goes to the backend.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const isSaving = ref(false);
// Display string in pt-BR format ("1.500,00"). The numeric source of
// truth is derived from stripping non-digits and treating the result as
// cents.
const displayValue = ref('');

const brlFormatter = new Intl.NumberFormat('pt-BR', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const formatFromNumber = value => {
  const cents = Math.round((Number(value) || 0) * 100);
  return brlFormatter.format(cents / 100);
};

const parseFromMasked = masked => {
  const digits = (masked || '').replace(/\D/g, '');
  if (!digits) return 0;
  return Number(digits) / 100;
};

const syncFromAccount = () => {
  const stored = Number(currentAccount.value?.average_ticket) || 0;
  displayValue.value = formatFromNumber(stored);
};

watch(
  currentAccount,
  () => {
    syncFromAccount();
  },
  { immediate: true }
);

const onInput = event => {
  const parsed = parseFromMasked(event.target.value);
  displayValue.value = formatFromNumber(parsed);
};

const currentNumber = computed(() => parseFromMasked(displayValue.value));

const isDirty = computed(
  () =>
    currentNumber.value !== (Number(currentAccount.value?.average_ticket) || 0)
);

const save = async () => {
  isSaving.value = true;
  try {
    await updateAccount({ average_ticket: currentNumber.value });
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
            class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-n-slate-11 text-sm"
          >
            {{ t('MARKETING_ANALYTICS.GENERAL.CURRENCY_PREFIX') }}
          </span>
          <input
            :value="displayValue"
            type="text"
            inputmode="numeric"
            class="w-full rounded border border-n-strong bg-n-solid-2 pl-10 pr-3 py-1.5 text-n-slate-12 text-right"
            @input="onInput"
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

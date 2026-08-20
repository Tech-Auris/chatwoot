<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const CATEGORY_LABELS = {
  text: 'Texto',
  media: 'Imagem, arquivo e transcrições',
  audio: 'Áudio',
};

const CATEGORIES = ['text', 'media', 'audio'];

const SAMPLE_CSV = '/downloads/token-usage-sample.csv';

const prices = ref([]);
const selectedPrices = ref({ text: '', media: '', audio: '' });
const file = ref(null);
const preview = ref(null);
const description = ref('');
const period = ref('');
const daysUntilDue = ref(7);
const loading = ref(false);
const issuing = ref(false);
const error = ref(null);
const results = ref(null);

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? '';

const formatAmount = amount => {
  if (amount == null) return '—';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(amount / 100);
};

const formatNumber = value => new Intl.NumberFormat('pt-BR').format(value || 0);

// Stripe prices are immutable: changing an amount creates a new price and the
// old one stays in the catalog. Two entries can therefore read exactly alike —
// the id is what tells them apart, so it rides along in the label.
const priceLabel = price => {
  const name = price.nickname || price.product_name || price.id;
  return `${name} — ${formatAmount(price.unit_amount)} (${price.id})`;
};

// Same product and same amount appearing more than once almost always means a
// duplicate left behind in Stripe. Saying so beats letting someone pick one of
// them at random every month.
const duplicatedPrices = computed(() => {
  const seen = new Map();
  prices.value.forEach(price => {
    const key = `${price.nickname || price.product_name}|${price.unit_amount}`;
    seen.set(key, (seen.get(key) || 0) + 1);
  });
  return [...seen.entries()]
    .filter(([, count]) => count > 1)
    .map(([key]) => key.split('|')[0]);
});

const fetchData = async () => {
  try {
    const res = await fetch(props.componentData.data_url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    prices.value = body.prices || [];
    // Last month's choice comes back filled in, so nobody re-picks it monthly.
    CATEGORIES.forEach(category => {
      selectedPrices.value[category] = body.selected_prices?.[category] || '';
    });
  } catch (e) {
    error.value = e.message;
  }
};

onMounted(() => {
  if (props.componentData.configured) fetchData();
});

const onFileChange = event => {
  file.value = event.target.files?.[0] || null;
  preview.value = null;
  results.value = null;
};

const allPricesChosen = computed(() =>
  CATEGORIES.every(category => selectedPrices.value[category])
);

const submitPreview = async () => {
  loading.value = true;
  error.value = null;
  results.value = null;
  try {
    const form = new FormData();
    form.append('file', file.value);
    CATEGORIES.forEach(category => {
      form.append(`prices[${category}]`, selectedPrices.value[category]);
    });

    const res = await fetch(props.componentData.preview_url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      body: form,
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    preview.value = body;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

const billableLines = computed(() =>
  (preview.value?.lines || []).filter(line => line.billable)
);

const blockedLines = computed(() =>
  (preview.value?.lines || []).filter(line => !line.billable)
);

const submitIssue = async () => {
  issuing.value = true;
  error.value = null;
  try {
    const res = await fetch(props.componentData.create_url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      body: JSON.stringify({
        rows: preview.value.rows,
        prices: selectedPrices.value,
        description: description.value,
        period: period.value,
        days_until_due: daysUntilDue.value,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    results.value = body;
    preview.value = null;
  } catch (e) {
    error.value = e.message;
  } finally {
    issuing.value = false;
  }
};

const statusLabel = status =>
  ({ issued: 'Emitida', skipped: 'Ignorada', failed: 'Falhou' })[status] ||
  status;
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Cobrança de tokens</h1>
      <p class="text-sm text-slate-500 mt-1">
        Importe a planilha de consumo do mês, confira os totais e só então emita
        as faturas. A importação não cobra nada — nada vai para o Stripe antes
        da sua confirmação.
      </p>
    </div>

    <div
      v-if="!componentData.configured"
      class="p-4 rounded border border-amber-100 bg-amber-25 text-sm text-amber-700"
    >
      Stripe ainda não configurado. Salve a Stripe Secret Key em
      <a :href="componentData.settings_url" class="underline">
        Settings → Stripe
      </a>
      para liberar esta tela.
    </div>

    <template v-else>
      <div v-if="error" class="p-3 mb-4 rounded bg-red-25 text-sm text-red-700">
        {{ error }}
      </div>

      <div class="border border-slate-100 rounded-lg p-5 mb-6">
        <h2 class="text-sm font-medium text-slate-800 mb-3">
          1. Preço de cada categoria
        </h2>
        <p v-if="duplicatedPrices.length" class="text-xs text-amber-700 mb-2">
          Há preços repetidos no catálogo do Stripe ({{
            duplicatedPrices.join(', ')
          }}). O id ao lado de cada opção diz qual é qual — vale arquivar os
          antigos em Financeiro → Produtos.
        </p>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <label
            v-for="category in CATEGORIES"
            :key="category"
            class="block text-xs text-slate-500"
          >
            {{ CATEGORY_LABELS[category] }}
            <select
              v-model="selectedPrices[category]"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            >
              <option value="">— escolher —</option>
              <option v-for="price in prices" :key="price.id" :value="price.id">
                {{ priceLabel(price) }}
              </option>
            </select>
          </label>
        </div>

        <h2 class="text-sm font-medium text-slate-800 mt-5 mb-3">
          2. Planilha de consumo
        </h2>
        <p class="text-xs text-slate-500 mb-2">
          Colunas: accountid, accountname, texto, imagem arquivo e transcrições,
          audio.
          <a
            :href="SAMPLE_CSV"
            download="token-usage-sample.csv"
            class="text-woot-500 underline ml-1"
          >
            Baixar um exemplo de csv.
          </a>
        </p>
        <input type="file" accept=".csv,text/csv" @change="onFileChange" />

        <div class="mt-4">
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="!file || !allPricesChosen || loading"
            @click="submitPreview"
          >
            {{ loading ? 'Calculando…' : 'Conferir totais' }}
          </button>
        </div>
      </div>

      <div v-if="preview" class="border border-slate-100 rounded-lg p-5 mb-6">
        <div class="flex items-baseline justify-between mb-4">
          <h2 class="text-sm font-medium text-slate-800">
            3. Conferência — {{ preview.billable_count }} cliente(s) a faturar
          </h2>
          <div class="text-right">
            <div class="text-xs text-slate-500">Total do lote</div>
            <div class="text-2xl font-medium text-slate-900">
              {{ formatAmount(preview.total_amount) }}
            </div>
          </div>
        </div>

        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-slate-500 border-b border-slate-100">
              <th class="py-2">Conta</th>
              <th class="py-2 text-right">Texto</th>
              <th class="py-2 text-right">Mídia</th>
              <th class="py-2 text-right">Áudio</th>
              <th class="py-2 text-right">Total</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="line in billableLines"
              :key="line.account_id"
              class="border-b border-slate-50"
            >
              <td class="py-2 text-slate-900">
                {{ line.account_name }}
                <span class="text-xs text-slate-400"
                  >#{{ line.account_id }}</span
                >
              </td>
              <td class="py-2 text-right text-slate-600">
                {{ formatNumber(line.quantities.text) }}
              </td>
              <td class="py-2 text-right text-slate-600">
                {{ formatNumber(line.quantities.media) }}
              </td>
              <td class="py-2 text-right text-slate-600">
                {{ formatNumber(line.quantities.audio) }}
              </td>
              <td class="py-2 text-right text-slate-900">
                {{ formatAmount(line.total_amount) }}
              </td>
            </tr>
          </tbody>
        </table>

        <div v-if="blockedLines.length" class="mt-4">
          <p class="text-xs text-amber-700 mb-1">
            {{ blockedLines.length }} linha(s) fora do lote:
          </p>
          <ul class="text-xs text-amber-700 list-disc pl-4">
            <li v-for="line in blockedLines" :key="line.account_id">
              {{ line.account_name || 'conta ' + line.account_id }} —
              {{ line.issue }}
            </li>
          </ul>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mt-5">
          <label class="block text-xs text-slate-500 md:col-span-2">
            Descrição da fatura
            <input
              v-model="description"
              type="text"
              placeholder="Cobrança Tokens - Julho/2026"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
          <label class="block text-xs text-slate-500">
            Vencimento (dias)
            <input
              v-model.number="daysUntilDue"
              type="number"
              min="1"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
          <label class="block text-xs text-slate-500">
            Período (para conferência depois)
            <input
              v-model="period"
              type="text"
              placeholder="2026-07"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
        </div>

        <div class="flex items-center gap-3 mt-5">
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="issuing || !preview.billable_count"
            @click="submitIssue"
          >
            {{
              issuing
                ? 'Emitindo…'
                : `Emitir ${preview.billable_count} fatura(s)`
            }}
          </button>
          <span class="text-xs text-slate-500">
            As faturas vão para clientes reais e não podem ser desfeitas em
            lote.
          </span>
        </div>
      </div>

      <div v-if="results" class="border border-slate-100 rounded-lg p-5">
        <h2 class="text-sm font-medium text-slate-800 mb-3">
          Resultado — {{ results.issued_count }} fatura(s) emitida(s)
        </h2>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-slate-500 border-b border-slate-100">
              <th class="py-2">Conta</th>
              <th class="py-2">Status</th>
              <th class="py-2">Fatura</th>
              <th class="py-2 text-right">Valor</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in results.results"
              :key="row.account_id"
              class="border-b border-slate-50"
            >
              <td class="py-2 text-slate-900">{{ row.account_name }}</td>
              <td class="py-2">
                <span
                  class="text-xs px-2 py-1 rounded"
                  :class="
                    row.status === 'issued'
                      ? 'bg-emerald-25 text-emerald-700'
                      : row.status === 'failed'
                        ? 'bg-red-25 text-red-700'
                        : 'bg-slate-25 text-slate-600'
                  "
                >
                  {{ statusLabel(row.status) }}
                </span>
                <span v-if="row.error" class="text-xs text-slate-500 ml-2">
                  {{ row.error }}
                </span>
              </td>
              <td class="py-2">
                <a
                  v-if="row.invoice_url"
                  :href="row.invoice_url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-woot-500 underline"
                >
                  {{ row.invoice_number || row.invoice_id }}
                </a>
                <span v-else class="text-slate-400">—</span>
              </td>
              <td class="py-2 text-right text-slate-700">
                {{ formatAmount(row.total_amount) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>

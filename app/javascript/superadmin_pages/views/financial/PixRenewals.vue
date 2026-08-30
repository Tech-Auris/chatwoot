<script setup>
import { ref, computed, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const TABS = [
  { id: 'open', label: 'Em aberto' },
  { id: 'paid', label: 'Pagas' },
];

const STATUS_LABELS = {
  pending: 'A faturar',
  invoiced: 'Faturada',
  paid: 'Paga',
  cancelled: 'Cancelada',
};

const CYCLE_LABELS = {
  monthly: 'Mensal',
  semiannual: 'Semestral',
  annual: 'Anual',
};

const SOURCE_LABELS = {
  inter: 'Banco Inter',
  asaas: 'AsaaS',
};

const activeTab = ref('open');
const renewals = ref([]);
const awaitingFirstPayment = ref([]);
const meta = ref({
  alert_count: 0,
  overdue_count: 0,
  alert_window_days: 7,
  sources: ['inter', 'asaas'],
});
const loading = ref(false);
const error = ref(null);
const busyId = ref(null);
const paidVia = ref('inter');

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? '';

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({ status: activeTab.value });
    const res = await fetch(`${props.componentData.data_url}?${params}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    renewals.value = body.renewals || [];
    awaitingFirstPayment.value = body.awaiting_first_payment || [];
    meta.value = body.meta || meta.value;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  if (props.componentData.configured) fetchData();
});

watch(activeTab, fetchData);

const post = async (url, payload, key) => {
  busyId.value = key;
  error.value = null;
  try {
    const res = await fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    await fetchData();
  } catch (e) {
    error.value = e.message;
  } finally {
    busyId.value = null;
  }
};

const issueInvoice = renewal =>
  post(
    `${props.componentData.renewals_url}/${renewal.id}/invoice`,
    {},
    renewal.id
  );

const payRenewal = renewal =>
  post(
    `${props.componentData.renewals_url}/${renewal.id}/pay`,
    { paid_via: paidVia.value },
    renewal.id
  );

const cancelRenewal = renewal => {
  if (!window.confirm('Encerrar a cobrança deste cliente?')) return;
  post(
    `${props.componentData.renewals_url}/${renewal.id}/cancel`,
    {},
    renewal.id
  );
};

const registerSale = quote =>
  post(
    props.componentData.register_sale_url,
    { sales_quote_id: quote.id, paid_via: paidVia.value },
    `quote-${quote.id}`
  );

const formatAmount = amount =>
  amount == null
    ? '—'
    : new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: 'BRL',
      }).format(amount / 100);

const formatDate = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';

const statusLabel = renewal => STATUS_LABELS[renewal.status] || renewal.status;
const cycleLabel = cycle => CYCLE_LABELS[cycle] || '—';
const sourceLabel = source => SOURCE_LABELS[source] || source;

const rowClass = renewal => {
  if (renewal.overdue) return 'bg-red-50 text-red-700';
  if (renewal.alerting) return 'bg-yellow-50 text-yellow-700';
  if (renewal.status === 'paid') return 'bg-green-50 text-green-700';
  return 'bg-slate-25 text-slate-600';
};

const alertMessage = computed(() => {
  const { alert_count: alerts, overdue_count: overdue } = meta.value;
  if (overdue) return `${overdue} renovação(ões) vencida(s) sem pagamento`;
  if (alerts)
    return `${alerts} renovação(ões) vencendo nos próximos ${meta.value.alert_window_days} dias`;
  return '';
});
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Renovações PIX</h1>
      <p class="text-sm text-slate-500 mt-1">
        Quem paga por PIX não renova sozinho: cada ciclo precisa ser faturado e
        baixado à mão. Esta tela avisa quais períodos estão vencendo e guarda o
        histórico de cada cobrança.
      </p>
    </div>

    <div
      v-if="!componentData.configured"
      class="p-4 rounded border border-yellow-100 bg-yellow-50 text-sm text-yellow-700"
    >
      Stripe ainda não configurado. Salve a Stripe Secret Key em
      <a :href="componentData.settings_url" class="underline">
        Settings → Stripe
      </a>
      para liberar esta tela.
    </div>

    <template v-else>
      <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
        {{ error }}
      </div>

      <div class="flex items-center gap-3 mb-4">
        <label class="text-sm text-slate-500">Dinheiro entrou por</label>
        <select
          v-model="paidVia"
          class="text-sm border border-slate-200 rounded px-2 py-1"
        >
          <option v-for="source in meta.sources" :key="source" :value="source">
            {{ sourceLabel(source) }}
          </option>
        </select>
        <span v-if="alertMessage" class="ml-auto text-xs text-yellow-700">
          {{ alertMessage }}
        </span>
      </div>

      <section v-if="awaitingFirstPayment.length" class="mb-8">
        <h2 class="text-base font-medium text-slate-900 mb-2">
          Vendas aguardando o primeiro PIX
        </h2>
        <p class="text-sm text-slate-500 mb-3">
          Propostas com os termos assinados que escolheram PIX. Ao registrar o
          pagamento, a conta é criada e o próximo vencimento entra na lista
          abaixo.
        </p>

        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-slate-500 border-b border-slate-100">
              <th class="py-2">Cliente</th>
              <th class="py-2">Ciclo</th>
              <th class="py-2">Assinou em</th>
              <th class="py-2 text-right">Valor</th>
              <th class="py-2 text-right">Ação</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="quote in awaitingFirstPayment"
              :key="quote.id"
              class="border-b border-slate-50"
            >
              <td class="py-3">
                <div class="text-slate-900">{{ quote.customer_name }}</div>
                <div class="text-xs text-slate-400 mt-1">
                  {{ quote.prospect_email }}
                </div>
              </td>
              <td class="py-3 text-slate-700">
                {{ cycleLabel(quote.billing_cycle) }}
              </td>
              <td class="py-3 text-slate-700">
                {{ formatDate(quote.signed_at) }}
              </td>
              <td class="py-3 text-right text-slate-700">
                {{ formatAmount(quote.amount) }}
              </td>
              <td class="py-3 text-right">
                <button
                  type="button"
                  class="px-2 py-1 rounded bg-woot-500 text-white text-xs disabled:opacity-40"
                  :disabled="busyId === `quote-${quote.id}`"
                  @click="registerSale(quote)"
                >
                  Registrar pagamento
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <div class="flex items-center gap-4 border-b border-slate-100 mb-4">
        <button
          v-for="tab in TABS"
          :key="tab.id"
          type="button"
          class="pb-2 text-sm border-b-2"
          :class="
            activeTab === tab.id
              ? 'border-woot-500 text-woot-500'
              : 'border-transparent text-slate-500'
          "
          @click="activeTab = tab.id"
        >
          {{ tab.label }}
        </button>
      </div>

      <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-slate-500 border-b border-slate-100">
            <th class="py-2">Cliente</th>
            <th class="py-2">Conta</th>
            <th class="py-2">Ciclo</th>
            <th class="py-2">Mês de vencimento</th>
            <th class="py-2">Situação</th>
            <th class="py-2 text-right">Valor</th>
            <th class="py-2 text-right">Ação</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="renewal in renewals"
            :key="renewal.id"
            class="border-b border-slate-50"
          >
            <td class="py-3 text-slate-900">{{ renewal.customer_name }}</td>
            <td class="py-3 text-slate-700">{{ renewal.account_name }}</td>
            <td class="py-3 text-slate-700">
              {{ cycleLabel(renewal.billing_cycle) }}
            </td>
            <td class="py-3 text-slate-700">
              {{ renewal.reference_month }}
              <div class="text-xs text-slate-400 mt-1">
                vence em {{ formatDate(renewal.due_on) }}
              </div>
            </td>

            <td class="py-3">
              <span
                class="px-2 py-0.5 rounded text-xs"
                :class="rowClass(renewal)"
              >
                {{ renewal.overdue ? 'Vencida' : statusLabel(renewal) }}
              </span>
              <div v-if="renewal.paid_via" class="text-xs text-slate-400 mt-1">
                Baixa manual — {{ sourceLabel(renewal.paid_via) }}
              </div>
              <a
                v-else-if="renewal.hosted_invoice_url"
                :href="renewal.hosted_invoice_url"
                target="_blank"
                rel="noopener noreferrer"
                class="block text-xs text-woot-500 underline mt-1"
              >
                Ver fatura
              </a>
            </td>

            <td class="py-3 text-right text-slate-700">
              {{ formatAmount(renewal.amount) }}
            </td>

            <td class="py-3 text-right">
              <div class="flex gap-2 justify-end">
                <button
                  v-if="renewal.status === 'pending'"
                  type="button"
                  class="px-2 py-1 rounded bg-woot-500 text-white text-xs disabled:opacity-40"
                  :disabled="busyId === renewal.id"
                  @click="issueInvoice(renewal)"
                >
                  Gerar fatura
                </button>
                <button
                  v-if="renewal.status === 'invoiced'"
                  type="button"
                  class="px-2 py-1 rounded bg-woot-500 text-white text-xs disabled:opacity-40"
                  :disabled="busyId === renewal.id"
                  @click="payRenewal(renewal)"
                >
                  Dar baixa
                </button>
                <button
                  v-if="renewal.status !== 'paid'"
                  type="button"
                  class="px-2 py-1 rounded border border-slate-200 text-slate-600 text-xs disabled:opacity-40"
                  :disabled="busyId === renewal.id"
                  @click="cancelRenewal(renewal)"
                >
                  Encerrar
                </button>
              </div>
            </td>
          </tr>

          <tr v-if="!renewals.length">
            <td colspan="7" class="py-6 text-center text-slate-400">
              Nenhuma renovação nesta aba.
            </td>
          </tr>
        </tbody>
      </table>
    </template>
  </div>
</template>

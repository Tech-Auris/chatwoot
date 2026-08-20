<script setup>
import { ref, computed, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const TABS = [
  { id: 'pending', label: 'Pendentes' },
  { id: 'linked', label: 'Conciliados' },
];

const activeTab = ref('pending');
const accounts = ref([]);
const customers = ref([]);
const meta = ref({
  current_page: 1,
  total_pages: 1,
  total_count: 0,
  linked_count: 0,
  pending_count: 0,
});
const page = ref(1);
const search = ref('');
const loading = ref(false);
const saving = ref(false);
const error = ref(null);

// Which account row has the customer picker open, and what is selected in it.
const pickerAccountId = ref(null);
const pickerValue = ref('');
const pickerSearch = ref('');

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? '';

const request = async (url, { method = 'GET', body } = {}) => {
  const res = await fetch(url, {
    method,
    credentials: 'same-origin',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload.error || `HTTP ${res.status}`);
  return payload;
};

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({
      scope: activeTab.value,
      page: String(page.value),
    });
    if (search.value.trim()) params.set('search', search.value.trim());

    const body = await request(`${props.componentData.data_url}?${params}`);
    accounts.value = body.accounts || [];
    customers.value = body.customers || [];
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

watch([activeTab, page], fetchData);

const changeTab = tab => {
  if (activeTab.value === tab) return;
  pickerAccountId.value = null;
  page.value = 1;
  activeTab.value = tab;
};

const submitSearch = () => {
  page.value = 1;
  fetchData();
};

const linkUrl = accountId => `${props.componentData.links_url}/${accountId}`;

const run = async (fn, { onDone } = {}) => {
  saving.value = true;
  error.value = null;
  try {
    await fn();
    if (onDone) onDone();
    await fetchData();
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

const openPicker = account => {
  pickerAccountId.value = account.id;
  pickerValue.value = account.stripe_customer_id || '';
  pickerSearch.value = '';
};

const filteredCustomers = computed(() => {
  const term = pickerSearch.value.trim().toLowerCase();
  if (!term) return customers.value;
  return customers.value.filter(
    customer =>
      customer.name?.toLowerCase().includes(term) ||
      customer.email?.toLowerCase().includes(term) ||
      customer.id.toLowerCase().includes(term)
  );
});

const linkAccount = (account, customerId) =>
  run(
    () =>
      request(linkUrl(account.id), {
        method: 'PATCH',
        body: { stripe_customer_id: customerId },
      }),
    {
      onDone: () => {
        pickerAccountId.value = null;
      },
    }
  );

const unlinkAccount = account => {
  const message = `Desvincular "${account.name}" do cliente ${account.stripe_customer?.name || account.stripe_customer_id}? A conta volta para a aba Pendentes. Nada é excluído no Stripe.`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;
  run(() => request(linkUrl(account.id), { method: 'DELETE' }));
};

const createCustomer = account => {
  const message = `Criar um cliente novo no Stripe para "${account.name}" e vincular? Use isso apenas se a conta ainda não existe lá.`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;
  run(() => request(`${linkUrl(account.id)}/customer`, { method: 'POST' }));
};

// Not every customer is charged for token usage — internal accounts, courtesy,
// contracts where it is bundled. The monthly batch reads this flag and leaves
// those accounts out on its own.
const toggleTokenBilling = account => {
  const enabling = !account.token_billing_enabled;
  const message = enabling
    ? `Voltar a cobrar tokens de "${account.name}"? A conta passa a entrar nos próximos lotes de cobrança.`
    : `Parar de cobrar tokens de "${account.name}"? A conta deixa de entrar nos lotes de cobrança de tokens.`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;

  run(() =>
    request(`${linkUrl(account.id)}/token_billing`, {
      method: 'POST',
      body: { enabled: enabling },
    })
  );
};

const customerLabel = customer => {
  if (!customer) return '—';
  const parts = [customer.name || customer.id];
  if (customer.email) parts.push(customer.email);
  return parts.join(' · ');
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Vínculos com o Stripe</h1>
      <p class="text-sm text-slate-500 mt-1">
        Relaciona cada conta do AurisChat ao cliente correspondente no Stripe. O
        vínculo é gravado dos dois lados, então também aparece no painel do
        Stripe.
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
      <div
        v-if="error"
        class="mb-4 p-3 rounded border border-red-100 bg-red-25 text-sm text-red-700"
      >
        {{ error }}
      </div>

      <div class="flex items-center gap-4 border-b border-slate-100 mb-4">
        <button
          v-for="tab in TABS"
          :key="tab.id"
          type="button"
          class="px-1 py-2 text-sm -mb-px border-b-2"
          :class="
            activeTab === tab.id
              ? 'border-woot-500 text-woot-500'
              : 'border-transparent text-slate-600'
          "
          @click="changeTab(tab.id)"
        >
          {{ tab.label }}
          <span class="ml-1 text-xs text-slate-400">
            {{ tab.id === 'pending' ? meta.pending_count : meta.linked_count }}
          </span>
        </button>
      </div>

      <form class="flex items-center gap-3 mb-4" @submit.prevent="submitSearch">
        <input
          v-model="search"
          placeholder="Buscar conta pelo nome"
          class="border border-slate-100 rounded-md p-2 text-sm w-72"
        />
        <button type="submit" class="text-sm text-woot-500">Buscar</button>
        <span class="ml-auto text-xs text-slate-500">
          {{ meta.total_count }} conta(s) nesta aba
        </span>
      </form>

      <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>
      <p v-else-if="!accounts.length" class="text-sm text-slate-500">
        {{
          activeTab === 'pending'
            ? 'Nenhuma conta pendente. Tudo conciliado.'
            : 'Nenhuma conta conciliada ainda.'
        }}
      </p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr
            class="text-left text-xs uppercase text-slate-500 border-b border-slate-100"
          >
            <th class="py-2">Conta</th>
            <th class="py-2">
              {{ activeTab === 'pending' ? 'Sugestões' : 'Cliente no Stripe' }}
            </th>
            <th class="py-2 text-right">Ações</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="account in accounts" :key="account.id">
            <tr class="border-b border-slate-50 align-top">
              <td class="py-3">
                <div class="text-slate-900">{{ account.name }}</div>
                <div class="text-xs text-slate-500">
                  {{ account.admin_emails.join(', ') || 'sem administrador' }}
                </div>
                <div class="text-xs text-slate-400 mt-1">
                  ID da conta: {{ account.id }}
                </div>
              </td>

              <td class="py-3">
                <template v-if="activeTab === 'linked'">
                  <div class="text-slate-700">
                    {{ customerLabel(account.stripe_customer) }}
                  </div>
                  <div class="text-xs text-slate-400">
                    {{ account.stripe_customer_id }}
                  </div>
                  <div
                    v-if="!account.stripe_customer"
                    class="text-xs text-amber-700 mt-1"
                  >
                    Cliente não encontrado no Stripe — pode ter sido excluído
                    lá.
                  </div>
                </template>

                <template v-else>
                  <div
                    v-if="!account.suggestions.length"
                    class="text-xs text-slate-400"
                  >
                    Sem sugestão automática
                  </div>
                  <div
                    v-for="suggestion in account.suggestions"
                    :key="suggestion.id"
                    class="flex items-center gap-2 mb-1"
                  >
                    <button
                      type="button"
                      :disabled="saving"
                      class="text-woot-500 text-xs disabled:opacity-50"
                      @click="linkAccount(account, suggestion.id)"
                    >
                      Vincular
                    </button>
                    <span class="text-xs text-slate-700">
                      {{ customerLabel(suggestion) }}
                    </span>
                    <span class="text-xs text-slate-400">
                      ({{ suggestion.reason }})
                    </span>
                  </div>
                </template>
              </td>

              <td class="py-3 text-right whitespace-nowrap">
                <button
                  type="button"
                  class="mr-3"
                  :class="
                    account.token_billing_enabled
                      ? 'text-slate-600'
                      : 'text-amber-700'
                  "
                  :title="
                    account.token_billing_enabled
                      ? 'Esta conta entra nos lotes de cobrança de tokens'
                      : 'Esta conta fica de fora dos lotes de cobrança de tokens'
                  "
                  @click="toggleTokenBilling(account)"
                >
                  {{
                    account.token_billing_enabled
                      ? 'Tokens: cobra'
                      : 'Tokens: não cobra'
                  }}
                </button>
                <button
                  type="button"
                  class="text-woot-500 mr-3"
                  @click="openPicker(account)"
                >
                  {{ activeTab === 'linked' ? 'Trocar' : 'Escolher' }}
                </button>
                <button
                  v-if="activeTab === 'linked'"
                  type="button"
                  class="text-red-600"
                  @click="unlinkAccount(account)"
                >
                  Desvincular
                </button>
                <button
                  v-else
                  type="button"
                  class="text-slate-600"
                  @click="createCustomer(account)"
                >
                  Criar no Stripe
                </button>
              </td>
            </tr>

            <tr
              v-if="pickerAccountId === account.id"
              :key="`${account.id}-picker`"
            >
              <td colspan="3" class="pb-4">
                <div class="p-3 rounded border border-slate-100 bg-slate-25">
                  <p class="text-xs text-slate-500 mb-2">
                    Clientes já vinculados a outra conta não aparecem na lista —
                    a relação é de um para um.
                  </p>
                  <input
                    v-model="pickerSearch"
                    placeholder="Buscar cliente por nome, e-mail ou ID"
                    class="mb-2 w-full border border-slate-100 rounded-md p-2 text-sm"
                  />
                  <select
                    v-model="pickerValue"
                    size="6"
                    class="w-full border border-slate-100 rounded-md p-2 text-sm"
                  >
                    <option
                      v-for="customer in filteredCustomers"
                      :key="customer.id"
                      :value="customer.id"
                    >
                      {{ customerLabel(customer) }}
                    </option>
                  </select>
                  <div class="flex gap-2 mt-3">
                    <button
                      type="button"
                      :disabled="saving || !pickerValue"
                      class="px-3 py-2 text-sm rounded-md bg-woot-500 text-white disabled:opacity-50"
                      @click="linkAccount(account, pickerValue)"
                    >
                      Vincular selecionado
                    </button>
                    <button
                      type="button"
                      class="px-3 py-2 text-sm rounded-md border border-slate-100 text-slate-700"
                      @click="pickerAccountId = null"
                    >
                      Cancelar
                    </button>
                  </div>
                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>

      <div
        v-if="meta.total_pages > 1"
        class="flex items-center gap-3 mt-4 text-sm"
      >
        <button
          type="button"
          class="text-woot-500 disabled:opacity-40"
          :disabled="page <= 1"
          @click="page -= 1"
        >
          Anterior
        </button>
        <span class="text-slate-500">
          Página {{ meta.current_page }} de {{ meta.total_pages }}
        </span>
        <button
          type="button"
          class="text-woot-500 disabled:opacity-40"
          :disabled="page >= meta.total_pages"
          @click="page += 1"
        >
          Próxima
        </button>
      </div>
    </template>
  </div>
</template>

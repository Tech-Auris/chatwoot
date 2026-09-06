<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: { type: Object, default: () => ({}) },
});

// The wizard walks the super admin through three steps: preview the marketing
// page → set the campaign settings (deadline, document date) → pick the
// required signers per account. Only the last step's Confirmar button hits
// `create_url`; the earlier steps stay client-side.

const step = ref(1);
const error = ref(null);
const loading = ref(false);

// Step 1 — preview
const previewUrlInput = ref('');
const version = ref(null);
const confirmedDocument = ref(false);

// Step 2 — settings
const documentDateInput = ref('');
const deadlineDaysInput = ref(7);

// Step 3 — signers
const accounts = ref([]);
const requiredByAccount = ref({}); // { [accountId]: Set<accountUserId> }

const csrfToken = () =>
  document.querySelector('meta[name=csrf-token]')?.getAttribute('content') ||
  '';

// Reader convenience — the wizard blocks step 2 until the super admin has
// scrolled the terms and ticked the confirmation. Simplest signal is the
// checkbox; a stricter version could wire scroll position later.
const canAdvanceFromStep1 = computed(
  () => version.value && confirmedDocument.value
);
const canAdvanceFromStep2 = computed(
  () =>
    documentDateInput.value &&
    Number(deadlineDaysInput.value) >= 1 &&
    Number(deadlineDaysInput.value) <= 90
);
const totalRequired = computed(() =>
  Object.values(requiredByAccount.value).reduce((sum, set) => sum + set.size, 0)
);

const fetchPreview = async () => {
  loading.value = true;
  error.value = null;
  try {
    const form = new FormData();
    if (previewUrlInput.value) form.set('url', previewUrlInput.value);
    const res = await fetch(props.componentData.preview_url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      body: form,
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    version.value = body;
    documentDateInput.value = body.document_date || '';
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

const fetchRoster = async () => {
  loading.value = true;
  error.value = null;
  try {
    const res = await fetch(props.componentData.roster_url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    accounts.value = body.accounts || [];
    // Pre-mark every manager as required so the default is "the whole roster
    // has to sign"; the super admin unticks those who don't.
    requiredByAccount.value = accounts.value.reduce((acc, account) => {
      acc[account.account_id] = new Set(
        account.managers.map(m => m.account_user_id)
      );
      return acc;
    }, {});
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

const toggleSigner = (accountId, accountUserId) => {
  const set = requiredByAccount.value[accountId];
  if (!set) return;
  if (set.has(accountUserId)) set.delete(accountUserId);
  else set.add(accountUserId);
  // Reassign so Vue reactivity picks it up (Set mutations don't trigger it).
  requiredByAccount.value = { ...requiredByAccount.value };
};

const isRequired = (accountId, accountUserId) =>
  requiredByAccount.value[accountId]?.has(accountUserId);

const advance = async () => {
  if (step.value === 1 && !canAdvanceFromStep1.value) return;
  if (step.value === 2 && !canAdvanceFromStep2.value) return;
  if (step.value === 2) await fetchRoster();
  step.value += 1;
};

const goBack = () => {
  if (step.value > 1) step.value -= 1;
};

const submit = async () => {
  loading.value = true;
  error.value = null;
  const payload = {
    campaign: {
      terms_version_id: version.value.id,
      document_date: documentDateInput.value,
      deadline_at: new Date(
        Date.now() + Number(deadlineDaysInput.value) * 24 * 60 * 60 * 1000
      ).toISOString(),
      required_signers_by_account: Object.fromEntries(
        Object.entries(requiredByAccount.value)
          .map(([id, set]) => [id, Array.from(set)])
          .filter(([, ids]) => ids.length)
      ),
    },
  };
  try {
    const res = await fetch(props.componentData.create_url, {
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
    window.location.href = props.componentData.show_url_template.replace(
      ':id',
      body.id
    );
  } catch (e) {
    error.value = e.message;
    loading.value = false;
  }
};

const stepTitle = n =>
  ({ 1: 'Confirmar documento', 2: 'Configuração', 3: 'Assinantes' })[n];

const cancel = () => {
  window.location.href = props.componentData.index_url;
};

onMounted(fetchPreview);
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">
        Nova campanha de termos
      </h1>
      <p class="text-sm text-slate-500 mt-1">
        Passo {{ step }} de 3 · {{ stepTitle(step) }}
      </p>
    </div>

    <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
      {{ error }}
    </div>

    <!-- Step 1: preview + confirm -->
    <section v-if="step === 1">
      <div class="mb-4 flex items-end gap-2">
        <div class="flex-1">
          <label class="block text-xs text-slate-500 mb-1">
            URL da versão pública (opcional — em branco usa o padrão)
          </label>
          <input
            v-model="previewUrlInput"
            type="url"
            placeholder="https://www.auris.ia.br/termos-de-uso"
            class="w-full px-3 py-2 border border-slate-200 rounded text-sm"
          />
        </div>
        <button
          type="button"
          class="px-3 py-2 rounded border border-slate-200 text-sm text-slate-700"
          :disabled="loading"
          @click="fetchPreview"
        >
          Recarregar
        </button>
      </div>

      <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

      <div v-else-if="version" class="border border-slate-200 rounded">
        <div class="p-3 border-b border-slate-100 text-xs text-slate-500">
          Fonte: {{ version.source_url }} · Hash:
          {{ version.content_hash?.slice(0, 12) }}
          <span v-if="version.document_date">
            · Data no documento: {{ version.document_date }}</span
          >
        </div>
        <div
          class="p-4 max-h-[60vh] overflow-y-auto text-sm text-slate-700 prose-sm"
        >
          <div v-dompurify-html="version.content" />
        </div>
      </div>

      <label class="flex items-start gap-2 mt-4 text-sm text-slate-700">
        <input v-model="confirmedDocument" type="checkbox" class="mt-1" />
        <span
          >Confirmo que este é o documento atualizado que os gerentes devem
          assinar.</span
        >
      </label>
    </section>

    <!-- Step 2: settings -->
    <section v-if="step === 2" class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <label class="block text-xs text-slate-500 mb-1"
          >Data do documento</label
        >
        <input
          v-model="documentDateInput"
          type="date"
          class="w-full px-3 py-2 border border-slate-200 rounded text-sm"
        />
        <p class="text-xs text-slate-400 mt-1">
          Detectada automaticamente a partir de "Última atualização" quando
          possível.
        </p>
      </div>
      <div>
        <label class="block text-xs text-slate-500 mb-1"
          >Vencimento em quantos dias?</label
        >
        <input
          v-model.number="deadlineDaysInput"
          type="number"
          min="1"
          max="90"
          class="w-full px-3 py-2 border border-slate-200 rounded text-sm"
        />
        <p class="text-xs text-slate-400 mt-1">Entre 1 e 90 dias.</p>
      </div>
    </section>

    <!-- Step 3: signers per account -->
    <section v-if="step === 3">
      <p v-if="loading" class="text-sm text-slate-500">Carregando gerentes…</p>
      <div v-else>
        <p class="text-sm text-slate-500 mb-3">
          Todos os gerentes vêm pré-marcados como obrigatórios. Desmarque quem
          não precisar assinar. Contas sem gerente não aparecem.
        </p>
        <div
          class="border border-slate-200 rounded max-h-[60vh] overflow-y-auto"
        >
          <div
            v-for="account in accounts"
            :key="account.account_id"
            class="p-3 border-b border-slate-100 last:border-b-0"
          >
            <div class="font-medium text-slate-800 text-sm mb-2">
              {{ account.account_name }}
              <span class="text-xs text-slate-400">
                #{{ account.account_id }}
              </span>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-1">
              <label
                v-for="manager in account.managers"
                :key="manager.account_user_id"
                class="flex items-center gap-2 text-sm text-slate-700"
              >
                <input
                  type="checkbox"
                  :checked="
                    isRequired(account.account_id, manager.account_user_id)
                  "
                  @change="
                    toggleSigner(account.account_id, manager.account_user_id)
                  "
                />
                <span>{{ manager.name || manager.email }}</span>
                <span class="text-xs text-slate-400">{{ manager.email }}</span>
              </label>
            </div>
          </div>
        </div>
        <p class="text-xs text-slate-500 mt-3">
          {{ totalRequired }} assinatura(s) será(ão) solicitada(s).
        </p>
      </div>
    </section>

    <!-- Footer -->
    <div class="flex items-center justify-between mt-6">
      <button
        type="button"
        class="px-3 py-1.5 rounded border border-slate-200 text-sm text-slate-600 disabled:opacity-40"
        :disabled="step === 1"
        @click="goBack"
      >
        Voltar
      </button>
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="px-3 py-1.5 rounded border border-slate-200 text-sm text-slate-600"
          @click="cancel"
        >
          Cancelar
        </button>
        <button
          v-if="step < 3"
          type="button"
          class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
          :disabled="
            loading ||
            (step === 1 && !canAdvanceFromStep1) ||
            (step === 2 && !canAdvanceFromStep2)
          "
          @click="advance"
        >
          Avançar
        </button>
        <button
          v-else
          type="button"
          class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
          :disabled="loading || totalRequired === 0"
          @click="submit"
        >
          Criar campanha
        </button>
      </div>
    </div>
  </div>
</template>

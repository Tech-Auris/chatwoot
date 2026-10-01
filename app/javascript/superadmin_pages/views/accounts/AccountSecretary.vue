<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: { type: Object, default: () => ({}) },
});

const STATUS_LABELS = {
  testing: 'em teste',
  active: 'ativa',
  retired: 'descontinuada',
};

const versions = ref([]);
const inboxes = ref([]);
const simulatorInbox = ref(null);
const versionId = ref('');
const simulatorVersionId = ref('');
const selectedInboxIds = ref([]);
const secret = ref(null);
const showSecret = ref(false);
const loading = ref(true);
const saving = ref(false);
const message = ref(null);
const error = ref(null);

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content || '';

const applyPayload = body => {
  versions.value = body.versions || [];
  inboxes.value = body.inboxes || [];
  simulatorInbox.value = body.simulator_inbox;
  versionId.value = body.secretary_version_id || '';
  simulatorVersionId.value = body.simulator_version_id || '';
  selectedInboxIds.value = inboxes.value.filter(i => i.enabled).map(i => i.id);
  secret.value = body.secret;
};

const request = async (url, method, data) => {
  const res = await fetch(url, {
    method,
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
    credentials: 'same-origin',
    body: data ? JSON.stringify(data) : undefined,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
  return body;
};

// The account can keep a retired version it already runs, but only active
// versions are offered for a new pick. The Simulador also takes testing ones.
const accountVersionOptions = computed(() =>
  versions.value.filter(
    v => v.status === 'active' || v.id === Number(versionId.value)
  )
);
const simulatorVersionOptions = computed(() =>
  versions.value.filter(
    v => v.status !== 'retired' || v.id === Number(simulatorVersionId.value)
  )
);

const versionLabel = version =>
  version.status === 'active'
    ? version.name
    : `${version.name} · ${STATUS_LABELS[version.status]}`;

const selectedInboxes = computed(() =>
  inboxes.value.filter(i => selectedInboxIds.value.includes(i.id))
);
const availableInboxes = computed(() =>
  inboxes.value.filter(i => !selectedInboxIds.value.includes(i.id))
);

const addInbox = event => {
  const id = Number(event.target.value);
  if (id) selectedInboxIds.value = [...selectedInboxIds.value, id];
  event.target.value = '';
};
const removeInbox = id => {
  selectedInboxIds.value = selectedInboxIds.value.filter(i => i !== id);
};
const selectAll = () => {
  selectedInboxIds.value = inboxes.value.map(i => i.id);
};
const clearAll = () => {
  selectedInboxIds.value = [];
};

const maskedSecret = computed(() => {
  if (!secret.value) return 'Gerado ao salvar';
  return showSecret.value ? secret.value : '•'.repeat(24);
});

const flash = text => {
  message.value = text;
  setTimeout(() => {
    message.value = null;
  }, 3000);
};

const load = async () => {
  loading.value = true;
  try {
    applyPayload(await request(props.componentData.url, 'GET'));
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

const save = async () => {
  saving.value = true;
  error.value = null;
  try {
    const body = await request(props.componentData.url, 'PATCH', {
      secretary_version_id: versionId.value || null,
      simulator_version_id: simulatorVersionId.value || null,
      inbox_ids: selectedInboxIds.value,
    });
    applyPayload(body);
    flash('Secretária atualizada');
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

const regenerateSecret = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Gerar um novo segredo? O anterior deixa de valer.'))
    return;
  error.value = null;
  try {
    const body = await request(props.componentData.regenerate_url, 'POST');
    secret.value = body.secret;
    showSecret.value = true;
    flash('Novo segredo gerado');
  } catch (e) {
    error.value = e.message;
  }
};

const copySecret = async () => {
  try {
    await navigator.clipboard.writeText(secret.value);
    flash('Segredo copiado');
  } catch (e) {
    error.value = 'Não foi possível copiar o segredo';
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-6 py-4">
    <h2 class="text-lg font-medium text-n-slate-12">Secretária</h2>

    <p v-if="loading" class="text-sm text-n-slate-11">Carregando…</p>

    <template v-else>
      <div class="grid grid-cols-[12rem_1fr] gap-x-6 gap-y-6 items-start">
        <label for="secretary-version" class="text-sm text-n-slate-11 pt-2">
          Versão da secretária
        </label>
        <select
          id="secretary-version"
          v-model="versionId"
          class="w-80 border border-slate-200 rounded px-2 py-1.5 text-sm"
        >
          <option value="">Sem secretária</option>
          <option
            v-for="version in accountVersionOptions"
            :key="version.id"
            :value="version.id"
          >
            {{ versionLabel(version) }}
          </option>
        </select>

        <span class="text-sm text-n-slate-11 pt-2">Caixas de entrada</span>
        <div class="flex flex-col gap-2">
          <div
            class="flex flex-wrap gap-2 min-h-11 p-2 border border-slate-200 rounded-lg"
          >
            <span
              v-for="inbox in selectedInboxes"
              :key="inbox.id"
              class="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-n-slate-3 text-sm text-n-slate-12"
            >
              {{ inbox.name }}
              <span
                role="button"
                tabindex="0"
                class="cursor-pointer text-n-slate-11 hover:text-n-slate-12"
                :aria-label="`Remover ${inbox.name}`"
                @click="removeInbox(inbox.id)"
                @keydown.enter="removeInbox(inbox.id)"
              >
                ×
              </span>
            </span>
            <select
              v-if="availableInboxes.length"
              class="flex-1 min-w-48 border-0 text-sm text-n-slate-11 bg-transparent"
              @change="addInbox"
            >
              <option value="">Adicionar caixa…</option>
              <option
                v-for="inbox in availableInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
            <span
              v-if="!inboxes.length"
              class="text-sm text-n-slate-11 self-center"
            >
              A conta não tem caixas de entrada.
            </span>
          </div>
          <div class="flex items-center gap-4 text-sm">
            <span
              role="button"
              tabindex="0"
              class="cursor-pointer text-woot-500"
              @click="selectAll"
              @keydown.enter="selectAll"
            >
              Selecionar todas
            </span>
            <span
              role="button"
              tabindex="0"
              class="cursor-pointer text-woot-500"
              @click="clearAll"
              @keydown.enter="clearAll"
            >
              Limpar
            </span>
          </div>
          <p class="text-xs text-n-slate-11">
            Caixas em que a secretária atende. O Simulador tem campo próprio.
          </p>
        </div>

        <label for="simulator-version" class="text-sm text-n-slate-11 pt-2">
          Simulador
        </label>
        <div class="flex flex-col gap-2">
          <select
            id="simulator-version"
            v-model="simulatorVersionId"
            class="w-80 border border-slate-200 rounded px-2 py-1.5 text-sm"
            :disabled="!simulatorInbox"
          >
            <option value="">Mesma da conta</option>
            <option
              v-for="version in simulatorVersionOptions"
              :key="version.id"
              :value="version.id"
            >
              {{ versionLabel(version) }}
            </option>
          </select>
          <p class="text-xs text-n-slate-11">
            {{
              simulatorInbox
                ? 'Versão usada só na caixa Simulador. Permite testar uma versão nova antes de liberar.'
                : 'Esta conta não tem caixa Simulador.'
            }}
          </p>
        </div>

        <span class="text-sm text-n-slate-11 pt-2">Segredo</span>
        <div class="flex flex-col gap-2">
          <div class="flex flex-wrap items-center gap-3">
            <code
              class="px-2 py-1.5 rounded bg-n-slate-3 text-sm text-n-slate-12 font-mono break-all"
            >
              {{ maskedSecret }}
            </code>
            <template v-if="secret">
              <span
                role="button"
                tabindex="0"
                class="cursor-pointer text-sm text-woot-500"
                @click="showSecret = !showSecret"
                @keydown.enter="showSecret = !showSecret"
              >
                {{ showSecret ? 'Ocultar' : 'Mostrar' }}
              </span>
              <span
                role="button"
                tabindex="0"
                class="cursor-pointer text-sm text-woot-500"
                @click="copySecret"
                @keydown.enter="copySecret"
              >
                Copiar
              </span>
              <span
                role="button"
                tabindex="0"
                class="cursor-pointer text-sm text-woot-500"
                @click="regenerateSecret"
                @keydown.enter="regenerateSecret"
              >
                Gerar novo
              </span>
            </template>
          </div>
          <p class="text-xs text-n-slate-11">
            Usado para assinar os envios (X-Chatwoot-Signature), igual ao
            webhook em Integrações.
          </p>
        </div>
      </div>

      <div class="flex items-center gap-4">
        <button
          type="button"
          class="px-4 py-2 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
          :disabled="saving"
          @click="save"
        >
          {{ saving ? 'Salvando…' : 'Atualizar' }}
        </button>
        <span v-if="message" class="text-sm text-n-teal-11">
          {{ message }}
        </span>
        <span v-if="error" class="text-sm text-n-ruby-11">{{ error }}</span>
      </div>
    </template>
  </div>
</template>

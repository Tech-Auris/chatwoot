<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: { type: Object, default: () => ({}) },
});

const FIELD_HINTS = {
  razao_social: 'Razão social (PJ)',
  cnpj: 'CNPJ (PJ)',
  endereco: 'Endereço completo, montado dos campos',
  representante_nome: 'Representante legal (PJ)',
  representante_cpf: 'CPF do representante (PJ)',
  representante_email: 'E-mail do representante (PJ)',
  nome_completo: 'Nome do contratante (PF)',
  cpf: 'CPF do contratante (PF)',
  email: 'E-mail do contratante (PF)',
  periodo_licenca: 'Ex.: 12 (doze) meses, de 15/10/2026 a 14/10/2027',
  produtos: 'Lista dos itens da proposta com quantidades',
  valor_total: 'Total com descontos, em número',
  valor_total_extenso: 'Total por extenso',
  forma_pagamento: 'Ex.: 12 (doze) parcelas de R$ 1.849,20 (…) no cartão',
  descontos: 'Descontos concedidos',
  data_contratacao: 'Data em que o contrato é gerado',
};

const loading = ref(true);
const error = ref(null);
const message = ref(null);
const enabled = ref(true);
const autoSign = ref(true);
const autentiqueConfigured = ref(false);
const template = ref(null);
const versions = ref([]);
const fields = ref([]);
const signer = ref(null);
const signerError = ref(null);
const editor = ref(null);
const saving = ref(false);
const previewing = ref(null);

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content || '';

const request = async (url, method = 'GET', body = null) => {
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
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
};

const flash = text => {
  message.value = text;
  setTimeout(() => {
    message.value = null;
  }, 3000);
};

const setEditorContent = html => {
  if (editor.value) editor.value.innerHTML = html;
};

const apply = data => {
  enabled.value = data.enabled;
  autoSign.value = data.auto_sign;
  autentiqueConfigured.value = data.autentique_configured;
  template.value = data.template;
  versions.value = data.versions;
  fields.value = data.fields;
};

const loadSigner = async () => {
  if (!autentiqueConfigured.value) return;
  try {
    signer.value = await request(props.componentData.signer_url);
    signerError.value = null;
  } catch (e) {
    signerError.value = e.message;
  }
};

const load = async () => {
  try {
    apply(await request(props.componentData.data_url));
    loading.value = false;
    // The editor only exists once loading is false.
    setTimeout(() => setEditorContent(template.value.content));
    loadSigner();
  } catch (e) {
    error.value = e.message;
    loading.value = false;
  }
};

const saveSettings = async (nextEnabled, nextAutoSign) => {
  try {
    apply(
      await request(props.componentData.settings_url, 'PATCH', {
        enabled: nextEnabled,
        auto_sign: nextAutoSign,
      })
    );
    flash('Configuração salva');
  } catch (e) {
    error.value = e.message;
  }
};

const format = (command, value = null) => {
  editor.value?.focus();
  document.execCommand(command, false, value);
};

const insertField = field => {
  editor.value?.focus();
  document.execCommand('insertText', false, `{{${field}}}`);
};

const saveTemplate = async () => {
  saving.value = true;
  error.value = null;
  try {
    apply(
      await request(props.componentData.templates_url, 'POST', {
        content: editor.value.innerHTML,
      })
    );
    setEditorContent(template.value.content);
    flash(`Versão v${template.value.version} salva`);
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

const preview = async personType => {
  previewing.value = personType;
  error.value = null;
  try {
    const res = await fetch(props.componentData.preview_url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      body: JSON.stringify({
        content: editor.value.innerHTML,
        person_type: personType,
      }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const url = URL.createObjectURL(await res.blob());
    window.open(url, '_blank', 'noopener');
  } catch (e) {
    error.value = `Não foi possível gerar a pré-visualização: ${e.message}`;
  } finally {
    previewing.value = null;
  }
};

const loadVersion = async version => {
  try {
    const data = await request(
      `${props.componentData.template_version_url}/${version}.json`
    );
    setEditorContent(data.content);
    flash(
      `Versão v${version} carregada no editor. Salve para torná-la a atual.`
    );
  } catch (e) {
    error.value = e.message;
  }
};

const formatDate = value =>
  value
    ? new Date(value).toLocaleString('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '—';

const currentVersion = computed(() => template.value?.version);

const placeholder = field => `{{${field}}}`;
const BLOCK_HINT = '{{#se_pj}}…{{/se_pj}}';

onMounted(load);
</script>

<template>
  <div class="w-full px-6 py-6 bg-n-background">
    <div class="max-w-6xl mx-auto flex flex-col gap-5">
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12">Contrato</h1>
        <p class="text-sm text-n-slate-11">
          Contrato gerado e enviado para assinatura nas contratações semestrais
          e anuais.
        </p>
      </div>

      <p v-if="loading" class="text-sm text-n-slate-11">Carregando…</p>
      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
      <p v-if="message" class="text-sm text-n-teal-11">{{ message }}</p>

      <template v-if="!loading && template">
        <section
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl p-5 flex items-center justify-between gap-6"
        >
          <div class="flex flex-col gap-1">
            <h2 class="text-base font-semibold text-n-slate-12">
              Fluxo de contrato
            </h2>
            <p class="text-sm text-n-slate-11 max-w-2xl">
              Ao ativar, um contrato será gerado automaticamente após o
              preenchimento de dados do cliente.
            </p>
          </div>
          <button
            type="button"
            role="switch"
            :aria-checked="enabled"
            class="reset-base flex items-center gap-2 text-sm font-semibold"
            :class="enabled ? 'text-n-teal-11' : 'text-n-slate-11'"
            @click="saveSettings(!enabled, autoSign)"
          >
            <span
              class="relative inline-block w-11 h-6 rounded-full transition-colors"
              :class="enabled ? 'bg-n-teal-9' : 'bg-n-slate-7'"
            >
              <span
                class="absolute top-[3px] w-[18px] h-[18px] rounded-full bg-white transition-all"
                :class="enabled ? 'left-[23px]' : 'left-[3px]'"
              />
            </span>
            {{ enabled ? 'Ligado' : 'Desligado' }}
          </button>
        </section>

        <section
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl p-5 flex flex-col gap-4"
        >
          <div class="flex items-start justify-between gap-6">
            <div class="flex flex-col gap-1">
              <h2 class="text-base font-semibold text-n-slate-12">
                Assinatura da Auris
              </h2>
              <p class="text-sm text-n-slate-11 max-w-2xl">
                Ao ativar, o representante legal da Auris assina
                automaticamente.
              </p>
            </div>
            <button
              type="button"
              role="switch"
              :aria-checked="autoSign"
              class="reset-base flex items-center gap-2 text-sm font-semibold flex-none"
              :class="autoSign ? 'text-n-teal-11' : 'text-n-slate-11'"
              @click="saveSettings(enabled, !autoSign)"
            >
              <span
                class="relative inline-block w-11 h-6 rounded-full transition-colors"
                :class="autoSign ? 'bg-n-teal-9' : 'bg-n-slate-7'"
              >
                <span
                  class="absolute top-[3px] w-[18px] h-[18px] rounded-full bg-white transition-all"
                  :class="autoSign ? 'left-[23px]' : 'left-[3px]'"
                />
              </span>
              Assinar automaticamente
            </button>
          </div>
          <div
            class="flex flex-col gap-1 rounded-lg px-4 py-3 text-sm"
            :class="
              signer
                ? 'bg-n-teal-2 outline outline-1 outline-n-teal-6'
                : 'bg-n-amber-2 outline outline-1 outline-n-amber-6'
            "
          >
            <span v-if="signer" class="text-n-slate-12">
              <strong>Representante legal da Auris:</strong>
              {{ signer.name }} · {{ signer.email }}
            </span>
            <span v-else-if="!autentiqueConfigured" class="text-n-amber-11">
              Token do Autentique não configurado.
              <a :href="componentData.autentique_settings_url">
                Configurar em Settings → Autentique
              </a>
            </span>
            <span v-else class="text-n-amber-11">
              Não foi possível consultar o Autentique: {{ signerError }}
            </span>
            <span class="text-n-slate-11">
              Conta dona do token do Autentique (Settings → Autentique). Para
              trocar quem assina, gere o token na conta do novo signatário.
            </span>
          </div>
        </section>

        <section
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl p-5 flex flex-col gap-4"
        >
          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex flex-col gap-0.5">
              <h2 class="text-base font-semibold text-n-slate-12">
                Modelo do contrato
              </h2>
              <span class="text-xs text-n-slate-11">
                Versão atual: v{{ currentVersion }} · salva em
                {{ formatDate(template.created_at) }} por
                {{ template.created_by_name || '—' }}
              </span>
            </div>
            <div class="flex gap-2">
              <button
                type="button"
                class="reset-base px-3 py-2 rounded-lg outline outline-1 outline-n-weak text-sm text-n-slate-12 disabled:opacity-50"
                :disabled="previewing !== null"
                @click="preview('pj')"
              >
                {{
                  previewing === 'pj' ? 'Gerando…' : 'Pré-visualizar PDF (PJ)'
                }}
              </button>
              <button
                type="button"
                class="reset-base px-3 py-2 rounded-lg outline outline-1 outline-n-weak text-sm text-n-slate-12 disabled:opacity-50"
                :disabled="previewing !== null"
                @click="preview('pf')"
              >
                {{
                  previewing === 'pf' ? 'Gerando…' : 'Pré-visualizar PDF (PF)'
                }}
              </button>
              <button
                type="button"
                class="reset-base px-4 py-2 rounded-lg bg-n-brand text-white text-sm font-semibold disabled:opacity-50"
                :disabled="saving"
                @click="saveTemplate"
              >
                {{ saving ? 'Salvando…' : 'Salvar nova versão' }}
              </button>
            </div>
          </div>

          <div class="grid grid-cols-[minmax(0,1fr)_300px] gap-4">
            <div
              class="flex flex-col rounded-lg outline outline-1 outline-n-weak overflow-hidden"
            >
              <div
                class="flex gap-1 px-2 py-1.5 border-b border-n-weak bg-n-alpha-1 text-sm text-n-slate-11"
              >
                <button
                  type="button"
                  class="reset-base min-w-8 h-8 font-bold"
                  aria-label="Negrito"
                  @click="format('bold')"
                >
                  B
                </button>
                <button
                  type="button"
                  class="reset-base min-w-8 h-8 italic"
                  aria-label="Itálico"
                  @click="format('italic')"
                >
                  I
                </button>
                <button
                  type="button"
                  class="reset-base min-w-8 h-8 underline"
                  aria-label="Sublinhado"
                  @click="format('underline')"
                >
                  U
                </button>
                <button
                  type="button"
                  class="reset-base h-8 px-2"
                  @click="format('formatBlock', 'h3')"
                >
                  Título
                </button>
                <button
                  type="button"
                  class="reset-base h-8 px-2"
                  @click="format('formatBlock', 'p')"
                >
                  Parágrafo
                </button>
                <button
                  type="button"
                  class="reset-base h-8 px-2"
                  @click="format('insertUnorderedList')"
                >
                  Lista
                </button>
              </div>
              <div
                ref="editor"
                contenteditable="true"
                class="px-6 py-5 h-[640px] overflow-y-auto text-sm leading-relaxed text-n-slate-12 bg-white focus:outline-none [&_table]:w-full [&_table]:border-collapse [&_table]:mb-3 [&_td]:border [&_td]:border-n-slate-7 [&_td]:px-2 [&_td]:py-1.5 [&_th]:border [&_th]:border-n-slate-7 [&_p]:mb-1.5 [&_ul]:list-disc [&_ul]:pl-5 [&_h2]:text-base [&_h2]:font-semibold [&_h3]:font-semibold"
              />
            </div>

            <aside
              class="flex flex-col gap-3 rounded-lg outline outline-1 outline-n-weak p-4 bg-n-alpha-1 text-xs h-[684px] overflow-y-auto"
            >
              <h3 class="text-sm font-semibold text-n-slate-12">
                Campos automáticos
              </h3>
              <span class="text-n-slate-11">
                Clique para inserir no ponto do cursor.
              </span>
              <button
                v-for="field in fields"
                :key="field"
                type="button"
                class="reset-base flex flex-col items-start gap-0.5 text-left rounded px-2 py-1.5 hover:bg-n-alpha-2"
                @click="insertField(field)"
              >
                <code class="text-n-brand">{{ placeholder(field) }}</code>
                <span class="text-n-slate-11">{{ FIELD_HINTS[field] }}</span>
              </button>
              <div
                class="flex flex-col gap-0.5 px-2 pt-2 border-t border-n-weak"
              >
                <code class="text-n-brand">{{ BLOCK_HINT }}</code>
                <span class="text-n-slate-11">
                  Trecho que só aparece para PJ (idem
                  <code>se_pf</code>
                  para PF)
                </span>
              </div>
            </aside>
          </div>
        </section>

        <section
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl p-5 flex flex-col gap-3"
        >
          <h2 class="text-base font-semibold text-n-slate-12">
            Versões do modelo
          </h2>
          <table class="w-full text-sm">
            <thead class="text-left text-n-slate-11">
              <tr>
                <th class="py-2 font-medium">Versão</th>
                <th class="py-2 font-medium">Salva em</th>
                <th class="py-2 font-medium">Por</th>
                <th class="py-2" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="version in versions"
                :key="version.version"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="py-2">
                  <strong>v{{ version.version }}</strong>
                  <span
                    v-if="version.version === currentVersion"
                    class="ml-1 px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11 text-xs"
                  >
                    atual
                  </span>
                </td>
                <td class="py-2">{{ formatDate(version.created_at) }}</td>
                <td class="py-2">{{ version.created_by_name || '—' }}</td>
                <td class="py-2 text-right">
                  <button
                    v-if="version.version !== currentVersion"
                    type="button"
                    class="reset-base text-n-brand"
                    @click="loadVersion(version.version)"
                  >
                    Carregar no editor
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <span class="text-xs text-n-slate-11">
            Cada contrato guarda a versão usada. Salvar uma versão nova não
            altera contratos já gerados.
          </span>
        </section>
      </template>
    </div>
  </div>
</template>

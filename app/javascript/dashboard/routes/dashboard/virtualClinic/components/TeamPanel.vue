<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  clinicName: { type: String, default: '' },
  aiTeam: { type: Object, default: null },
  selected: { type: String, default: '' },
});

const emit = defineEmits(['selectMember']);
const { t } = useI18n();

const members = computed(() => props.aiTeam?.members || []);
const enabled = computed(() => props.aiTeam?.enabled === true);

// Where the administrator goes to turn the AI team on.
const missingAction = computed(() => {
  if (props.aiTeam?.missing === 'mcp') {
    return {
      label: t('VIRTUAL_CLINIC.AI_TEAM.ENABLE_MCP'),
      hint: t('VIRTUAL_CLINIC.AI_TEAM.MISSING_MCP'),
      to: { name: 'settings_integrations_mcp' },
    };
  }
  if (props.aiTeam?.missing === 'openai_key') {
    return {
      label: t('VIRTUAL_CLINIC.AI_TEAM.CONFIGURE_OPENAI'),
      hint: t('VIRTUAL_CLINIC.AI_TEAM.MISSING_OPENAI'),
      to: {
        name: 'settings_applications_integration',
        params: { integration_id: 'openai' },
      },
    };
  }
  return null;
});

const select = member => {
  if (enabled.value) emit('selectMember', member.persona);
};
</script>

<template>
  <section
    class="flex flex-col w-64 shrink-0 gap-4 p-4 border-r border-n-weak bg-n-solid-1"
  >
    <h1 class="text-lg font-semibold text-n-slate-12 truncate">
      {{ clinicName }}
    </h1>

    <div v-if="aiTeam?.visible" class="flex flex-col gap-1">
      <h2 class="mb-1 text-xs font-medium text-n-slate-11">
        {{ t('VIRTUAL_CLINIC.AI_TEAM.TITLE', { count: members.length }) }}
      </h2>
      <button
        v-for="member in members"
        :key="member.persona"
        type="button"
        class="flex items-center gap-3 p-2 text-left rounded-lg"
        :class="[
          enabled ? 'hover:bg-n-alpha-2' : 'opacity-50 cursor-default',
          selected === member.persona ? 'bg-n-alpha-2' : '',
        ]"
        @click="select(member)"
      >
        <span
          class="grid text-sm font-semibold rounded-full size-9 place-items-center bg-n-teal-3 text-n-teal-11"
        >
          {{ member.name.charAt(0) }}
        </span>
        <span class="flex flex-col min-w-0">
          <span class="text-sm font-medium text-n-slate-12">
            {{ member.name }}
            <span class="ml-1 text-xs text-n-slate-11">
              {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
            </span>
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{
              enabled
                ? t('VIRTUAL_CLINIC.AI_TEAM.AVAILABLE')
                : t('VIRTUAL_CLINIC.AI_TEAM.OFF')
            }}
          </span>
        </span>
      </button>

      <div
        v-if="missingAction"
        class="flex flex-col gap-2 p-3 mt-2 rounded-lg bg-n-alpha-1"
      >
        <p class="text-xs text-n-slate-11">{{ missingAction.hint }}</p>
        <router-link :to="missingAction.to">
          <Button :label="missingAction.label" size="sm" class="w-full" />
        </router-link>
      </div>
    </div>
  </section>
</template>

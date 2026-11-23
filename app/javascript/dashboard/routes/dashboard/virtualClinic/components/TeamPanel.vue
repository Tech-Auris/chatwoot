<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PeopleList from './PeopleList.vue';
import { formatReais, isOffDuty, offDutyReason } from '../teamStatus';

const props = defineProps({
  clinicName: { type: String, default: '' },
  aiTeam: { type: Object, default: null },
  status: { type: Object, default: null },
  selected: { type: String, default: '' },
  // User ids walking on the map right now.
  peopleOnMap: { type: Array, default: () => [] },
  // Open alerts per AI teammate (❗).
  alertCounts: { type: Object, default: () => ({}) },
});

const emit = defineEmits([
  'selectMember',
  'edit',
  'editAvatar',
  'editProfile',
  'memberSettings',
]);
const { t } = useI18n();
const members = computed(() => props.aiTeam?.members || []);
const chatEnabled = computed(() => props.aiTeam?.chat_enabled === true);

// Where the administrator goes to be able to talk to the AI team.
const missingAction = computed(() => {
  if (props.aiTeam?.chat_missing === 'mcp') {
    return {
      label: t('VIRTUAL_CLINIC.AI_TEAM.ENABLE_MCP'),
      hint: t('VIRTUAL_CLINIC.AI_TEAM.MISSING_MCP'),
      to: { name: 'settings_integrations_mcp' },
    };
  }
  if (props.aiTeam?.chat_missing === 'openai_key') {
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

// One line of what each teammate is doing, from the live status. It does not
// depend on the OpenAI key: Clara serves patients through the n8n anyway.
const statusLine = persona => {
  // Agents don't get the numbers of the restricted teammates.
  if (!props.status?.[persona]) return '';
  if (isOffDuty(persona, props.status)) {
    return t('VIRTUAL_CLINIC.STATUS.OFF_DUTY', {
      reason: offDutyReason(props.status, t),
    });
  }
  if (persona === 'secretary') {
    const { active_conversations: active, in_follow_up: followUps } =
      props.status.secretary;
    if (!active && !followUps) return t('VIRTUAL_CLINIC.STATUS.IDLE');
    return t('VIRTUAL_CLINIC.STATUS.SECRETARY', { active, followUps });
  }
  if (persona === 'marketing') {
    const { active_campaigns: campaigns, cost_per_appointment: cost } =
      props.status.marketing;
    return cost === null
      ? t('VIRTUAL_CLINIC.STATUS.MARKETING_CAMPAIGNS', { campaigns })
      : t('VIRTUAL_CLINIC.STATUS.MARKETING', {
          campaigns,
          cost: formatReais(cost),
        });
  }
  const { leads, conversion_rate: rate } = props.status.manager.month;
  return rate === null
    ? t('VIRTUAL_CLINIC.STATUS.MANAGER_LEADS', { leads })
    : t('VIRTUAL_CLINIC.STATUS.MANAGER', { leads, rate });
};

// The manager also opens without the chat: she has the person's news.
const select = member => {
  if (chatEnabled.value || member.persona === 'manager') {
    emit('selectMember', member.persona);
  }
};
</script>

<template>
  <section
    class="flex flex-col w-72 shrink-0 gap-4 p-4 border-r border-n-weak bg-n-solid-1"
  >
    <div class="flex items-center gap-2">
      <h1 class="flex-1 text-lg font-semibold truncate text-n-slate-12">
        {{ clinicName }}
      </h1>
      <Button
        icon="i-lucide-user-pen"
        variant="ghost"
        color="slate"
        size="xs"
        :title="t('VIRTUAL_CLINIC.PROFILE.TITLE')"
        @click="emit('editProfile')"
      />
      <Button
        v-if="aiTeam?.can_edit_layout"
        icon="i-lucide-pencil-ruler"
        variant="ghost"
        color="slate"
        size="xs"
        :title="t('VIRTUAL_CLINIC.EDITOR.EDIT')"
        @click="emit('edit')"
      />
    </div>

    <div v-if="aiTeam?.visible" class="flex flex-col gap-1">
      <h2 class="mb-1 text-xs font-medium text-n-slate-11">
        {{ t('VIRTUAL_CLINIC.AI_TEAM.TITLE', { count: members.length }) }}
      </h2>
      <div v-for="member in members" :key="member.persona" class="relative">
        <button
          type="button"
          class="flex items-center w-full gap-3 p-2 text-left rounded-lg"
          :class="[
            chatEnabled || member.persona === 'manager'
              ? 'hover:bg-n-alpha-2'
              : 'cursor-default',
            isOffDuty(member.persona, status) ? 'opacity-50' : '',
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
            <span class="pr-12 text-sm font-medium text-n-slate-12">
              {{ member.name }}
              <span
                v-if="alertCounts[member.persona]"
                class="px-1.5 ml-1 text-xs font-semibold text-white rounded-full bg-n-ruby-9"
              >
                {{ alertCounts[member.persona] }}
              </span>
              <span class="ml-1 text-xs text-n-slate-11">
                {{
                  t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`)
                }}
              </span>
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{ statusLine(member.persona) }}
            </span>
            <span
              v-if="!chatEnabled && aiTeam.manages_team"
              class="flex items-center gap-1 text-xs text-n-slate-10"
            >
              <Icon icon="i-lucide-message-circle-off" class="size-3" />
              {{ t('VIRTUAL_CLINIC.AI_TEAM.CHAT_OFF') }}
            </span>
          </span>
        </button>
        <span class="absolute flex top-2 right-1">
          <Button
            v-if="aiTeam.manages_team"
            icon="i-lucide-settings"
            variant="ghost"
            color="slate"
            size="xs"
            class="!w-5"
            :title="
              t('VIRTUAL_CLINIC.MEMBER_SETTINGS.OPEN', { name: member.name })
            "
            @click="emit('memberSettings', member.persona)"
          />
          <Button
            v-if="aiTeam?.can_edit_layout"
            icon="i-lucide-shirt"
            variant="ghost"
            color="slate"
            size="xs"
            class="!w-5"
            :title="t('VIRTUAL_CLINIC.AVATAR.EDIT')"
            @click="emit('editAvatar', member.persona)"
          />
        </span>
      </div>

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

    <PeopleList
      :people-on-map="peopleOnMap"
      @edit-avatar="emit('editAvatar')"
      @edit-profile="emit('editProfile')"
    />
  </section>
</template>

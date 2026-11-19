<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';

const props = defineProps({
  clinicName: { type: String, default: '' },
  aiTeam: { type: Object, default: null },
  status: { type: Object, default: null },
  selected: { type: String, default: '' },
});

const emit = defineEmits(['selectMember']);
const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const agents = useMapGetter('agents/getNonInternalAgents');
const currentUserId = useMapGetter('getCurrentUserID');

// Online first, then busy, then offline; the user sits at the top. The AI
// user is left out: on the map it is Clara.
const STATUS_ORDER = { online: 0, busy: 1, offline: 2 };
const people = computed(() =>
  (agents.value || [])
    .filter(agent => !agent.is_ai_user)
    .sort(
      (a, b) =>
        (b.id === currentUserId.value) - (a.id === currentUserId.value) ||
        (STATUS_ORDER[a.availability_status] ?? 2) -
          (STATUS_ORDER[b.availability_status] ?? 2) ||
        a.name.localeCompare(b.name)
    )
);
const onlineCount = computed(
  () => people.value.filter(p => p.availability_status === 'online').length
);

// Opens (or creates) the direct message in the internal chat, Gather-style.
const openDirectMessage = async person => {
  if (person.id === currentUserId.value) return;
  const channel = await store.dispatch('internalChat/create', {
    channel: { channel_type: 'dm' },
    member_ids: [person.id],
  });
  router.push({
    name: 'internal_chat_dm',
    params: { accountId: route.params.accountId, channelId: channel.id },
  });
};

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

// The clinic pays the OpenAI key, so its administrator caps the questions.
const saveDailyLimit = event => {
  const value = event.target.value;
  VirtualClinicAPI.updateSettings({ daily_question_limit: value });
};

// One line of what each teammate is doing, from the live status.
const statusLine = persona => {
  if (!enabled.value) return t('VIRTUAL_CLINIC.AI_TEAM.OFF');
  if (!props.status) return t('VIRTUAL_CLINIC.AI_TEAM.AVAILABLE');
  if (persona === 'secretary') {
    const { active_conversations: active, in_follow_up: followUps } =
      props.status.secretary;
    if (!active && !followUps) return t('VIRTUAL_CLINIC.STATUS.IDLE');
    return t('VIRTUAL_CLINIC.STATUS.SECRETARY', { active, followUps });
  }
  const { leads, conversion_rate: rate } = props.status.manager.month;
  return rate === null
    ? t('VIRTUAL_CLINIC.STATUS.MANAGER_LEADS', { leads })
    : t('VIRTUAL_CLINIC.STATUS.MANAGER', { leads, rate });
};

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
            {{ statusLine(member.persona) }}
          </span>
        </span>
      </button>

      <label
        v-if="enabled && aiTeam.can_manage_settings"
        class="flex items-center justify-between gap-2 px-2 mt-1 text-xs text-n-slate-11"
      >
        {{ t('VIRTUAL_CLINIC.SETTINGS.DAILY_LIMIT') }}
        <input
          type="number"
          min="1"
          class="w-16 px-2 py-1 text-xs border rounded-md border-n-weak bg-n-solid-2 text-n-slate-12"
          :value="aiTeam.daily_question_limit"
          :placeholder="t('VIRTUAL_CLINIC.SETTINGS.NO_LIMIT')"
          @change="saveDailyLimit"
        />
      </label>

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

    <div class="flex flex-col min-h-0 gap-1">
      <h2 class="mb-1 text-xs font-medium text-n-slate-11">
        {{ t('VIRTUAL_CLINIC.PEOPLE.TITLE', { count: onlineCount }) }}
      </h2>
      <div class="flex flex-col gap-1 overflow-y-auto">
        <button
          v-for="person in people"
          :key="person.id"
          type="button"
          class="flex items-center gap-3 p-2 text-left rounded-lg hover:bg-n-alpha-2"
          @click="openDirectMessage(person)"
        >
          <Avatar
            :name="person.name"
            :src="person.thumbnail || ''"
            :status="person.availability_status"
            :size="32"
            rounded-full
          />
          <span class="flex flex-col min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ person.name }}
              <span
                v-if="person.id === currentUserId"
                class="text-xs font-normal text-n-slate-11"
              >
                {{ t('VIRTUAL_CLINIC.PEOPLE.YOU') }}
              </span>
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                t(
                  `VIRTUAL_CLINIC.PEOPLE.STATUS.${(person.availability_status || 'offline').toUpperCase()}`
                )
              }}
            </span>
          </span>
        </button>
      </div>
    </div>
  </section>
</template>

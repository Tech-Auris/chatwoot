<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import { isOffDuty, offDutyReason } from '../teamStatus';

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

const emit = defineEmits(['selectMember', 'edit', 'editAvatar']);
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

// Opens (or creates) the direct message in the internal chat, Gather-style;
// on yourself, the avatar editor.
const openDirectMessage = async person => {
  if (person.id === currentUserId.value) {
    emit('editAvatar');
    return;
  }
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
  if (!props.status) return '';
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
  const { leads, conversion_rate: rate } = props.status.manager.month;
  return rate === null
    ? t('VIRTUAL_CLINIC.STATUS.MANAGER_LEADS', { leads })
    : t('VIRTUAL_CLINIC.STATUS.MANAGER', { leads, rate });
};

// "Bom dia da Helena" at 8h, turned on by the clinic administrator.
const dailySummary = ref(false);
watch(
  () => props.aiTeam?.daily_summary,
  value => {
    dailySummary.value = value === true;
  },
  { immediate: true }
);
const toggleDailySummary = async () => {
  dailySummary.value = !dailySummary.value;
  await VirtualClinicAPI.updateSettings({ daily_summary: dailySummary.value });
};

const select = member => {
  if (chatEnabled.value) emit('selectMember', member.persona);
};
</script>

<template>
  <section
    class="flex flex-col w-64 shrink-0 gap-4 p-4 border-r border-n-weak bg-n-solid-1"
  >
    <div class="flex items-center gap-2">
      <h1 class="flex-1 text-lg font-semibold truncate text-n-slate-12">
        {{ clinicName }}
      </h1>
      <Button
        icon="i-lucide-shirt"
        variant="ghost"
        color="slate"
        size="xs"
        :title="t('VIRTUAL_CLINIC.AVATAR.TITLE')"
        @click="emit('editAvatar')"
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
            chatEnabled ? 'hover:bg-n-alpha-2' : 'cursor-default',
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
            <span class="text-sm font-medium text-n-slate-12">
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
              v-if="!chatEnabled"
              class="flex items-center gap-1 text-xs text-n-slate-10"
            >
              <Icon icon="i-lucide-message-circle-off" class="size-3" />
              {{ t('VIRTUAL_CLINIC.AI_TEAM.CHAT_OFF') }}
            </span>
          </span>
        </button>
        <Button
          v-if="aiTeam?.can_edit_layout"
          icon="i-lucide-shirt"
          variant="ghost"
          color="slate"
          size="xs"
          class="absolute top-2 right-1"
          :title="t('VIRTUAL_CLINIC.AVATAR.EDIT')"
          @click="emit('editAvatar', member.persona)"
        />
      </div>

      <label
        v-if="aiTeam.can_manage_settings"
        class="flex items-start gap-2 p-2 mt-1 text-xs cursor-pointer text-n-slate-11"
      >
        <input
          type="checkbox"
          class="mt-0.5"
          :checked="dailySummary"
          @change="toggleDailySummary"
        />
        <span>
          {{
            t('VIRTUAL_CLINIC.AI_TEAM.DAILY_SUMMARY', {
              name: members.find(m => m.persona === 'manager')?.name || '',
            })
          }}
        </span>
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
            <span class="flex items-center gap-1 text-xs text-n-slate-11">
              {{
                t(
                  `VIRTUAL_CLINIC.PEOPLE.STATUS.${(person.availability_status || 'offline').toUpperCase()}`
                )
              }}
              <span
                v-if="peopleOnMap.includes(person.id)"
                class="flex items-center gap-0.5 text-n-teal-11"
              >
                · <Icon icon="i-lucide-map-pin" class="size-3" />
                {{ t('VIRTUAL_CLINIC.PEOPLE.ON_MAP') }}
              </span>
            </span>
          </span>
        </button>
      </div>
    </div>
  </section>
</template>

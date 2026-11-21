<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// The clinic team, Gather-style: a search, then who is online and who is
// offline (each can be folded). Clicking someone opens the direct message;
// on yourself, your profile, with shortcuts to it and to your avatar.
defineProps({
  // User ids walking on the map right now.
  peopleOnMap: { type: Array, default: () => [] },
});
const emit = defineEmits(['editAvatar', 'editProfile']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const agents = useMapGetter('agents/getNonInternalAgents');
const currentUserId = useMapGetter('getCurrentUserID');

// Joined the account in the last two weeks: "Novo 🎉".
const NEW_FOR_SECONDS = 14 * 24 * 60 * 60;
const isNew = person =>
  person.joined_at && Date.now() / 1000 - person.joined_at < NEW_FOR_SECONDS;

const query = ref('');
const folded = ref({ online: false, offline: false });

// The AI user is left out: on the map it is Clara. You first, then by name.
const people = computed(() => {
  const search = query.value.trim().toLowerCase();
  return (agents.value || [])
    .filter(agent => !agent.is_ai_user)
    .filter(agent => !search || agent.name.toLowerCase().includes(search))
    .sort(
      (a, b) =>
        (b.id === currentUserId.value) - (a.id === currentUserId.value) ||
        a.name.localeCompare(b.name)
    );
});
// Busy counts as online: they are at work.
const groups = computed(() => [
  {
    key: 'online',
    people: people.value.filter(p => p.availability_status !== 'offline'),
  },
  {
    key: 'offline',
    people: people.value.filter(p => p.availability_status === 'offline'),
  },
]);

const open = async person => {
  if (person.id === currentUserId.value) {
    emit('editProfile');
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
</script>

<template>
  <div class="flex flex-col min-h-0 gap-2">
    <label
      class="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-n-alpha-2 text-n-slate-10"
    >
      <Icon icon="i-lucide-search" class="size-4 shrink-0" />
      <input
        v-model="query"
        type="search"
        :placeholder="t('VIRTUAL_CLINIC.PEOPLE.SEARCH')"
        class="w-full !h-auto !p-0 !m-0 text-sm !bg-transparent !border-0 !shadow-none !outline-none text-n-slate-12 placeholder:text-n-slate-10"
      />
    </label>

    <div class="flex flex-col min-h-0 gap-3 overflow-y-auto">
      <section
        v-for="group in groups"
        :key="group.key"
        class="flex flex-col gap-0.5"
      >
        <button
          type="button"
          class="flex items-center gap-1 px-1 py-0.5 text-xs font-medium text-left text-n-slate-11"
          @click="folded[group.key] = !folded[group.key]"
        >
          {{
            t(`VIRTUAL_CLINIC.PEOPLE.GROUPS.${group.key.toUpperCase()}`, {
              count: group.people.length,
            })
          }}
          <Icon
            :icon="
              folded[group.key]
                ? 'i-lucide-chevron-right'
                : 'i-lucide-chevron-down'
            "
            class="size-3.5"
          />
        </button>
        <template v-if="!folded[group.key]">
          <div v-for="person in group.people" :key="person.id" class="relative">
            <button
              type="button"
              class="flex items-center w-full gap-3 p-2 text-left rounded-lg hover:bg-n-alpha-2"
              :class="group.key === 'offline' ? 'py-1.5' : ''"
              @click="open(person)"
            >
              <Avatar
                :name="person.name"
                :src="person.thumbnail || ''"
                :status="person.availability_status"
                :size="group.key === 'online' ? 36 : 28"
                rounded-full
              />
              <span class="flex flex-col min-w-0">
                <span
                  class="flex items-center gap-1.5 text-sm truncate text-n-slate-12"
                  :class="group.key === 'online' ? 'font-medium' : ''"
                >
                  <span class="truncate">{{ person.name }}</span>
                  <span
                    v-if="person.id === currentUserId"
                    class="text-xs font-normal text-n-slate-11"
                  >
                    {{ t('VIRTUAL_CLINIC.PEOPLE.YOU') }}
                  </span>
                  <span
                    v-if="isNew(person)"
                    class="px-1.5 py-0.5 text-xxs font-medium rounded-full shrink-0 bg-n-iris-3 text-n-iris-11"
                  >
                    {{ t('VIRTUAL_CLINIC.PEOPLE.NEW') }}
                  </span>
                </span>
                <span
                  v-if="group.key === 'online'"
                  class="flex items-center gap-1 text-xs text-n-slate-11"
                >
                  {{
                    t(
                      `VIRTUAL_CLINIC.PEOPLE.STATUS.${person.availability_status.toUpperCase()}`
                    )
                  }}
                  <span
                    v-if="peopleOnMap.includes(person.id)"
                    class="flex items-center gap-0.5 text-n-teal-11"
                  >
                    <Icon icon="i-lucide-map-pin" class="size-3" />
                    {{ t('VIRTUAL_CLINIC.PEOPLE.ON_MAP') }}
                  </span>
                </span>
              </span>
            </button>
            <span
              v-if="person.id === currentUserId"
              class="absolute flex gap-0.5 -translate-y-1/2 top-1/2 right-1"
            >
              <Button
                icon="i-lucide-user-pen"
                variant="ghost"
                color="slate"
                size="xs"
                :title="t('VIRTUAL_CLINIC.PROFILE.TITLE')"
                @click="emit('editProfile')"
              />
              <Button
                icon="i-lucide-shirt"
                variant="ghost"
                color="slate"
                size="xs"
                :title="t('VIRTUAL_CLINIC.AVATAR.TITLE')"
                @click="emit('editAvatar')"
              />
            </span>
          </div>
        </template>
      </section>
    </div>
  </div>
</template>

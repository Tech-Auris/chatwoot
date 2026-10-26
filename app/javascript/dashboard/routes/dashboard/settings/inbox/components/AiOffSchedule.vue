<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import InboxAiScheduleAPI from 'dashboard/api/inboxAiSchedule';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// The hours in which the AI is off in this inbox: a patient message then
// goes to the chosen team, and the AI keeps the conversation as context.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();
const teams = useMapGetter('teams/getTeams');

const DAYS = [1, 2, 3, 4, 5, 6, 0];
const isSaving = ref(false);
const timezone = ref('');
const state = reactive({
  enabled: false,
  teamId: '',
  days: Object.fromEntries(DAYS.map(day => [day, []])),
});

const dayNames = computed(() => ({
  0: t('INBOX_MGMT.AI_SCHEDULE.DAYS.SUNDAY'),
  1: t('INBOX_MGMT.AI_SCHEDULE.DAYS.MONDAY'),
  2: t('INBOX_MGMT.AI_SCHEDULE.DAYS.TUESDAY'),
  3: t('INBOX_MGMT.AI_SCHEDULE.DAYS.WEDNESDAY'),
  4: t('INBOX_MGMT.AI_SCHEDULE.DAYS.THURSDAY'),
  5: t('INBOX_MGMT.AI_SCHEDULE.DAYS.FRIDAY'),
  6: t('INBOX_MGMT.AI_SCHEDULE.DAYS.SATURDAY'),
}));

const teamOptions = computed(() => [
  { value: '', label: t('INBOX_MGMT.AI_SCHEDULE.NO_TEAM') },
  ...(teams.value || []).map(team => ({ value: team.id, label: team.name })),
]);

const isValidRange = range => range.from && range.to && range.from < range.to;
const hasError = computed(
  () =>
    state.enabled &&
    DAYS.some(day => state.days[day].some(range => !isValidRange(range)))
);

const load = async () => {
  const { data } = await InboxAiScheduleAPI.show(props.inbox.id);
  state.enabled = data.enabled;
  state.teamId = data.team_id || '';
  timezone.value = data.timezone;
  DAYS.forEach(day => {
    state.days[day] = data.hours
      .filter(hour => hour.day_of_week === day)
      .map(({ from, to }) => ({ from, to }));
  });
};

const addRange = day => state.days[day].push({ from: '08:00', to: '12:00' });
const removeRange = (day, index) => state.days[day].splice(index, 1);

const save = async () => {
  isSaving.value = true;
  try {
    const hours = DAYS.flatMap(day =>
      state.days[day].map(range => ({ day_of_week: day, ...range }))
    );
    await InboxAiScheduleAPI.update(props.inbox.id, {
      enabled: state.enabled,
      teamId: state.teamId,
      hours,
    });
    useAlert(t('INBOX_MGMT.AI_SCHEDULE.SAVED'));
  } catch {
    useAlert(t('INBOX_MGMT.AI_SCHEDULE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(() => {
  store.dispatch('teams/get');
  load();
});
</script>

<template>
  <div class="mx-6 flex flex-col gap-6">
    <SettingsToggleSection
      v-model="state.enabled"
      :header="t('INBOX_MGMT.AI_SCHEDULE.TOGGLE')"
      :description="t('INBOX_MGMT.AI_SCHEDULE.TOGGLE_HELP')"
    />

    <template v-if="state.enabled">
      <SettingsFieldSection
        :label="t('INBOX_MGMT.AI_SCHEDULE.TEAM_LABEL')"
        :help-text="t('INBOX_MGMT.AI_SCHEDULE.TEAM_HELP')"
      >
        <Select v-model="state.teamId" :options="teamOptions" />
      </SettingsFieldSection>

      <div class="flex flex-col gap-1">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('INBOX_MGMT.AI_SCHEDULE.HOURS_TITLE') }}
        </span>
        <span class="text-body-main text-n-slate-11">
          {{ t('INBOX_MGMT.AI_SCHEDULE.HOURS_HELP', { timezone }) }}
        </span>
      </div>

      <div
        class="flex flex-col divide-y divide-n-weak outline outline-1 -outline-offset-1 outline-n-weak rounded-xl"
      >
        <div
          v-for="day in DAYS"
          :key="day"
          class="flex flex-wrap items-start gap-3 px-4 py-3"
        >
          <span class="w-32 pt-2 text-sm font-medium text-n-slate-12">
            {{ dayNames[day] }}
          </span>
          <div class="flex flex-col flex-1 gap-2">
            <span
              v-if="!state.days[day].length"
              class="pt-2 text-sm text-n-slate-11"
            >
              {{ t('INBOX_MGMT.AI_SCHEDULE.AI_ON_ALL_DAY') }}
            </span>
            <div
              v-for="(range, index) in state.days[day]"
              :key="index"
              class="flex items-center gap-2"
            >
              <input
                v-model="range.from"
                type="time"
                class="!mb-0 w-32 text-sm"
                :aria-label="t('INBOX_MGMT.AI_SCHEDULE.FROM')"
              />
              <span class="text-sm text-n-slate-11">
                {{ t('INBOX_MGMT.AI_SCHEDULE.TO') }}
              </span>
              <input
                v-model="range.to"
                type="time"
                class="!mb-0 w-32 text-sm"
                :aria-label="t('INBOX_MGMT.AI_SCHEDULE.TO')"
              />
              <NextButton
                v-tooltip.top="t('INBOX_MGMT.AI_SCHEDULE.REMOVE_RANGE')"
                icon="i-lucide-trash-2"
                ruby
                ghost
                xs
                @click="removeRange(day, index)"
              />
              <span v-if="!isValidRange(range)" class="text-xs text-n-ruby-11">
                {{ t('INBOX_MGMT.AI_SCHEDULE.INVALID_RANGE') }}
              </span>
            </div>
          </div>
          <NextButton
            :label="t('INBOX_MGMT.AI_SCHEDULE.ADD_RANGE')"
            icon="i-lucide-plus"
            slate
            faded
            xs
            @click="addRange(day)"
          />
        </div>
      </div>
    </template>

    <div class="flex justify-end pb-4">
      <NextButton
        :label="t('INBOX_MGMT.AI_SCHEDULE.SAVE')"
        :is-loading="isSaving"
        :disabled="hasError"
        @click="save"
      />
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import PipelinesAPI from 'dashboard/api/pipelines';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Pipeline selector at the top of the Funil: the Agendamento first (the
// default, always what opens), then the clinic pipelines with the number of
// contacts in progress, searchable. Administrators and managers also create
// pipelines here and bring archived ones back.
const props = defineProps({
  // null = Agendamento
  modelValue: { type: Number, default: null },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'create']);

const { t } = useI18n();
const store = useStore();
const pipelines = useMapGetter('pipelines/getPipelines');

const search = ref('');
const showArchived = ref(false);
const archived = ref([]);
const popoverRef = ref(null);

const selectedName = computed(() => {
  if (!props.modelValue) return t('PIPELINES.AGENDAMENTO');
  return (
    pipelines.value.find(pipeline => pipeline.id === props.modelValue)?.name ||
    t('PIPELINES.AGENDAMENTO')
  );
});

const matches = list => {
  const query = search.value.trim().toLowerCase();
  if (!query) return list;
  return list.filter(item => item.name.toLowerCase().includes(query));
};

const filteredPipelines = computed(() => matches(pipelines.value));
const filteredArchived = computed(() => matches(archived.value));

const select = (id, hide) => {
  emit('update:modelValue', id);
  hide();
};

const onShow = () => {
  search.value = '';
  showArchived.value = false;
};

const toggleArchived = async () => {
  showArchived.value = !showArchived.value;
  if (!showArchived.value) return;
  const { data } = await PipelinesAPI.get({ archived: true });
  archived.value = data?.payload || [];
};

const unarchive = async pipeline => {
  try {
    await PipelinesAPI.unarchive(pipeline.id);
    archived.value = archived.value.filter(item => item.id !== pipeline.id);
    await store.dispatch('pipelines/get', { force: true });
    useAlert(t('PIPELINES.SELECTOR.UNARCHIVED', { pipeline: pipeline.name }));
  } catch (error) {
    useAlert(t('PIPELINES.CONFIG.ERROR'));
  }
};

const create = hide => {
  hide();
  emit('create');
};
</script>

<template>
  <Popover ref="popoverRef" align="start" @show="onShow">
    <button
      type="button"
      class="inline-flex items-center gap-2 h-9 px-3 rounded-lg text-sm font-medium bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
    >
      <span v-if="!modelValue" class="i-lucide-lock size-3.5 text-n-slate-11" />
      <span class="max-w-60 truncate">{{ selectedName }}</span>
      <span class="i-lucide-chevron-down size-4 text-n-slate-11" />
    </button>
    <template #content="{ hide }">
      <div class="flex flex-col w-72 max-h-96 py-2">
        <div class="px-2 pb-1">
          <input
            v-model="search"
            type="search"
            :placeholder="t('PIPELINES.SEARCH')"
            class="reset-base w-full h-8 px-2 text-sm border-none rounded-lg bg-n-alpha-black2 text-n-slate-12 focus:outline-none"
          />
        </div>
        <div class="flex flex-col overflow-y-auto px-1">
          <button
            type="button"
            class="flex items-center gap-2 h-8 px-2 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-1"
            :class="{ 'bg-n-alpha-1': !modelValue }"
            @click="select(null, hide)"
          >
            <span class="i-lucide-lock size-3.5 text-n-slate-11" />
            <span class="flex-1 truncate text-start">
              {{ t('PIPELINES.AGENDAMENTO') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('PIPELINES.SELECTOR.DEFAULT') }}
            </span>
          </button>
          <div class="h-px my-1 bg-n-weak" />
          <template v-if="!showArchived">
            <button
              v-for="pipeline in filteredPipelines"
              :key="pipeline.id"
              type="button"
              class="flex items-center gap-2 h-8 px-2 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-1"
              :class="{ 'bg-n-alpha-1': modelValue === pipeline.id }"
              @click="select(pipeline.id, hide)"
            >
              <span class="flex-1 truncate text-start">{{
                pipeline.name
              }}</span>
              <span class="text-xs text-n-slate-11">
                {{ pipeline.entries_count }}
              </span>
            </button>
            <p
              v-if="!filteredPipelines.length"
              class="px-2 py-1.5 mb-0 text-xs text-n-slate-11"
            >
              {{
                pipelines.length
                  ? t('PIPELINES.ADD_TO.NO_MATCH')
                  : t('PIPELINES.SELECTOR.EMPTY')
              }}
            </p>
          </template>
          <template v-else>
            <div
              v-for="pipeline in filteredArchived"
              :key="pipeline.id"
              class="flex items-center gap-2 h-8 px-2 text-sm text-n-slate-11"
            >
              <span class="i-lucide-archive size-3.5" />
              <span class="flex-1 truncate">{{ pipeline.name }}</span>
              <Button
                :label="t('PIPELINES.SELECTOR.UNARCHIVE')"
                link
                xs
                @click="unarchive(pipeline)"
              />
            </div>
            <p
              v-if="!filteredArchived.length"
              class="px-2 py-1.5 mb-0 text-xs text-n-slate-11"
            >
              {{ t('PIPELINES.SELECTOR.NO_ARCHIVED') }}
            </p>
          </template>
        </div>
        <div
          v-if="canManage"
          class="flex items-center justify-between gap-2 px-2 pt-2 mt-1 border-t border-n-weak"
        >
          <Button
            :label="t('PIPELINES.SELECTOR.NEW')"
            icon="i-lucide-plus"
            ghost
            sm
            @click="create(hide)"
          />
          <Button
            :label="
              showArchived
                ? t('PIPELINES.SELECTOR.HIDE_ARCHIVED')
                : t('PIPELINES.SELECTOR.SHOW_ARCHIVED')
            "
            slate
            link
            xs
            @click="toggleArchived"
          />
        </div>
      </div>
    </template>
  </Popover>
</template>

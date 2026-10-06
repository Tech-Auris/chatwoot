<script setup>
import { computed } from 'vue';

// Same picker as the secretary inboxes in Super Admin: chips for the picked
// inboxes, a list with the rest. No inbox picked means every inbox,
// including the ones created later.
const props = defineProps({
  inboxes: {
    type: Array,
    default: () => [],
  },
});

const selectedIds = defineModel({ type: Array, default: () => [] });

const selectedInboxes = computed(() =>
  props.inboxes.filter(inbox => selectedIds.value.includes(inbox.id))
);
const availableInboxes = computed(() =>
  props.inboxes.filter(inbox => !selectedIds.value.includes(inbox.id))
);

const addInbox = event => {
  const id = Number(event.target.value);
  if (id) selectedIds.value = [...selectedIds.value, id];
  event.target.value = '';
};
const removeInbox = id => {
  selectedIds.value = selectedIds.value.filter(selected => selected !== id);
};
const selectAll = () => {
  selectedIds.value = props.inboxes.map(inbox => inbox.id);
};
const clearAll = () => {
  selectedIds.value = [];
};
</script>

<template>
  <div class="flex flex-col gap-2 mb-4">
    <div
      class="flex flex-wrap items-center gap-2 min-h-11 p-2 border border-n-weak rounded-lg bg-n-alpha-black2"
    >
      <span
        v-for="inbox in selectedInboxes"
        :key="inbox.id"
        class="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-n-slate-3 text-sm text-n-slate-12"
      >
        {{ inbox.name }}
        <button
          type="button"
          class="text-n-slate-11 hover:text-n-slate-12"
          :aria-label="
            $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.REMOVE', {
              name: inbox.name,
            })
          "
          @click="removeInbox(inbox.id)"
        >
          <span class="i-lucide-x size-3.5 block" />
        </button>
      </span>
      <span v-if="!selectedInboxes.length" class="text-sm text-n-slate-11 px-1">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.PLACEHOLDER') }}
      </span>
      <select
        v-if="availableInboxes.length"
        class="flex-1 min-w-48 !mb-0 !border-0 !bg-transparent !h-auto !py-1 text-sm text-n-slate-11"
        @change="addInbox"
      >
        <option value="">
          {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.ADD') }}
        </option>
        <option
          v-for="inbox in availableInboxes"
          :key="inbox.id"
          :value="inbox.id"
        >
          {{ inbox.name }}
        </option>
      </select>
    </div>
    <div class="flex items-center gap-4 text-sm">
      <button type="button" class="text-n-brand" @click="selectAll">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.SELECT_ALL') }}
      </button>
      <button type="button" class="text-n-brand" @click="clearAll">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.CLEAR') }}
      </button>
    </div>
    <p class="text-xs text-n-slate-11 m-0">
      {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.HELP') }}
    </p>
  </div>
</template>

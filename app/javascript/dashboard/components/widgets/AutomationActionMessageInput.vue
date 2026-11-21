<script setup>
import { computed } from 'vue';

import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AutomationActionTemplateFallback from './AutomationActionTemplateFallback.vue';

// `send_message` params: `[text]` or `[text, template_params]`.
const props = defineProps({
  modelValue: {
    type: [Array, String],
    default: () => [],
  },
  conditions: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const params = computed(() => [props.modelValue].flat());

const templateParams = computed(() => params.value[1] || null);

const update = (text, template) => {
  emit('update:modelValue', template ? [text, template] : [text]);
};

const content = computed({
  get: () => (typeof params.value[0] === 'string' ? params.value[0] : ''),
  set: value => update(value, templateParams.value),
});

const onTemplateChange = (value, message) => {
  update(content.value.trim() ? content.value : message || '', value);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <WootMessageEditor
      v-model="content"
      rows="4"
      enable-variables
      :placeholder="$t('AUTOMATION.ACTION.TEAM_MESSAGE_INPUT_PLACEHOLDER')"
      class="[&_.ProseMirror-menubar]:hidden px-3 py-1 bg-n-alpha-1 rounded-lg outline outline-1 outline-n-weak dark:outline-n-strong"
    />
    <AutomationActionTemplateFallback
      :model-value="templateParams"
      :conditions="conditions"
      @update:model-value="onTemplateChange"
    />
  </div>
</template>

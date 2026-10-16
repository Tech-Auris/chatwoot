<script setup>
import { ref, onMounted } from 'vue';
import Icon from 'next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const { attachment, fullWidth } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  // Large picture spanning the bubble, used when the image has a caption
  fullWidth: {
    type: Boolean,
    default: false,
  },
});

const showGallery = ref(false);

const { filteredCurrentChatAttachments } = useMessageContext();

const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
  type: 'image',
});

onMounted(() => {
  if (attachment.dataUrl) {
    loadWithRetry(attachment.dataUrl);
  }
});

const handleError = () => {
  hasError.value = true;
};
</script>

<template>
  <div
    class="overflow-hidden contain-content cursor-pointer"
    :class="fullWidth ? 'w-full rounded-lg' : 'size-[72px] rounded-xl'"
    @click="showGallery = true"
  >
    <div
      v-if="hasError"
      class="flex flex-col items-center justify-center gap-1 text-xs text-center rounded-lg size-full bg-n-alpha-1 text-n-slate-11"
      :class="{ 'h-24': fullWidth }"
    >
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
    </div>
    <img
      v-else-if="isLoaded"
      class="w-full skip-context-menu"
      :class="fullWidth ? 'h-auto' : 'object-cover h-full'"
      :src="attachment.dataUrl"
      :width="fullWidth ? attachment.width : undefined"
      :height="fullWidth ? attachment.height : undefined"
      @error="handleError"
    />
    <div
      v-else
      class="flex items-center justify-center rounded-lg size-full bg-n-alpha-1"
      :class="{ 'h-48': fullWidth }"
    >
      <Spinner class="text-n-slate-11" />
    </div>
  </div>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="handleError"
    @close="() => (showGallery = false)"
  />
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const emit = defineEmits(['add', 'import', 'export']);

const { t } = useI18n();

const { isAdmin, isManager } = useAdmin();

// Moving the whole contact base in or out is not an agent's to do, and the API
// refuses it. Offering the option anyway only produced a failed request.
const canMoveContactList = computed(() => isAdmin.value || isManager.value);

const contactMenuItems = computed(() =>
  [
    {
      label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'),
      action: 'add',
      value: 'add',
      icon: 'i-lucide-plus',
    },
    canMoveContactList.value && {
      label: t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
      ),
      action: 'export',
      value: 'export',
      icon: 'i-lucide-upload',
    },
    canMoveContactList.value && {
      label: t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
      ),
      action: 'import',
      value: 'import',
      icon: 'i-lucide-download',
    },
  ].filter(Boolean)
);
const showActionsDropdown = ref(false);

const handleContactAction = ({ action }) => {
  if (action === 'add') {
    emit('add');
  } else if (action === 'import') {
    emit('import');
  } else if (action === 'export') {
    emit('export');
  }
};
</script>

<template>
  <div v-on-clickaway="() => (showActionsDropdown = false)" class="relative">
    <Button
      icon="i-lucide-ellipsis-vertical"
      color="slate"
      variant="ghost"
      size="sm"
      :class="showActionsDropdown ? 'bg-n-alpha-2' : ''"
      @click="showActionsDropdown = !showActionsDropdown"
    />
    <DropdownMenu
      v-if="showActionsDropdown"
      :menu-items="contactMenuItems"
      class="ltr:right-0 rtl:left-0 mt-1 w-52 top-full"
      @action="handleContactAction($event)"
    />
  </div>
</template>

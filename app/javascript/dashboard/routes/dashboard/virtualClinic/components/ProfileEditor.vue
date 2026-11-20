<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { sheetForUser } from '../engine/layout';
import { useAvatarArt } from '../composables/useAvatarArt';

// Gather-style "Edit profile" from the clinic: the profile picture, the
// avatar on the map and the names. It saves the same profile as Settings →
// Profile.
const props = defineProps({
  // The look on the map (`{ sheet }` or the parts), null when never edited.
  avatar: { type: Object, default: null },
});
const emit = defineEmits(['close', 'editAvatar']);

const { t } = useI18n();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const { thumbnail } = useAvatarArt();

const dialog = ref(null);
const name = ref(currentUser.value.name || '');
const displayName = ref(currentUser.value.display_name || '');
const photo = ref(null);
const photoUrl = ref(currentUser.value.avatar_url || '');
const saving = ref(false);
const fileInput = ref(null);

const look = computed(
  () => props.avatar || { sheet: sheetForUser(currentUser.value.id) }
);

const pickPhoto = event => {
  const [file] = event.target.files;
  if (!file) return;
  photo.value = file;
  photoUrl.value = URL.createObjectURL(file);
};

const removePhoto = async () => {
  await store.dispatch('deleteAvatar');
  photo.value = null;
  photoUrl.value = '';
};

const save = async () => {
  if (!name.value.trim()) return;
  saving.value = true;
  try {
    await store.dispatch('updateProfile', {
      name: name.value.trim(),
      displayName: displayName.value.trim(),
      avatar: photo.value,
    });
    useAlert(t('VIRTUAL_CLINIC.PROFILE.SAVED'));
    dialog.value.close();
  } catch {
    useAlert(t('VIRTUAL_CLINIC.PROFILE.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const editAvatar = () => {
  emit('editAvatar');
  dialog.value.close();
};

onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  if (photo.value) URL.revokeObjectURL(photoUrl.value);
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="md"
    :title="t('VIRTUAL_CLINIC.PROFILE.TITLE')"
    :confirm-button-label="t('VIRTUAL_CLINIC.PROFILE.SAVE')"
    :is-loading="saving"
    :disable-confirm-button="!name.trim()"
    @confirm="save"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-5">
      <div class="flex justify-around">
        <div class="flex flex-col items-center gap-2">
          <span class="text-sm text-n-slate-12">
            {{ t('VIRTUAL_CLINIC.PROFILE.PHOTO') }}
          </span>
          <div class="relative">
            <Avatar
              :name="name || currentUser.name"
              :src="photoUrl"
              :size="96"
              rounded-full
            />
            <Button
              v-if="photoUrl"
              type="button"
              icon="i-lucide-trash-2"
              color="ruby"
              size="xs"
              class="absolute top-0 -right-2"
              :title="t('VIRTUAL_CLINIC.PROFILE.REMOVE_PHOTO')"
              @click="removePhoto"
            />
            <Button
              type="button"
              icon="i-lucide-pencil"
              color="slate"
              variant="faded"
              size="xs"
              class="absolute bottom-0 -right-2"
              :title="t('VIRTUAL_CLINIC.PROFILE.CHANGE_PHOTO')"
              @click="fileInput.click()"
            />
            <input
              ref="fileInput"
              type="file"
              accept="image/png, image/jpeg, image/gif"
              class="hidden"
              @change="pickPhoto"
            />
          </div>
        </div>
        <div class="flex flex-col items-center gap-2">
          <span class="text-sm text-n-slate-12">
            {{ t('VIRTUAL_CLINIC.PROFILE.AVATAR') }}
          </span>
          <div class="relative">
            <div
              class="grid overflow-hidden rounded-full size-24 place-items-center bg-n-alpha-2"
            >
              <img
                v-if="thumbnail(look)"
                :src="thumbnail(look)"
                alt=""
                class="w-10 [image-rendering:pixelated]"
              />
            </div>
            <Button
              type="button"
              icon="i-lucide-pencil"
              color="slate"
              variant="faded"
              size="xs"
              class="absolute bottom-0 -right-2"
              :title="t('VIRTUAL_CLINIC.AVATAR.TITLE')"
              @click="editAvatar"
            />
          </div>
        </div>
      </div>
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('VIRTUAL_CLINIC.PROFILE.NAME') }}
        <input
          v-model="name"
          maxlength="255"
          class="px-3 py-2 !mb-0 text-sm border rounded-lg border-n-weak bg-n-solid-2"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('VIRTUAL_CLINIC.PROFILE.DISPLAY_NAME') }}
        <input
          v-model="displayName"
          maxlength="255"
          :placeholder="name"
          class="px-3 py-2 !mb-0 text-sm border rounded-lg border-n-weak bg-n-solid-2"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('VIRTUAL_CLINIC.PROFILE.DISPLAY_NAME_HINT') }}
        </span>
      </label>
    </div>
  </Dialog>
</template>

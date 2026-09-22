<script>
import validations from './helpers/validations';
import FormInput from 'v3/components/Form/Input.vue';
import { reactive } from 'vue';
import { useVuelidate } from '@vuelidate/core';

import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
    FormInput,
  },
  props: {
    onSubmit: {
      type: Function,
      default: () => {},
    },
    submitInProgress: {
      type: Boolean,
      default: false,
    },
    formData: {
      type: Object,
      default: () => {},
    },
    submitButtonText: {
      type: String,
      default: '',
    },
  },
  setup(props) {
    const formData = props.formData || {};
    const {
      description = '',
      name: title = '',
      allow_auto_assign: allowAutoAssign = true,
      auto_assign_include_offline: autoAssignIncludeOffline = false,
    } = formData;

    const state = reactive({
      description,
      title,
      allowAutoAssign,
      // Mirrors the boolean but kept as a string ("online" | "all") so
      // the two radio buttons bind directly. Converted back on submit.
      autoAssignScope: autoAssignIncludeOffline ? 'all' : 'online',
    });

    const rules = validations;
    const v$ = useVuelidate(rules, state);
    return { state, v$ };
  },
  methods: {
    handleSubmit() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }
      this.onSubmit({
        description: this.state.description,
        name: this.state.title,
        allow_auto_assign: this.state.allowAutoAssign,
        auto_assign_include_offline:
          this.state.allowAutoAssign && this.state.autoAssignScope === 'all',
      });
    },
  },
};
</script>

<template>
  <div class="flex-shrink-0 w-full">
    <form class="mx-0 grid gap-4" @submit.prevent="handleSubmit">
      <FormInput
        v-model="state.title"
        name="title"
        spacing="compact"
        :label="$t('TEAMS_SETTINGS.FORM.NAME.LABEL')"
        :placeholder="$t('TEAMS_SETTINGS.FORM.NAME.PLACEHOLDER')"
        :has-error="v$.title.$error"
        :error-message="v$.title.$error ? v$.title.$errors[0].$message : ''"
        @blur="v$.title.$touch"
      />
      <FormInput
        v-model="state.description"
        name="description"
        spacing="compact"
        :label="$t('TEAMS_SETTINGS.FORM.DESCRIPTION.LABEL')"
        :placeholder="$t('TEAMS_SETTINGS.FORM.DESCRIPTION.PLACEHOLDER')"
        :has-error="v$.description.$error"
        :error-message="
          v$.description.$error ? v$.description.$errors[0].$message : ''
        "
        @blur="v$.description.$touch"
      />
      <div class="w-full flex items-center gap-2">
        <input v-model="state.allowAutoAssign" type="checkbox" :value="true" />
        <label for="conversation_creation">
          {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.LABEL') }}
        </label>
      </div>
      <!-- Scope of the auto-assignment: kept out of the DOM when the
           parent checkbox is off, so the info block just below reads
           the "disabled" copy without radio noise around it. -->
      <div v-if="state.allowAutoAssign" class="w-full flex flex-col gap-2 pl-6">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="state.autoAssignScope" type="radio" value="online" />
          {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.SCOPE_ONLINE') }}
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="state.autoAssignScope" type="radio" value="all" />
          {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.SCOPE_ALL') }}
        </label>
      </div>
      <div
        class="w-full flex gap-3 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-alpha-1"
      >
        <span class="i-lucide-info shrink-0 w-5 h-5 text-n-slate-11 mt-0.5" />
        <div class="flex flex-col gap-2 text-sm text-n-slate-11">
          <span class="text-n-slate-12 font-medium">
            {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.INFO_TITLE') }}
          </span>
          <template v-if="state.allowAutoAssign">
            <p v-if="state.autoAssignScope === 'online'" class="m-0">
              {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.INFO_BODY_SCOPE_ONLINE') }}
            </p>
            <p v-else class="m-0">
              {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.INFO_BODY_SCOPE_ALL') }}
            </p>
          </template>
          <p v-else class="m-0">
            {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.INFO_BODY_DISABLED') }}
          </p>
        </div>
      </div>
      <div class="flex flex-row justify-end gap-2 py-2 px-0 w-full">
        <div class="w-full">
          <NextButton
            type="submit"
            :label="submitButtonText"
            :disabled="v$.title.$invalid || submitInProgress"
            :is-loading="submitInProgress"
          />
        </div>
      </div>
    </form>
  </div>
</template>

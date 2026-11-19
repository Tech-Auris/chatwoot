import { ref } from 'vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';

// The config only changes when an admin flips a switch elsewhere, so the map
// page and the chat list share one fetch per account while the app is open.
const configs = ref({});

export function useVirtualClinicConfig() {
  const load = async accountId => {
    if (!configs.value[accountId]) {
      const { data } = await VirtualClinicAPI.getConfig();
      configs.value = { ...configs.value, [accountId]: data.ai_team };
    }
    return configs.value[accountId];
  };

  return { configs, load };
}

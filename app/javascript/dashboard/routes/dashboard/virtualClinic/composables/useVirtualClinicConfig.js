import { ref } from 'vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';

// Shared by the map page and the chat list. Fetched again every time a page
// opens: the admin may have just turned the AI assistant on or saved the
// OpenAI key in another screen.
const configs = ref({});

export function useVirtualClinicConfig() {
  const load = async accountId => {
    const { data } = await VirtualClinicAPI.getConfig();
    configs.value = { ...configs.value, [accountId]: data.ai_team };
    return data.ai_team;
  };

  return { configs, load };
}

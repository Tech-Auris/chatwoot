import { onBeforeUnmount, ref, watch } from 'vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';

const POLL_MS = 30000;

// What the AI team is doing now. Polls while the page is visible and the user
// sees the AI team (no OpenAI key needed); the server caches it for 30 s.
export function useVirtualClinicStatus(enabled) {
  const status = ref(null);
  let timer = null;

  const fetchStatus = async () => {
    if (document.hidden) return;
    const { data } = await VirtualClinicAPI.getStatus();
    status.value = data;
  };

  const stop = () => {
    clearInterval(timer);
    timer = null;
  };

  watch(
    enabled,
    on => {
      stop();
      if (!on) return;
      fetchStatus();
      timer = setInterval(fetchStatus, POLL_MS);
    },
    { immediate: true }
  );

  onBeforeUnmount(stop);
  return { status };
}

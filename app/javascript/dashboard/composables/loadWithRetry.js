import { ref } from 'vue';

export const useLoadWithRetry = (config = {}) => {
  const maxRetry = config.maxRetry || 3;
  const backoff = config.backoff || 1000;
  const type = config.type || '';

  const isLoaded = ref(false);
  const hasError = ref(false);

  // `source` is either a URL or a function returning one. The function form
  // exists for media whose URL must differ per attempt: an ActiveStorage
  // redirect that a cache already resolved to an expired target would fail
  // every retry identically if the same URL were reused.
  const loadWithRetry = async source => {
    const attemptLoad = async () => {
      const url = typeof source === 'function' ? source() : source;
      return new Promise((resolve, reject) => {
        let media;
        if (type === 'image') {
          media = new Image();
          media.onload = () => resolve();
          media.onerror = () => reject(new Error('Failed to load image'));
        } else if (type === 'audio') {
          media = new Audio();
          media.onloadedmetadata = () => resolve();
          media.onerror = () => reject(new Error('Failed to load audio'));
        } else if (type === 'video') {
          media = document.createElement('video');
          media.preload = 'metadata';
          media.onloadedmetadata = () => resolve();
          media.onerror = () => reject(new Error('Failed to load video'));
        } else {
          fetch(url)
            .then(res => {
              if (res.ok) resolve();
              else reject(new Error('Failed to load resource'));
            })
            .catch(err => reject(err));
          return;
        }
        media.src = url;
      });
    };

    const sleep = ms => {
      return new Promise(resolve => {
        setTimeout(resolve, ms);
      });
    };

    const retry = async (attempt = 0) => {
      try {
        await attemptLoad();
        hasError.value = false;
        isLoaded.value = true;
      } catch (error) {
        if (attempt + 1 >= maxRetry) {
          hasError.value = true;
          isLoaded.value = false;
          return;
        }
        await sleep(backoff * (attempt + 1));
        await retry(attempt + 1);
      }
    };

    await retry();
  };

  return {
    isLoaded,
    hasError,
    loadWithRetry,
  };
};

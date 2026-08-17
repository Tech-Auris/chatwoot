import { useLoadWithRetry } from '../loadWithRetry';

describe('useLoadWithRetry', () => {
  let created;

  // Stubs the media element the composable builds internally so a test can
  // decide, per attempt, whether the load succeeds.
  const stubMedia = outcomes => {
    created = [];
    global.Audio = class {
      constructor() {
        this.handlers = {};
        created.push(this);
      }

      set src(value) {
        this.url = value;
        const succeeds = outcomes[created.length - 1];
        setTimeout(() => {
          if (succeeds) this.onloadedmetadata?.();
          else this.onerror?.();
        }, 0);
      }
    };
  };

  afterEach(() => {
    delete global.Audio;
  });

  it('loads a plain URL', async () => {
    stubMedia([true]);
    const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
      type: 'audio',
    });

    await loadWithRetry('https://example.com/audio.mp3');

    expect(isLoaded.value).toBe(true);
    expect(hasError.value).toBe(false);
    expect(created[0].url).toBe('https://example.com/audio.mp3');
  });

  // The whole point of the function form: an expired URL sitting in an HTTP
  // cache fails identically on every retry unless each attempt asks for a
  // different one.
  it('asks the source function for a new URL on every attempt', async () => {
    stubMedia([false, false, true]);
    let attempt = 0;
    const { isLoaded, loadWithRetry } = useLoadWithRetry({
      type: 'audio',
      backoff: 1,
    });

    await loadWithRetry(() => {
      attempt += 1;
      return `https://example.com/audio.mp3?t=${attempt}`;
    });

    expect(created.map(media => media.url)).toEqual([
      'https://example.com/audio.mp3?t=1',
      'https://example.com/audio.mp3?t=2',
      'https://example.com/audio.mp3?t=3',
    ]);
    expect(isLoaded.value).toBe(true);
  });

  it('gives up after the configured number of attempts', async () => {
    stubMedia([false, false, false]);
    const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
      type: 'audio',
      backoff: 1,
    });

    await loadWithRetry(() => 'https://example.com/audio.mp3');

    expect(hasError.value).toBe(true);
    expect(isLoaded.value).toBe(false);
    expect(created).toHaveLength(3);
  });
});

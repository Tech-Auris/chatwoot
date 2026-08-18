import campaignsAPI from '../campaigns';
import ApiClient from '../ApiClient';

describe('#CampaignsAPI', () => {
  it('creates correct instance', () => {
    expect(campaignsAPI).toBeInstanceOf(ApiClient);
    expect(campaignsAPI).toHaveProperty('get');
    expect(campaignsAPI).toHaveProperty('create');
    expect(campaignsAPI).toHaveProperty('importAudience');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = { post: vi.fn(() => Promise.resolve()) };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    // The auth headers live on the configured global instance. Importing the
    // bare axios module here compiles fine and 401s on every request, which is
    // what this guards against.
    it('posts the audience file through the configured axios', () => {
      const file = new File(['id,name,email,phone_number'], 'audiencia.csv', {
        type: 'text/csv',
      });

      campaignsAPI.importAudience(file);

      expect(axiosMock.post).toHaveBeenCalledTimes(1);
      const [url, formData, config] = axiosMock.post.mock.calls[0];
      expect(url).toContain('/campaigns/import_audience');
      expect(formData.get('file')).toBe(file);
      expect(config.headers['Content-Type']).toBe('multipart/form-data');
    });
  });
});

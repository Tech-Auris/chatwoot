import virtualClinic from '../virtualClinic';

describe('#VirtualClinicAPI', () => {
  const originalAxios = window.axios;
  const png = new Blob(['png']);
  const axiosMock = {
    get: vi.fn(url =>
      Promise.resolve({
        data: url.endsWith('/config') ? { assets_version: '1764000000' } : png,
      })
    ),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    virtualClinic.assetsVersion = undefined;
    axiosMock.get.mockClear();
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('puts the art version in the art URL', async () => {
    await virtualClinic.getConfig();

    const data = await virtualClinic.getAsset('1_recepcao/relogio.png');

    expect(data).toBe(png);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v2/virtual_clinic/assets/1_recepcao/relogio.png',
      { params: { v: '1764000000' }, responseType: 'blob' }
    );
  });

  it('fetches the version first when the art loads before the config', async () => {
    await virtualClinic.getAsset('1_recepcao/relogio.png');

    expect(axiosMock.get).toHaveBeenCalledWith('/api/v2/virtual_clinic/config');
    expect(axiosMock.get).toHaveBeenLastCalledWith(
      '/api/v2/virtual_clinic/assets/1_recepcao/relogio.png',
      { params: { v: '1764000000' }, responseType: 'blob' }
    );
  });
});

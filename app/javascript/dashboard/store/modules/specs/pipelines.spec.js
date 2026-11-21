import axios from 'axios';
import { actions, getters } from '../pipelines';
import types from '../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('#pipelines', () => {
  const commit = vi.fn();

  beforeEach(() => {
    commit.mockClear();
    axios.get.mockReset();
  });

  it('loads the pipelines once', async () => {
    axios.get.mockResolvedValue({
      data: { payload: [{ id: 1, name: 'Retorno' }] },
    });

    await actions.get({ commit, state: { uiFlags: { isFetched: false } } });
    await actions.get({ commit, state: { uiFlags: { isFetched: true } } });

    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(commit).toHaveBeenCalledWith(types.SET_PIPELINES, [
      { id: 1, name: 'Retorno' },
    ]);
  });

  it('reloads when forced, after a pipeline changed', async () => {
    axios.get.mockResolvedValue({ data: { payload: [] } });

    await actions.get(
      { commit, state: { uiFlags: { isFetched: true } } },
      { force: true }
    );

    expect(axios.get).toHaveBeenCalledTimes(1);
  });

  it('leaves the list empty when the account has no funnel', async () => {
    axios.get.mockRejectedValue(new Error('403'));

    await actions.get({ commit, state: { uiFlags: { isFetched: false } } });

    expect(commit).toHaveBeenCalledWith(types.SET_PIPELINES, []);
  });

  it('finds a pipeline by id', () => {
    const state = { records: [{ id: 1 }, { id: 2 }] };

    expect(getters.getPipeline(state)(2)).toEqual({ id: 2 });
  });
});

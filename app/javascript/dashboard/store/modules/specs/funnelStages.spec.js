import axios from 'axios';
import { actions, getters, mutations } from '../funnelStages';
import types from '../../mutation-types';

// The API clients talk to the configured global axios, not the imported module.
global.axios = axios;
vi.mock('axios');

describe('#funnelStages', () => {
  const commit = vi.fn();

  beforeEach(() => {
    commit.mockClear();
    axios.get.mockReset();
  });

  it('keeps only the active stages', async () => {
    axios.get.mockResolvedValue({
      data: {
        payload: [
          { id: 1, name: 'Novo Contato', active: true },
          { id: 2, name: 'Desativada', active: false },
        ],
      },
    });

    await actions.get({
      commit,
      state: { uiFlags: { isFetched: false, isFetching: false } },
    });

    expect(commit).toHaveBeenCalledWith(types.SET_FUNNEL_STAGES, [
      { id: 1, name: 'Novo Contato', active: true },
    ]);
  });

  // The badge mounts on every conversation opened; without this guard each one
  // would fetch the same list again.
  it('does not fetch again once the list is loaded', async () => {
    await actions.get({
      commit,
      state: { uiFlags: { isFetched: true, isFetching: false } },
    });

    expect(axios.get).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
  });

  // An account without the funnel answers 403 here, and that must leave the
  // screen usable rather than stuck loading.
  it('settles the flags when the request fails', async () => {
    axios.get.mockRejectedValue(new Error('Forbidden'));

    await actions.get({
      commit,
      state: { uiFlags: { isFetched: false, isFetching: false } },
    });

    expect(commit).toHaveBeenLastCalledWith(types.SET_FUNNEL_STAGES_UI_FLAG, {
      isFetching: false,
      isFetched: true,
    });
  });

  it('exposes the stages through the getter', () => {
    const state = { records: [{ id: 1 }] };

    expect(getters.getFunnelStages(state)).toEqual([{ id: 1 }]);
  });

  it('stores the fetched stages', () => {
    const state = { records: [] };

    mutations[types.SET_FUNNEL_STAGES](state, [{ id: 3 }]);

    expect(state.records).toEqual([{ id: 3 }]);
  });
});

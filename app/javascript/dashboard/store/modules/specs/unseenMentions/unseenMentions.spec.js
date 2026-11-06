import axios from 'axios';
import { actions, getters, mutations } from '../../unseenMentions';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('unseenMentions', () => {
  beforeEach(() => {
    commit.mockClear();
  });

  it('fetches the unseen mentions', async () => {
    const payload = [
      {
        conversation_id: 12,
        mentioned_at: 1,
        mentioned_by: { id: 3, name: 'Daniel' },
      },
    ];
    axios.get.mockResolvedValue({ data: { payload } });

    await actions.get({ commit });

    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/mentions/unseen')
    );
    expect(commit).toHaveBeenCalledWith('SET_UNSEEN_MENTIONS', payload);
  });

  it('keys mentions by conversation and counts them', () => {
    const state = { records: {} };
    mutations.SET_UNSEEN_MENTIONS(state, [
      {
        conversation_id: 12,
        mentioned_at: 1,
        mentioned_by: { id: 3, name: 'Daniel' },
      },
      { conversation_id: 15, mentioned_at: 2, mentioned_by: null },
    ]);

    expect(getters.getCount(state)).toBe(2);
    expect(getters.getByConversation(state)(12).mentionedBy.name).toBe(
      'Daniel'
    );
    expect(getters.getByConversation(state)(99)).toBeNull();
  });

  it('drops a conversation once it is seen', () => {
    const state = { records: { 12: {}, 15: {} } };
    mutations.REMOVE_UNSEEN_MENTION(state, 12);

    expect(getters.getCount(state)).toBe(1);
    expect(getters.getByConversation(state)(12)).toBeNull();
  });
});

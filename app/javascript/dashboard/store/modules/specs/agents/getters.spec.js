import { getters } from '../../agents';

describe('#getters', () => {
  it('getAgents', () => {
    const state = {
      records: [
        {
          id: 1,
          name: 'Agent 1',
          email: 'agent1@chatwoot.com',
          confirmed: true,
        },
        {
          id: 2,
          name: 'Agent 2',
          email: 'agent2@chatwoot.com',
          confirmed: false,
        },
      ],
    };
    expect(getters.getAgents(state)).toEqual([
      {
        id: 1,
        name: 'Agent 1',
        email: 'agent1@chatwoot.com',
        confirmed: true,
      },
      {
        id: 2,
        name: 'Agent 2',
        email: 'agent2@chatwoot.com',
        confirmed: false,
      },
    ]);
  });

  it('getVerifiedAgents', () => {
    const state = {
      records: [
        {
          id: 1,
          name: 'Agent 1',
          email: 'agent1@chatwoot.com',
          confirmed: true,
        },
        {
          id: 2,
          name: 'Agent 2',
          email: 'agent2@chatwoot.com',
          confirmed: false,
        },
      ],
    };
    expect(getters.getVerifiedAgents(state)).toEqual([
      {
        id: 1,
        name: 'Agent 1',
        email: 'agent1@chatwoot.com',
        confirmed: true,
      },
    ]);
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: true,
        isCreating: false,
        isUpdating: false,
        isDeleting: false,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    });
  });

  it('getAgentStatus', () => {
    const state = {
      records: [
        {
          id: 1,
          name: 'Agent 1',
          email: 'agent1@chatwoot.com',
          confirmed: true,
          availability_status: 'online',
        },
        {
          id: 2,
          name: 'Agent 2',
          email: 'agent2@chatwoot.com',
          confirmed: false,
          availability_status: 'offline',
        },
      ],
    };
    expect(getters.getAgentStatus(state)).toEqual({
      online: 1,
      busy: 0,
      offline: 1,
    });
  });

  it('getAgentStatus', () => {
    const state = {
      records: [
        {
          id: 1,
          name: 'Agent 1',
          email: 'agent1@chatwoot.com',
          confirmed: true,
          availability_status: 'online',
        },
        {
          id: 2,
          name: 'Agent 2',
          email: 'agent2@chatwoot.com',
          confirmed: false,
          availability_status: 'offline',
        },
      ],
    };
    expect(getters.getAgentStatus(state)).toEqual({
      online: 1,
      busy: 0,
      offline: 1,
    });
  });

  describe('administrators', () => {
    const state = {
      records: [
        {
          id: 1,
          role: 'agent',
          confirmed: true,
          availability_status: 'online',
        },
        {
          id: 2,
          role: 'administrator',
          confirmed: true,
          availability_status: 'online',
        },
        {
          id: 3,
          role: 'administrator',
          is_ai_user: true,
          confirmed: true,
          availability_status: 'busy',
        },
      ],
    };

    it('getNonInternalAgents hides administrators except the AI user', () => {
      expect(getters.getNonInternalAgents(state).map(a => a.id)).toEqual([
        1, 3,
      ]);
    });

    it('getVerifiedNonInternalAgents hides administrators except the AI user', () => {
      expect(
        getters.getVerifiedNonInternalAgents(state).map(a => a.id)
      ).toEqual([1, 3]);
    });

    it('getAgentStatus does not count administrators except the AI user', () => {
      expect(getters.getAgentStatus(state)).toEqual({
        online: 1,
        busy: 1,
        offline: 0,
      });
    });
  });
});

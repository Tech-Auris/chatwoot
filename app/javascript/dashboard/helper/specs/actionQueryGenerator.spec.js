import actionQueryGenerator from '../actionQueryGenerator';

const testData = [
  {
    action_name: 'add_label',
    action_params: [{ id: 'testlabel', name: 'testlabel' }],
  },
  {
    action_name: 'assign_team',
    action_params: [
      {
        id: 1,
        name: 'sales team',
        description: 'This is our internal sales team',
        allow_auto_assign: true,
        account_id: 1,
        is_member: true,
      },
    ],
  },
];

const finalResult = [
  {
    action_name: 'add_label',
    action_params: ['testlabel'],
  },
  {
    action_name: 'assign_team',
    action_params: [1],
  },
];

describe('#actionQueryGenerator', () => {
  it('returns the correct format of filter query', () => {
    expect(actionQueryGenerator(testData)).toEqual(finalResult);
    expect(
      actionQueryGenerator(testData).every(i => Array.isArray(i.action_params))
    ).toBe(true);
  });
});

it('keeps the text and the template fallback of send_message', () => {
  const templateParams = { name: 'no_show', language: 'pt_BR' };
  expect(
    actionQueryGenerator([
      { action_name: 'send_message', action_params: ['Oi', templateParams] },
    ])
  ).toEqual([
    { action_name: 'send_message', action_params: ['Oi', templateParams] },
  ]);
});

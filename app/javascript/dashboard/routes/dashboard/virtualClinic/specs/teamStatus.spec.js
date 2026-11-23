import { describe, it, expect } from 'vitest';
import { faces, faceLines, isFaded } from '../teamStatus';

const t = (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key);
const onDuty = { secretary: { on_duty: true, active_conversations: 2 } };
const team = chat => ({
  manages_team: true,
  chat_enabled: chat,
  chat_missing: chat ? null : 'openai_key',
});

describe('teamStatus', () => {
  it('gives Clara attendance and assistant, and the other teammates only the assistant', () => {
    expect(
      faces('secretary', onDuty, team(true)).map(face => face.key)
    ).toEqual(['attendance', 'assistant']);
    expect(faces('manager', onDuty, team(true)).map(face => face.key)).toEqual([
      'assistant',
    ]);
  });

  it('turns the assistant on and off for every teammate at once (one OpenAI key)', () => {
    ['secretary', 'manager'].forEach(persona => {
      const assistantOf = aiTeam =>
        faces(persona, onDuty, aiTeam).find(face => face.key === 'assistant');

      expect(assistantOf(team(true))).toEqual({
        key: 'assistant',
        on: true,
        reason: null,
      });
      expect(assistantOf(team(false))).toEqual({
        key: 'assistant',
        on: false,
        reason: 'openai_key',
      });
    });
  });

  it('fades a teammate only when every face is off', () => {
    const offDuty = { secretary: { on_duty: false, off_duty_reason: 'x' } };

    expect(isFaded('secretary', onDuty, team(false))).toBe(false);
    expect(isFaded('secretary', offDuty, team(true))).toBe(false);
    expect(isFaded('secretary', offDuty, team(false))).toBe(true);
    expect(isFaded('manager', onDuty, team(false))).toBe(true);
  });

  it('shows agents only the attendance and never fades the others for them', () => {
    const agentTeam = { manages_team: false, chat_enabled: false };

    expect(faces('secretary', onDuty, agentTeam).map(f => f.key)).toEqual([
      'attendance',
    ]);
    expect(isFaded('manager', onDuty, agentTeam)).toBe(false);
  });

  it('writes one line per face with the reason when off', () => {
    expect(
      faceLines(
        'secretary',
        { secretary: { on_duty: false, off_duty_reason: 'ai_not_found' } },
        team(false),
        t
      )
    ).toEqual([
      {
        key: 'attendance',
        on: false,
        text: 'VIRTUAL_CLINIC.FACES.ATTENDANCE · VIRTUAL_CLINIC.FACES.REASONS.AI_NOT_FOUND',
      },
      {
        key: 'assistant',
        on: false,
        text: 'VIRTUAL_CLINIC.FACES.ASSISTANT · VIRTUAL_CLINIC.FACES.REASONS.MISSING_OPENAI',
      },
    ]);
  });

  it('shows only the name of the assistant when it is on (the green dot says it)', () => {
    expect(faceLines('manager', onDuty, team(true), t)).toEqual([
      { key: 'assistant', on: true, text: 'VIRTUAL_CLINIC.FACES.ASSISTANT' },
    ]);
  });

  it('waits for the live status before the attendance line', () => {
    expect(
      faceLines('secretary', null, team(true), t).map(line => line.key)
    ).toEqual(['assistant']);
  });
});

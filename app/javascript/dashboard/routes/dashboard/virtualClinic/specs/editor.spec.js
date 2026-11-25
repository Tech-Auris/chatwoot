import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  CHARACTERS,
  DEFAULT_LAYOUT,
  ITEMS,
  applySaved,
  seatedPose,
  toSaved,
} from '../engine/layout';
import { checkLayout } from '../engine/layoutCheck';
import { useClinicLayout } from '../composables/useClinicLayout';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';

vi.mock('dashboard/api/virtualClinic', () => ({
  default: {
    getLayout: vi.fn(),
    saveLayout: vi.fn(),
    resetLayout: vi.fn(),
  },
}));

const sizes = Object.fromEntries(
  ITEMS.map(({ sprite }) => [sprite, { width: 32, height: 32 }])
);

describe('seated at the desk', () => {
  it('sits Clara in her chair only while at the reception desk', () => {
    const desk = { x: CHARACTERS.secretary.x, y: CHARACTERS.secretary.y };
    expect(seatedPose('secretary', desk)).toEqual({ drop: 4, height: 52 });
    expect(seatedPose('secretary', { ...desk, moving: true })).toBeNull();
    // Moved elsewhere in the editor: she stands there.
    expect(seatedPose('secretary', { x: 280, y: 212 })).toBeNull();
    expect(seatedPose('manager', CHARACTERS.manager)).toBeNull();
  });
});

describe('saved layout', () => {
  it('keeps the default clinic when nothing was saved', () => {
    expect(applySaved(null)).toBe(DEFAULT_LAYOUT);
  });

  it('applies what the clinic changed and saves only that back', () => {
    const saved = {
      floors: ['5_pisos/alternativa_menta.png', null, null, null],
      items: [{ sprite: '4_copa/geladeira.png', x: 10, y: 400, flip: true }],
      rooms: { RECEPTION: 'Recepção Centro' },
      team: { manager: { name: 'Marta', sheet: '8_pessoas/pessoa_02.png' } },
    };
    const layout = applySaved(saved);

    expect(layout.floors[0].block).toBe('5_pisos/alternativa_menta.png');
    expect(layout.floors[1].block).toBe(DEFAULT_LAYOUT.floors[1].block);
    expect(layout.items).toHaveLength(1);
    expect(layout.rooms[0].name).toBe('Recepção Centro');
    expect(layout.team.manager).toMatchObject({
      name: 'Marta',
      sheet: '8_pessoas/pessoa_02.png',
      x: CHARACTERS.manager.x,
    });

    const back = toSaved(layout);
    expect(back.rooms).toEqual({ RECEPTION: 'Recepção Centro' });
    expect(back.items).toEqual([
      { sprite: '4_copa/geladeira.png', x: 10, y: 400, flip: true },
    ]);
    expect(back.team.secretary).toEqual({
      sheet: CHARACTERS.secretary.sheet,
      x: CHARACTERS.secretary.x,
      y: CHARACTERS.secretary.y,
    });
  });

  it('swaps the five reception desk pieces of an old layout for the whole desk', () => {
    const piece = (name, x, y) => ({ sprite: `1_recepcao/${name}.png`, x, y });
    const layout = applySaved({
      items: [
        piece('lixeira', 500, 210),
        piece('balcao_canto_esq', 230, 140),
        piece('balcao_meio', 262, 172),
        piece('balcao_com_computador', 294, 168),
        piece('balcao_meio_2', 358, 172),
        piece('balcao_canto_dir', 390, 140),
      ],
    });

    expect(layout.items).toEqual([
      piece('lixeira', 500, 210),
      piece('balcao_recepcao', 230, 124),
    ]);
  });
});

describe('checkLayout', () => {
  it('accepts the default clinic', () => {
    expect(checkLayout(DEFAULT_LAYOUT, sizes)).toBeNull();
  });

  it('refuses a piece in front of the door', () => {
    const items = [...ITEMS, { sprite: '4_copa/geladeira.png', x: 52, y: 80 }];
    expect(checkLayout({ ...DEFAULT_LAYOUT, items }, sizes)).toEqual({
      problem: 'entrance',
    });
  });

  it('refuses a teammate nobody can reach', () => {
    // A row of plants closing the door of the gerência to the corridor.
    const wall = [];
    for (let x = 1152; x < 1216; x += 16) {
      wall.push({ sprite: '3_gerencia/planta.png', x, y: 240 });
    }
    const layout = { ...DEFAULT_LAYOUT, items: [...ITEMS, ...wall] };
    expect(
      checkLayout(layout, {
        ...sizes,
        '3_gerencia/planta.png': { width: 16, height: 32 },
      })
    ).toEqual({ problem: 'unreachable', persona: 'manager' });
  });
});

describe('useClinicLayout', () => {
  beforeEach(() => vi.clearAllMocks());

  it('edits a draft and only changes the clinic on save', async () => {
    VirtualClinicAPI.saveLayout.mockResolvedValue({
      data: { layout: { rooms: { KITCHEN: 'Cozinha' } } },
    });
    const editor = useClinicLayout();
    editor.start();
    editor.renameRoom('KITCHEN', ' Cozinha ');
    editor.select({ kind: 'item', index: 0 });
    editor.moveSelected(101, 203, { width: 32, height: 32 });
    expect(editor.layout.value.items[0]).toMatchObject({ x: 100, y: 204 });
    editor.flipSelected();
    expect(editor.layout.value.items[0].flip).toBe(true);

    expect(await editor.save('')).toBe(true);
    const sent = VirtualClinicAPI.saveLayout.mock.calls[0][0];
    expect(sent.rooms).toEqual({ KITCHEN: 'Cozinha' });
    expect(sent.items[0]).toMatchObject({ x: 100, y: 204, flip: true });
    expect(editor.editing.value).toBe(false);
    expect(editor.layout.value.rooms[3].name).toBe('Cozinha');
  });

  it('keeps a moved piece inside the clinic and drops it with Del', () => {
    const editor = useClinicLayout();
    editor.start();
    const count = editor.layout.value.items.length;
    editor.select({ kind: 'item', index: 2 });
    editor.moveSelected(5000, -40, { width: 40, height: 40 });
    expect(editor.layout.value.items[2]).toMatchObject({ x: 1240, y: 0 });
    editor.removeSelected();
    expect(editor.layout.value.items).toHaveLength(count - 1);
    expect(editor.selected.value).toBeNull();
  });

  it('shows the problem and does not save', async () => {
    const editor = useClinicLayout();
    editor.start();
    expect(await editor.save('Ninguém chega até a Helena')).toBe(false);
    expect(editor.error.value).toBe('Ninguém chega até a Helena');
    expect(VirtualClinicAPI.saveLayout).not.toHaveBeenCalled();
  });

  it('saves one teammate right away, outside the editor', async () => {
    VirtualClinicAPI.saveLayout.mockResolvedValue({ data: { layout: {} } });
    const editor = useClinicLayout();
    const avatar = {
      body: 'Body_32x32_01',
      eyes: 'Eyes_32x32_01',
      outfit: 'Outfit_33_32x32_01',
    };
    await editor.saveTeam('secretary', { avatar });

    const sent = VirtualClinicAPI.saveLayout.mock.calls[0][0];
    expect(sent.team.secretary).toEqual({ avatar, x: 304, y: 87 });
    expect(sent.items).toHaveLength(ITEMS.length);
    expect(editor.editing.value).toBe(false);
  });

  it('adds a pack decoration once', () => {
    const editor = useClinicLayout();
    editor.start();
    const count = editor.layout.value.items.length;
    const pack = [{ sprite: '11_natal/arvore_natal.png', x: 440, y: 100 }];
    editor.addItems(pack);
    editor.addItems(pack);
    expect(editor.layout.value.items).toHaveLength(count + 1);
  });

  it('discards the draft', () => {
    const editor = useClinicLayout();
    editor.start();
    editor.setTeam('manager', { name: 'Marta' });
    editor.discard();
    expect(editor.editing.value).toBe(false);
    expect(editor.layout.value).toBe(DEFAULT_LAYOUT);
  });
});

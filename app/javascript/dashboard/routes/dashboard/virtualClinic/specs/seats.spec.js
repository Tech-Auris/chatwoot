import { describe, it, expect } from 'vitest';
import { seatAt, seatsOf, withoutSeats } from '../engine/seats';
import { frameAt } from '../engine/collision';

const items = [
  { sprite: '4_copa/cadeira_lado.png', x: 748, y: 492, flip: true },
  { sprite: '4_copa/cadeira_frente.png', x: 788, y: 445 },
  { sprite: '2_sala_de_espera/cadeira_azul_costas.png', x: 48, y: 530 },
  { sprite: '2_sala_de_espera/poltronas_beges_dupla.png', x: 28, y: 352 },
  { sprite: '1_recepcao/cadeira_secretaria.png', x: 304, y: 104 },
  { sprite: '4_copa/mesa_redonda.png', x: 772, y: 470 },
];
const sizes = {
  '4_copa/cadeira_lado.png': { width: 22, height: 32 },
  '4_copa/cadeira_frente.png': { width: 22, height: 24 },
  '2_sala_de_espera/cadeira_azul_costas.png': { width: 24, height: 24 },
  '2_sala_de_espera/poltronas_beges_dupla.png': { width: 62, height: 36 },
  '1_recepcao/cadeira_secretaria.png': { width: 24, height: 30 },
  '4_copa/mesa_redonda.png': { width: 56, height: 50 },
};
const team = { secretary: { x: 304, y: 87 } };

describe('seats', () => {
  const seats = seatsOf(items, sizes, team);

  it('knows chairs, armchairs and which way the sitter faces', () => {
    const faces = seats.map(seat => [
      seat.item.sprite.split('/')[1],
      seat.face,
    ]);
    expect(faces).toEqual([
      ['cadeira_lado.png', 'right'],
      ['cadeira_frente.png', 'down'],
      ['cadeira_azul_costas.png', 'up'],
      ['poltronas_beges_dupla.png', 'down'],
      ['poltronas_beges_dupla.png', 'down'],
    ]);
    // The double armchair seats two, side by side, in the compact frames.
    const [left, right] = seats.slice(3);
    expect([left.compact, right.x - left.x]).toEqual([true, 31]);
  });

  it("leaves the AI team's desk chair out", () => {
    expect(seats.some(seat => /secretaria/.test(seat.item.sprite))).toBe(false);
    expect(withoutSeats(items, seats).map(item => item.sprite)).toEqual([
      '1_recepcao/cadeira_secretaria.png',
      '4_copa/mesa_redonda.png',
    ]);
  });

  it('finds the seat under the feet and where the sitter is drawn', () => {
    const chair = seatAt(seats, frameAt({ x: 798, y: 456 }));
    expect(chair).toMatchObject({ face: 'down', frame: { x: 783, y: 401 } });
    expect(seatAt(seats, frameAt({ x: 600, y: 300 }))).toBeNull();
  });
});

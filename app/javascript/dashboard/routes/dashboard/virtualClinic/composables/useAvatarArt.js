import { reactive } from 'vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import { layerPath, layersOf, lookSheet } from '../engine/avatar';

// Standing, facing front (row 1, column 18 of the sheet), from the top of
// the hair down to the feet: 32×52 of the 32×64 frame.
export const FRONT = { x: 18 * 32, y: 64 + 12, width: 32, height: 52 };
// The six frames of standing facing front (the preview).
export const IDLE_FRONT = { x: 18 * 32, y: 64, width: 6 * 32, height: 64 };

// Layers are whole spritesheets, so only the PNGs are kept and each picture
// decodes just the part it needs (the art needs the user's session, so it
// comes through the API, once).
const blobs = {};
const blobOf = path => {
  blobs[path] ||= VirtualClinicAPI.getAsset(path);
  return blobs[path];
};

const cut = async (path, region) =>
  createImageBitmap(
    await blobOf(path),
    region.x,
    region.y,
    region.width,
    region.height
  );

// A region of the sheet of a look: the premade sheet, or every layer drawn
// in order.
export async function drawLook(look, region) {
  const paths = look.sheet
    ? [look.sheet]
    : layersOf(lookSheet(look)).map(layerPath);
  const layers = await Promise.all(paths.map(path => cut(path, region)));
  const canvas = document.createElement('canvas');
  canvas.width = region.width;
  canvas.height = region.height;
  const context = canvas.getContext('2d');
  layers.forEach(layer => context.drawImage(layer, 0, 0));
  return canvas;
}

export const loadArt = async path => createImageBitmap(await blobOf(path));

const frontPixels = async name => {
  const canvas = document.createElement('canvas');
  canvas.width = FRONT.width;
  canvas.height = FRONT.height;
  const context = canvas.getContext('2d');
  context.drawImage(await cut(layerPath(name), FRONT), 0, 0);
  return context.getImageData(0, 0, FRONT.width, FRONT.height).data;
};

const differs = (data, other, i) =>
  [0, 1, 2, 3].some(c => data[i + c] !== other[i + c]);

const mostCommon = (data, counted) => {
  const counts = {};
  for (let i = 0; i < data.length; i += 4) {
    const [r, g, b, a] = [data[i], data[i + 1], data[i + 2], data[i + 3]];
    if (a > 0 && counted(i)) {
      const color = `rgb(${r}, ${g}, ${b})`;
      counts[color] = (counts[color] || 0) + 1;
    }
  }
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0];
};

// The color a layer is known by (the dots under the grid), as a one-pixel
// picture: the most common one of its front frame among the pixels that
// change in `other` (another color of the same style), so outlines and
// details drawn the same in every color are left out. When none change, any
// pixel but the darkest counts.
const swatchOf = async (name, other) => {
  const data = await frontPixels(name);
  const otherData = other && (await frontPixels(other));
  const top =
    (otherData && mostCommon(data, i => differs(data, otherData, i))) ||
    mostCommon(data, i => data[i] + data[i + 1] + data[i + 2] > 120);
  const dot = document.createElement('canvas');
  dot.width = 1;
  dot.height = 1;
  const paint = dot.getContext('2d');
  paint.fillStyle = top || 'transparent';
  paint.fillRect(0, 0, 1, 1);
  return dot.toDataURL();
};

const thumbnails = reactive({});
const swatches = reactive({});

const remember = (store, key, load) => {
  if (!(key in store)) {
    store[key] = '';
    load().then(value => {
      store[key] = value;
    });
  }
  return store[key];
};

// Small pictures for the avatar editor, '' while they load: a look standing
// and the color of a layer (both <img> srcs).
export function useAvatarArt() {
  const thumbnail = look =>
    remember(thumbnails, lookSheet(look), async () =>
      (await drawLook(look, FRONT)).toDataURL()
    );
  // `colors`: every color of the style of `name`.
  const swatch = (name, colors = []) =>
    remember(swatches, name, () =>
      swatchOf(
        name,
        colors.find(color => color !== name)
      )
    );
  return { thumbnail, swatch };
}

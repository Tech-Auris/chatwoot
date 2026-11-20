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

// The color a layer is known by (the dots under the grid): the most common
// one of its front frame, outlines and shadows left out, as a one-pixel
// picture.
const swatchOf = async name => {
  const canvas = document.createElement('canvas');
  canvas.width = FRONT.width;
  canvas.height = FRONT.height;
  const context = canvas.getContext('2d');
  context.drawImage(await cut(layerPath(name), FRONT), 0, 0);
  const { data } = context.getImageData(0, 0, FRONT.width, FRONT.height);
  const counts = {};
  for (let i = 0; i < data.length; i += 4) {
    const [r, g, b, a] = [data[i], data[i + 1], data[i + 2], data[i + 3]];
    if (a > 0 && r + g + b > 120) {
      const color = `rgb(${r}, ${g}, ${b})`;
      counts[color] = (counts[color] || 0) + 1;
    }
  }
  const [top] = Object.entries(counts).sort((a, b) => b[1] - a[1]);
  const dot = document.createElement('canvas');
  dot.width = 1;
  dot.height = 1;
  const paint = dot.getContext('2d');
  paint.fillStyle = top ? top[0] : 'transparent';
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
  const swatch = name => remember(swatches, name, () => swatchOf(name));
  return { thumbnail, swatch };
}

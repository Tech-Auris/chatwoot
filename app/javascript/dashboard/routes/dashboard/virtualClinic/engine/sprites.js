import { composeAvatar, isAvatarKey } from './avatar';

// Loads the clinic art. Furniture pieces from the pack carry a lot of
// transparent margin, so each one is cropped to its outline on load; floor
// and wall blocks and character sheets keep their exact grid.
const KEEP_GRID = /^(5_pisos|6_paredes|7_personagens|8_pessoas)\//;
// An animated piece is a strip of frames side by side ("lago_anim16.png":
// 16 frames).
const ANIMATED = /_anim(\d+)\.png$/;

// `width` × the image height, from `x` on, as a canvas.
const sliceOf = (image, x = 0, width = image.width) => {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = image.height;
  canvas
    .getContext('2d')
    .drawImage(image, x, 0, width, image.height, 0, 0, width, image.height);
  return canvas;
};

// The box around the visible pixels of a canvas, or null when there are none.
function outlineOf(canvas) {
  const { data } = canvas
    .getContext('2d')
    .getImageData(0, 0, canvas.width, canvas.height);
  let [left, top, right, bottom] = [canvas.width, canvas.height, -1, -1];
  for (let y = 0; y < canvas.height; y += 1) {
    for (let x = 0; x < canvas.width; x += 1) {
      if (data[(y * canvas.width + x) * 4 + 3] > 0) {
        left = Math.min(left, x);
        right = Math.max(right, x);
        top = Math.min(top, y);
        bottom = Math.max(bottom, y);
      }
    }
  }
  return right < 0 ? null : { left, top, right, bottom };
}

function crop(canvas, box) {
  if (!box) return canvas;
  const { left, top, right, bottom } = box;
  const cropped = document.createElement('canvas');
  cropped.width = right - left + 1;
  cropped.height = bottom - top + 1;
  cropped
    .getContext('2d')
    .drawImage(
      canvas,
      left,
      top,
      cropped.width,
      cropped.height,
      0,
      0,
      cropped.width,
      cropped.height
    );
  return cropped;
}

export function cropToOutline(image) {
  const canvas = sliceOf(image);
  return crop(canvas, outlineOf(canvas));
}

// The frames of an animated piece, each cut like the first one so they stay
// aligned. The first frame stands for the piece (its size, its thumbnail)
// and carries them all in `frames`.
function framesOf(image, count) {
  const width = image.width / count;
  const slices = Array.from({ length: count }, (_, i) =>
    sliceOf(image, i * width, width)
  );
  const box = outlineOf(slices[0]);
  const frames = slices.map(slice => crop(slice, box));
  frames[0].frames = frames;
  return frames[0];
}

const prepare = (path, image) => {
  const animated = path.match(ANIMATED);
  if (animated) return framesOf(image, Number(animated[1]));
  return KEEP_GRID.test(path) ? image : cropToOutline(image);
};

// `fetchBlob(path)` resolves to the PNG blob of one file of the pack. An
// avatar key (see avatar.js) loads its layers and becomes one sheet.
export async function loadSprites(paths, fetchBlob) {
  const loadImage = async path => createImageBitmap(await fetchBlob(path));
  const entries = await Promise.all(
    paths.map(async path => {
      if (isAvatarKey(path))
        return [path, await composeAvatar(path, loadImage)];
      const image = await loadImage(path);
      return [path, prepare(path, image)];
    })
  );
  return Object.fromEntries(entries);
}

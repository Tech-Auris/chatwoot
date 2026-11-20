// Loads the clinic art. Furniture pieces from the pack carry a lot of
// transparent margin, so each one is cropped to its outline on load; floor
// and wall blocks and character sheets keep their exact grid.
const KEEP_GRID = /^(5_pisos|6_paredes|7_personagens|8_pessoas)\//;

export function cropToOutline(image) {
  const canvas = document.createElement('canvas');
  canvas.width = image.width;
  canvas.height = image.height;
  const context = canvas.getContext('2d');
  context.drawImage(image, 0, 0);
  const { data } = context.getImageData(0, 0, image.width, image.height);
  let [left, top, right, bottom] = [image.width, image.height, -1, -1];
  for (let y = 0; y < image.height; y += 1) {
    for (let x = 0; x < image.width; x += 1) {
      if (data[(y * image.width + x) * 4 + 3] > 0) {
        left = Math.min(left, x);
        right = Math.max(right, x);
        top = Math.min(top, y);
        bottom = Math.max(bottom, y);
      }
    }
  }
  if (right < 0) return canvas;
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

// `fetchBlob(path)` resolves to the PNG blob of one file of the pack.
export async function loadSprites(paths, fetchBlob) {
  const entries = await Promise.all(
    paths.map(async path => {
      const image = await createImageBitmap(await fetchBlob(path));
      return [path, KEEP_GRID.test(path) ? image : cropToOutline(image)];
    })
  );
  return Object.fromEntries(entries);
}

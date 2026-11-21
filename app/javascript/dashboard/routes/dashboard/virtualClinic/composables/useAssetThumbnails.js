import { reactive } from 'vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import { cropToOutline } from '../engine/sprites';

const SHEET = /^(7_personagens|8_pessoas)\//;
const BLOCK = /^(5_pisos|6_paredes)\//;
// Standing, facing front: row 1, column 18 of the LimeZu character sheet.
const FRONT = { x: 18 * 32, y: 64, width: 32, height: 64 };

const urls = reactive({});

const toUrl = async path => {
  const image = await createImageBitmap(await VirtualClinicAPI.getAsset(path));
  if (BLOCK.test(path)) {
    const canvas = document.createElement('canvas');
    canvas.width = image.width;
    canvas.height = image.height;
    canvas.getContext('2d').drawImage(image, 0, 0);
    return canvas.toDataURL();
  }
  if (SHEET.test(path)) {
    const canvas = document.createElement('canvas');
    canvas.width = FRONT.width;
    canvas.height = FRONT.height;
    canvas
      .getContext('2d')
      .drawImage(
        image,
        FRONT.x,
        FRONT.y,
        FRONT.width,
        FRONT.height,
        0,
        0,
        FRONT.width,
        FRONT.height
      );
    return canvas.toDataURL();
  }
  return cropToOutline(image).toDataURL();
};

// Small pictures of the pack for the editor (the art needs the user's
// session, so it can't be a plain <img> URL): furniture cropped to its
// outline, floor and wall blocks as they are, characters standing.
export function useAssetThumbnails() {
  const thumbnail = path => {
    if (!(path in urls)) {
      urls[path] = '';
      toUrl(path).then(url => {
        urls[path] = url;
      });
    }
    return urls[path];
  };
  return { thumbnail };
}

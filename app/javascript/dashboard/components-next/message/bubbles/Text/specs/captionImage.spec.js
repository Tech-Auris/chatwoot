import { findCaptionImage } from '../captionImage';

const image = {
  id: 1,
  fileType: 'image',
  dataUrl: 'https://example.com/a.png',
};

describe('findCaptionImage', () => {
  it('returns the image when a single image comes with text', () => {
    expect(findCaptionImage([image], 'Olá')).toBe(image);
  });

  it('returns null when there is no text', () => {
    expect(findCaptionImage([image], '')).toBeNull();
  });

  it('returns null when there is more than one attachment', () => {
    expect(findCaptionImage([image, { ...image, id: 2 }], 'Olá')).toBeNull();
  });

  it('returns null when the single attachment is not an image', () => {
    expect(
      findCaptionImage([{ ...image, fileType: 'file' }], 'Olá')
    ).toBeNull();
  });
});

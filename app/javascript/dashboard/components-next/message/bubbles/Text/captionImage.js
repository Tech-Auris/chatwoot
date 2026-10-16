import { ATTACHMENT_TYPES } from '../../constants';

// WhatsApp shows a lone image sent with text as a picture on top with the
// text as its caption below, so the bubble mirrors that instead of showing
// the image as a thumbnail chip under the text.
export const findCaptionImage = (attachments, content) => {
  if (!content || attachments?.length !== 1) return null;

  const [attachment] = attachments;
  return attachment.fileType === ATTACHMENT_TYPES.IMAGE ? attachment : null;
};

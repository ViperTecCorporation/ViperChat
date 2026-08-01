const FULL_PROTOCOL_URL = /^https?:\/\/[^\s]+$/i;

const normalizeText = value => value?.replace(/\s+/g, ' ').trim() || '';

export const extractFullProtocolUrlFromClipboard = clipboardData => {
  const html = clipboardData?.getData('text/html');
  if (!html) return null;

  const document = new DOMParser().parseFromString(html, 'text/html');
  const anchors = document.querySelectorAll('a[href]');
  if (anchors.length !== 1) return null;

  const anchor = anchors[0];
  const href = anchor.getAttribute('href')?.trim();
  if (!href || !FULL_PROTOCOL_URL.test(href)) return null;

  const anchorText = normalizeText(anchor.textContent);
  const htmlText = normalizeText(document.body.textContent);
  const plainText = normalizeText(clipboardData.getData('text/plain'));

  const containsOnlyLink =
    htmlText === anchorText &&
    (!plainText || plainText === anchorText || plainText === href);

  return containsOnlyLink ? href : null;
};

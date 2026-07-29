import { describe, expect, it } from 'vitest';
import { extractFullProtocolUrlFromClipboard } from './clipboardUrl';

const clipboardData = ({ html = '', text = '' } = {}) => ({
  getData: type => (type === 'text/html' ? html : text),
});

describe('extractFullProtocolUrlFromClipboard', () => {
  it('returns the URL when the clipboard contains only a rich HTTPS link', () => {
    const data = clipboardData({
      html: '<a href="https://example.com/page">Example page</a>',
      text: 'Example page',
    });

    expect(extractFullProtocolUrlFromClipboard(data)).toBe(
      'https://example.com/page'
    );
  });

  it('accepts a complete HTTP URL', () => {
    const data = clipboardData({
      html: '<a href="http://example.com/page">Example page</a>',
      text: 'Example page',
    });

    expect(extractFullProtocolUrlFromClipboard(data)).toBe(
      'http://example.com/page'
    );
  });

  it('ignores links without a complete HTTP protocol', () => {
    const data = clipboardData({
      html: '<a href="example.com/page">Example page</a>',
      text: 'Example page',
    });

    expect(extractFullProtocolUrlFromClipboard(data)).toBeNull();
  });

  it('does not replace rich text that contains content besides the link', () => {
    const data = clipboardData({
      html: '<p>See <a href="https://example.com/page">this page</a></p>',
      text: 'See this page',
    });

    expect(extractFullProtocolUrlFromClipboard(data)).toBeNull();
  });
});

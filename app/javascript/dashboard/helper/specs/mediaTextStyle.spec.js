import { mediaTextStyle, MEDIA_FONTS } from '../mediaTextStyle';

describe('media text formatting', () => {
  it('combines bold italic underline and shadow', () => {
    expect(
      mediaTextStyle(
        { bold: true, italic: true, underline: true, shadow: true },
        40
      )
    ).toMatchObject({
      fontStyle: 'bold italic',
      textDecoration: 'underline',
      shadowEnabled: true,
      shadowBlur: 4.8,
    });
  });
  it('removes all formatting when switches are cleared', () => {
    expect(mediaTextStyle({}, 28)).toMatchObject({
      fontStyle: 'normal',
      textDecoration: '',
      shadowEnabled: false,
    });
  });
  it('offers ten distinct system font choices', () => {
    expect(new Set(MEDIA_FONTS).size).toBe(10);
  });
});

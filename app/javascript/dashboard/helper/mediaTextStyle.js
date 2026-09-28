export const MEDIA_FONTS = [
  'Arial',
  'Verdana',
  'Georgia',
  'Tahoma',
  'Trebuchet MS',
  'Times New Roman',
  'Courier New',
  'Impact',
  'Comic Sans MS',
  'system-ui',
];

export function mediaTextStyle({ bold, italic, underline, shadow }, fontSize) {
  return {
    fontStyle:
      [bold && 'bold', italic && 'italic'].filter(Boolean).join(' ') ||
      'normal',
    textDecoration: underline ? 'underline' : '',
    shadowEnabled: !!shadow,
    shadowColor: '#000000',
    shadowOpacity: 0.8,
    shadowBlur: fontSize * 0.12,
    shadowOffsetX: fontSize * 0.06,
    shadowOffsetY: fontSize * 0.06,
  };
}

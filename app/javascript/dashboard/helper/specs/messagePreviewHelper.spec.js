import { getMessagePreviewContent } from '../messagePreviewHelper';

const t = key => key;

describe('getMessagePreviewContent', () => {
  it('uses the transcription of an attachment when message content is empty', () => {
    const message = {
      content: null,
      attachments: [
        { fileType: 'audio', transcribedText: 'Texto transcrito do áudio' },
      ],
    };

    expect(getMessagePreviewContent({ message, t })).toBe(
      'Texto transcrito do áudio'
    );
  });

  it('supports the snake case transcription returned by older payloads', () => {
    const message = {
      attachments: [
        {
          file_type: 'audio',
          meta: { transcribed_text: 'Transcrição antiga' },
        },
      ],
    };

    expect(getMessagePreviewContent({ message, t })).toBe('Transcrição antiga');
  });

  it('keeps message content ahead of attachment transcription', () => {
    const message = {
      content: 'Legenda da mídia',
      attachments: [{ fileType: 'audio', transcribedText: 'Transcrição' }],
    };

    expect(getMessagePreviewContent({ message, t })).toBe('Legenda da mídia');
  });

  it('shows the attachment label when media has no transcription', () => {
    const message = { attachments: [{ fileType: 'audio' }] };

    expect(getMessagePreviewContent({ message, t })).toBe(
      'CHAT_LIST.ATTACHMENTS.audio.CONTENT'
    );
  });

  it('uses the empty fallback only when there is no message or attachment', () => {
    expect(getMessagePreviewContent({ t })).toBe('CHAT_LIST.NO_CONTENT');
  });
});

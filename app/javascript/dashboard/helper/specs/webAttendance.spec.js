import { describe, expect, it } from 'vitest';
import {
  attendanceDraftKey,
  filterMessagesByDestination,
  supportsWebAttendance,
  webAttendanceLimits,
} from '../webAttendance';
import { createPendingMessage } from '../commons';
import en from 'dashboard/i18n/locale/en/webAttendance.json';
import pt from 'dashboard/i18n/locale/pt/webAttendance.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/webAttendance.json';

describe('web attendance destinations', () => {
  it.each([
    ['unoapi', true],
    ['whatsapp_cloud', true],
    ['cloud', false],
    ['default', false],
    ['twilio', false],
  ])(
    'supports attendance provider %s=%s without widening other gates',
    (provider, expected) => {
      expect(
        supportsWebAttendance({ provider, channel_type: 'Channel::Whatsapp' })
      ).toBe(expected);
      expect(
        supportsWebAttendance({ provider, channel_type: 'Channel::Api' })
      ).toBe(false);
      expect(supportsWebAttendance(null)).toBe(false);
    }
  );
  it('keeps Uno limits and applies Meta CTA limits only to WhatsApp Cloud', () => {
    expect(webAttendanceLimits('unoapi')).toEqual({
      invitation: 4096,
      button: 60,
    });
    expect(webAttendanceLimits('whatsapp_cloud')).toEqual({
      invitation: 1024,
      button: 20,
    });
  });
  it.each([en, pt, ptBR])(
    'keeps translated Cloud defaults within 20 characters and explains the window',
    locale => {
      expect(
        locale.WEB_ATTENDANCE.DEFAULT_BUTTON_CLOUD.length
      ).toBeLessThanOrEqual(20);
      expect(locale.WEB_ATTENDANCE.CLOUD_HELP).toContain('24');
      expect(locale.WEB_ATTENDANCE.INVITE_UNAVAILABLE).toContain('template');
      expect(locale.WEB_ATTENDANCE.BUTTON_LABEL).toContain('{max}');
    }
  );
  const messages = [
    { id: 1, message_type: 0 },
    { id: 2, message_type: 1, delivery_destination: 'channel' },
    { id: 3, message_type: 0, delivery_destination: 'web' },
    { id: 4, message_type: 1, delivery_destination: 'web' },
    { id: 5, message_type: 1, private: true },
    { id: 6, message_type: 2 },
    { id: 7, message_type: 'activity' },
  ];

  it('keeps old channel messages and shared notes/activity in WhatsApp', () => {
    expect(
      filterMessagesByDestination(messages, 'channel').map(m => m.id)
    ).toEqual([1, 2, 5, 6, 7]);
  });

  it('shows only web messages plus shared notes/activity in Web', () => {
    expect(filterMessagesByDestination(messages, 'web').map(m => m.id)).toEqual(
      [3, 4, 5, 6, 7]
    );
  });

  it('separates public drafts while preserving the existing common note key', () => {
    expect(attendanceDraftKey(12, 'REPLY', 'channel')).toBe('draft-12-REPLY');
    expect(attendanceDraftKey(12, 'REPLY', 'web')).toBe('draft-12-REPLY-web');
    expect(attendanceDraftKey(12, 'NOTE', 'web')).toBe('draft-12-NOTE');
    expect(attendanceDraftKey(12, 'NOTE', 'channel')).toBe('draft-12-NOTE');
  });

  it('preserves web routing in an optimistic contact message', () => {
    const pending = createPendingMessage({
      conversationId: 12,
      delivery_destination: 'web',
      contentAttributes: {
        contacts: [{ name: 'Contact', phone_number: '+15555550101' }],
      },
    });
    expect(pending.delivery_destination).toBe('web');
    expect(pending.attachments[0].file_type).toBe('contact');
  });

  it('defaults optimistic legacy messages to the original channel', () => {
    expect(
      createPendingMessage({ conversationId: 12 }).delivery_destination
    ).toBe('channel');
  });
});

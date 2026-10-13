import { describe, expect, it, vi } from 'vitest';
import Settings from 'dashboard/routes/dashboard/settings/inbox/Settings.vue';
import {
  supportsWebAttendance,
  webAttendanceLimits,
} from 'dashboard/helper/webAttendance';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('web attendance inbox settings', () => {
  it.each([
    ['whatsapp_cloud', true, true, true, 'x'.repeat(1024), true],
    ['whatsapp_cloud', true, true, true, 'x'.repeat(1025), false],
    ['whatsapp_cloud', true, true, true, ' '.repeat(1025), false],
    ['whatsapp_cloud', true, true, true, '🎉'.repeat(1024), true],
    ['whatsapp_cloud', true, true, false, 'x'.repeat(1025), true],
    ['whatsapp_cloud', true, false, true, 'x'.repeat(1025), true],
    ['whatsapp_cloud', false, true, true, 'x'.repeat(1025), true],
    ['unoapi', true, true, true, 'x'.repeat(2048), true],
  ])(
    'validates %s greeting CTA with web=%s greeting=%s invite=%s',
    async (provider, web, greeting, invite, content, allowed) => {
      const context = {
        supportsWebAttendance: true,
        inbox: { provider },
        currentInboxId: 7,
        webAttendanceLimits: webAttendanceLimits(provider),
        webAttendanceEnabled: web,
        greetingEnabled: greeting,
        webAttendanceGreetingEnabled: invite,
        greetingMessage: content,
        webAttendanceButtonText: 'Abrir atendimento',
        webAttendanceInvitationMessage: 'Manual invitation',
        widgetBuilderStorageKey: 'web-attendance-greeting-test',
        $store: { dispatch: vi.fn().mockResolvedValue() },
        $t: key => key,
        get webAttendanceGreetingTooLong() {
          return Settings.computed.webAttendanceGreetingTooLong.call(this);
        },
      };
      useAlert.mockClear();
      expect(context.webAttendanceGreetingTooLong).toBe(!allowed);
      await Settings.methods.updateInbox.call(context);
      if (allowed) {
        expect(context.$store.dispatch).toHaveBeenCalledWith(
          'inboxes/updateInbox',
          expect.objectContaining({ greeting_message: content })
        );
      } else {
        expect(context.$store.dispatch).not.toHaveBeenCalled();
        expect(useAlert).toHaveBeenCalledWith(
          'WEB_ATTENDANCE.GREETING_LIMIT_ERROR'
        );
      }
      expect(context.greetingMessage).toBe(content);
      localStorage.removeItem(context.widgetBuilderStorageKey);
    }
  );
  it.each([
    ['whatsapp_cloud', undefined, 'Abrir atendimento'],
    ['whatsapp_cloud', 'Continuar atendimento', 'Abrir atendimento'],
    ['whatsapp_cloud', 'Custom CTA', 'Custom CTA'],
    ['unoapi', undefined, 'Continuar atendimento'],
    ['unoapi', 'Continuar atendimento', 'Continuar atendimento'],
  ])(
    'initializes %s button %s without changing custom or Uno labels',
    (provider, configured, expected) => {
      const context = {
        isAWhatsAppCloudChannel: provider === 'whatsapp_cloud',
        inbox: { id: 7, provider, web_attendance_button_text: configured },
        widgetBuilderStorageKey: 'web-attendance-settings-test',
        $t: key =>
          ({
            'WEB_ATTENDANCE.DEFAULT_BUTTON_CLOUD': 'Abrir atendimento',
            'WEB_ATTENDANCE.DEFAULT_BUTTON': 'Continuar atendimento',
          })[key] || key,
      };
      Settings.methods.syncInboxData.call(context);
      expect(context.webAttendanceButtonText).toBe(expected);
    }
  );
  it.each([
    ['unoapi', true],
    ['unoapi', false],
    ['whatsapp_cloud', true],
    ['whatsapp_cloud', false],
  ])(
    'saves explicit %s configuration with enabled=%s',
    async (provider, enabled) => {
      const context = {
        isAUnoapiChannel: true,
        supportsWebAttendance: true,
        webAttendanceLimits: webAttendanceLimits(provider),
        currentInboxId: 7,
        selectedInboxName: ' Test inbox ',
        inbox: { provider, channel_type: 'Channel::Whatsapp' },
        webAttendanceEnabled: enabled,
        webAttendanceGreetingEnabled: true,
        greetingEnabled: true,
        greetingMessage: 'Greeting remains enabled',
        webAttendanceButtonText: ' Open Web ',
        webAttendanceInvitationMessage: ' Continue online ',
        widgetBuilderStorageKey: 'web-attendance-settings-test',
        $store: { dispatch: vi.fn().mockResolvedValue() },
        $t: key => key,
      };
      await Settings.methods.updateInbox.call(context);
      expect(context.$store.dispatch).toHaveBeenCalledWith(
        'inboxes/updateInbox',
        expect.objectContaining({
          id: 7,
          web_attendance_enabled: enabled,
          greeting_enabled: true,
          greeting_message: 'Greeting remains enabled',
          web_attendance_greeting_enabled: enabled,
          web_attendance_button_text: 'Open Web',
          web_attendance_invitation_message: 'Continue online',
        })
      );
      localStorage.removeItem(context.widgetBuilderStorageKey);
    }
  );

  it.each(['cloud', 'default', 'twilio'])(
    'does not send attendance settings for %s',
    async provider => {
      const context = {
        isAUnoapiChannel: false,
        supportsWebAttendance: false,
        currentInboxId: 7,
        inbox: { provider, channel_type: 'Channel::Whatsapp' },
        widgetBuilderStorageKey: 'web-attendance-settings-test',
        $store: { dispatch: vi.fn().mockResolvedValue() },
        $t: key => key,
      };
      await Settings.methods.updateInbox.call(context);
      expect(context.$store.dispatch).toHaveBeenCalledOnce();
      const payload = context.$store.dispatch.mock.calls[0][1];
      expect(payload).not.toHaveProperty('web_attendance_enabled');
      expect(payload).not.toHaveProperty('web_attendance_greeting_enabled');
      expect(payload).not.toHaveProperty('web_attendance_button_text');
      expect(payload).not.toHaveProperty('web_attendance_invitation_message');
      localStorage.removeItem(context.widgetBuilderStorageKey);
    }
  );

  it.each(['unoapi', 'whatsapp_cloud', 'cloud', 'default'])(
    'exposes settings only for supported provider %s',
    provider => {
      const inbox = { provider, channel_type: 'Channel::Whatsapp' };
      expect(Settings.computed.supportsWebAttendance.call({ inbox })).toBe(
        supportsWebAttendance(inbox)
      );
      expect(Settings.computed.webAttendanceLimits.call({ inbox })).toEqual(
        webAttendanceLimits(provider)
      );
    }
  );

  it.each([
    ['whatsapp_cloud', 1024, 20],
    ['unoapi', 4096, 60],
  ])(
    'validates body and title lengths for %s without sending invalid settings',
    async (provider, invitation, button) => {
      const context = {
        supportsWebAttendance: true,
        webAttendanceEnabled: true,
        webAttendanceLimits: webAttendanceLimits(provider),
        webAttendanceInvitationMessage: 'x'.repeat(invitation + 1),
        webAttendanceButtonText: 'x'.repeat(button),
        currentInboxId: 7,
        inbox: { provider },
        widgetBuilderStorageKey: 'web-attendance-settings-test',
        $store: { dispatch: vi.fn().mockResolvedValue() },
        $t: key => key,
      };
      await Settings.methods.updateInbox.call(context);
      expect(context.$store.dispatch).not.toHaveBeenCalled();
      context.webAttendanceInvitationMessage = 'x'.repeat(invitation);
      context.webAttendanceButtonText = 'x'.repeat(button + 1);
      await Settings.methods.updateInbox.call(context);
      expect(context.$store.dispatch).not.toHaveBeenCalled();
      context.webAttendanceButtonText = 'x'.repeat(button);
      await Settings.methods.updateInbox.call(context);
      expect(context.$store.dispatch).toHaveBeenCalledOnce();
      context.webAttendanceEnabled = false;
      context.webAttendanceButtonText = 'x'.repeat(button + 1);
      await Settings.methods.updateInbox.call(context);
      expect(context.$store.dispatch).toHaveBeenCalledTimes(2);
      localStorage.removeItem(context.widgetBuilderStorageKey);
    }
  );
});

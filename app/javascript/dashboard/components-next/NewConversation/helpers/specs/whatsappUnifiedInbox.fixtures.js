export const link = {
  link_id: 7,
  primary_inbox_id: 1,
  primary_inbox_name: 'Unified support',
  secondary_inbox_id: 2,
  default_provider: 'unoapi',
  transports: [
    {
      provider: 'unoapi',
      label: 'ViperConnect',
      inbox_id: 2,
      channel_type: 'Channel::Whatsapp',
      message_templates: [],
    },
    {
      provider: 'whatsapp_cloud',
      label: 'Meta',
      inbox_id: 1,
      channel_type: 'Channel::Whatsapp',
      message_templates: [
        {
          id: 9,
          name: 'welcome',
          status: 'APPROVED',
          components: [{ type: 'BODY', text: 'Welcome' }],
        },
      ],
    },
  ],
};
export const inboxes = [
  {
    id: 1,
    name: 'Unified support',
    provider: 'whatsapp_cloud',
    channel_type: 'Channel::Whatsapp',
    whatsapp_inbox_link: link,
  },
  {
    id: 2,
    name: 'Physical Uno',
    provider: 'unoapi',
    channel_type: 'Channel::Whatsapp',
    whatsapp_inbox_link: link,
  },
];

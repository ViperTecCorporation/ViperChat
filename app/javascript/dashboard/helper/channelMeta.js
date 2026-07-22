export const getChannelMeta = channelType => {
  const ch = (channelType || '').toLowerCase();
  if (ch.includes('whatsapp'))
    return { icon: 'i-lucide-phone', color: 'text-emerald-500', name: 'WhatsApp' };
  if (ch.includes('email'))
    return { icon: 'i-lucide-mail', color: 'text-cyan-500', name: 'E-mail' };
  if (ch.includes('instagram'))
    return { icon: 'i-lucide-instagram', color: 'text-pink-500', name: 'Instagram' };
  if (ch.includes('facebook'))
    return { icon: 'i-lucide-facebook', color: 'text-blue-600', name: 'Facebook' };
  if (ch.includes('twitter'))
    return { icon: 'i-lucide-twitter', color: 'text-sky-400', name: 'Twitter' };
  if (ch.includes('telegram'))
    return { icon: 'i-lucide-send', color: 'text-sky-500', name: 'Telegram' };
  if (ch.includes('tiktok'))
    return { icon: 'i-lucide-music', color: 'text-pink-400', name: 'TikTok' };
  return { icon: 'i-lucide-globe', color: 'text-slate-400', name: 'Web Chat' };
};

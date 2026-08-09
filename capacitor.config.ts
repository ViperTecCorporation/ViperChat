import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'net.vipertec.viperchat',
  appName: 'ViperChat',
  webDir: 'dist-mobile',
  loggingBehavior: 'debug',
  server: {
    hostname: 'localhost',
    androidScheme: 'https',
  },
  plugins: {
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'banner', 'list'],
    },
  },
};

export default config;

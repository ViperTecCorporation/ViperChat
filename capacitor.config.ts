import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'net.vipertec.viperchat',
  appName: 'ViperChat',
  webDir: 'dist-mobile',
  loggingBehavior: 'none',
  server: {
    hostname: 'localhost',
    androidScheme: 'https',
  },
  plugins: {
    FirebaseMessaging: {
      presentationOptions: ['alert', 'badge', 'sound'],
    },
  },
};

export default config;

import { loadConfig } from './config.js';
import { createFirebaseSender } from './firebase.js';
import { buildServer } from './server.js';

const config = loadConfig();
const server = buildServer({
  relayToken: config.relayToken,
  firebaseProjectId: config.firebaseProjectId,
  sendPush: createFirebaseSender({
    projectId: config.firebaseProjectId,
    credentials: config.firebaseCredentials,
  }),
});

server.listen(config.port, '0.0.0.0', () => {
  console.info(
    JSON.stringify({
      level: 'info',
      event: 'relay_started',
      port: config.port,
      firebaseProjectId: config.firebaseProjectId,
    })
  );
});

const shutdown = () => server.close(() => process.exit(0));
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

import { randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { firebaseErrorStatus } from './firebase.js';

const MAX_BODY_BYTES = 1024 * 1024;

const json = (response, status, body) => {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(body));
};

const authorized = (header, expectedToken) => {
  const provided = header?.startsWith('Bearer ') ? header.slice(7) : '';
  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expectedToken);
  return (
    providedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(providedBuffer, expectedBuffer)
  );
};

const readJson = request =>
  new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let settled = false;
    request.on('data', chunk => {
      if (settled) return;
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        settled = true;
        reject(Object.assign(new Error('Payload too large'), { status: 413 }));
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => {
      if (settled) return;
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(Object.assign(new Error('Invalid JSON'), { status: 400 }));
      }
    });
    request.on('error', error => {
      if (!settled) reject(error);
    });
  });

const validatePayload = payload => {
  if (!payload || typeof payload !== 'object') return false;
  if (!payload.installation_id || typeof payload.installation_id !== 'string')
    return false;
  if (
    !payload.device?.push_token ||
    typeof payload.device.push_token !== 'string'
  )
    return false;
  if (!payload.notification || typeof payload.notification !== 'object')
    return false;
  return (
    typeof payload.notification.title === 'string' &&
    typeof payload.notification.body === 'string' &&
    (!payload.notification.data ||
      typeof payload.notification.data === 'object')
  );
};

export const buildServer = ({ relayToken, firebaseProjectId, sendPush }) =>
  createServer(async (request, response) => {
    const requestId = request.headers['x-request-id'] || randomUUID();
    response.setHeader('X-Request-Id', requestId);

    if (request.method === 'GET' && request.url === '/healthz') {
      json(response, 200, {
        status: 'ok',
        firebaseProjectId,
      });
      return;
    }

    if (request.method !== 'POST' || request.url !== '/v1/push') {
      json(response, 404, { error: 'Not found', requestId });
      return;
    }

    if (!authorized(request.headers.authorization, relayToken)) {
      json(response, 401, { error: 'Unauthorized', requestId });
      return;
    }

    try {
      const payload = await readJson(request);
      if (!validatePayload(payload)) {
        json(response, 422, { error: 'Invalid push payload', requestId });
        return;
      }

      const result = await sendPush(payload);
      console.info(
        JSON.stringify({
          level: 'info',
          event: 'push_sent',
          requestId,
          installationId: payload.installation_id,
          deviceId: payload.device.device_id,
        })
      );
      json(response, 202, { accepted: true, message: result?.name, requestId });
    } catch (error) {
      const status = error.status || firebaseErrorStatus(error);
      console.error(
        JSON.stringify({
          level: 'error',
          event: 'push_failed',
          requestId,
          status,
          error: error.message,
        })
      );
      json(response, status, { error: 'Push delivery failed', requestId });
    }
  });

export const serverTestUtils = { authorized, validatePayload };

/**
 * LockSync WebSocket Relay Server
 *
 * Architecture: Thin relay — the server exists ONLY to:
 *   1. Generate & validate 6-digit pairing codes
 *   2. Issue JWTs after successful pairing
 *   3. Forward message deltas between paired devices in real-time
 *
 * No messages are stored. No database needed. This is as close to
 * peer-to-peer as you can get while still routing over the internet.
 * The VPS is a "secure postman" — it authenticates the pair, then
 * blindly forwards sealed envelopes between them.
 */

require('dotenv').config();
const http = require('http');
const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');

// ─── Config ──────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT, 10) || 8080;
const JWT_SECRET = process.env.JWT_SECRET || (() => {
  console.error('FATAL: JWT_SECRET is not set. Exiting.');
  process.exit(1);
})();
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '*').split(',').map(s => s.trim());
const PAIR_CODE_TTL = parseInt(process.env.PAIR_CODE_TTL, 10) || 300;       // seconds
const JWT_EXPIRY = process.env.JWT_EXPIRY || '7d';
const JWT_REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || '30d';
const PAIR_RATE_LIMIT = parseInt(process.env.PAIR_RATE_LIMIT, 10) || 10;
const MAX_MESSAGE_SIZE = parseInt(process.env.MAX_MESSAGE_SIZE, 10) || 16384;

// ─── In-memory stores (no DB needed for a relay) ────────────────────
/** Pending pairing codes: code → { deviceId, createdAt, ws } */
const pairingCodes = new Map();

/** Active pairs: pairId → { deviceA: { id, ws }, deviceB: { id, ws } } */
const activePairs = new Map();

/** Device → pairId lookup for fast disconnect cleanup */
const deviceToPair = new Map();

/** Rate limiter: IP → { count, windowStart } */
const rateLimits = new Map();

// ─── HTTP server (health check + upgrade) ────────────────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      pairs: activePairs.size,
      pendingCodes: pairingCodes.size,
      uptime: process.uptime(),
    }));
    return;
  }
  res.writeHead(404);
  res.end();
});

// ─── WebSocket server ────────────────────────────────────────────────
const wss = new WebSocketServer({
  server,
  maxPayload: MAX_MESSAGE_SIZE,
  verifyClient: ({ req }, done) => {
    // Origin validation
    if (ALLOWED_ORIGINS[0] !== '*') {
      const origin = req.headers.origin;
      if (!origin || !ALLOWED_ORIGINS.includes(origin)) {
        done(false, 403, 'Origin not allowed');
        return;
      }
    }
    done(true);
  },
});

wss.on('connection', (ws, req) => {
  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress;
  ws._ip = ip;
  ws._deviceId = null;
  ws._pairId = null;
  ws._authenticated = false;

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      sendError(ws, 'INVALID_JSON', 'Message must be valid JSON');
      return;
    }

    if (!msg.type) {
      sendError(ws, 'MISSING_TYPE', 'Message must have a "type" field');
      return;
    }

    switch (msg.type) {
      case 'request_code':
        handleRequestCode(ws, msg);
        break;
      case 'join_code':
        handleJoinCode(ws, msg, ip);
        break;
      case 'authenticate':
        handleAuthenticate(ws, msg);
        break;
      case 'refresh_token':
        handleRefreshToken(ws, msg);
        break;
      case 'sync':
        handleSync(ws, msg);
        break;
      case 'ping':
        send(ws, { type: 'pong', ts: Date.now() });
        break;
      default:
        sendError(ws, 'UNKNOWN_TYPE', `Unknown message type: ${msg.type}`);
    }
  });

  ws.on('close', () => handleDisconnect(ws));
  ws.on('error', () => handleDisconnect(ws));
});

// ─── Pairing: Device A requests a code ───────────────────────────────
function handleRequestCode(ws, msg) {
  const deviceId = msg.deviceId;
  if (!deviceId || typeof deviceId !== 'string' || deviceId.length < 8) {
    sendError(ws, 'INVALID_DEVICE_ID', 'Provide a valid deviceId (min 8 chars)');
    return;
  }

  // Clean up any existing code from this device
  for (const [code, entry] of pairingCodes) {
    if (entry.deviceId === deviceId) {
      pairingCodes.delete(code);
    }
  }

  const code = generatePairCode();
  pairingCodes.set(code, {
    deviceId,
    createdAt: Date.now(),
    ws,
  });

  ws._deviceId = deviceId;

  // Auto-expire the code
  setTimeout(() => {
    if (pairingCodes.has(code)) {
      const entry = pairingCodes.get(code);
      pairingCodes.delete(code);
      if (entry.ws.readyState === 1) {
        send(entry.ws, { type: 'code_expired', code });
      }
    }
  }, PAIR_CODE_TTL * 1000);

  send(ws, { type: 'code_created', code, expiresIn: PAIR_CODE_TTL });
  console.log(`[PAIR] Code ${code} created for device ${deviceId.slice(0, 8)}…`);
}

// ─── Pairing: Device B joins with a code ─────────────────────────────
function handleJoinCode(ws, msg, ip) {
  // Rate limiting
  if (!checkRateLimit(ip)) {
    sendError(ws, 'RATE_LIMITED', 'Too many pairing attempts. Try again later.');
    return;
  }

  const { code, deviceId } = msg;
  if (!code || !deviceId || typeof deviceId !== 'string' || deviceId.length < 8) {
    sendError(ws, 'INVALID_REQUEST', 'Provide code and deviceId');
    return;
  }

  const entry = pairingCodes.get(code);
  if (!entry) {
    sendError(ws, 'INVALID_CODE', 'Code not found or expired');
    return;
  }

  if (entry.deviceId === deviceId) {
    sendError(ws, 'SELF_PAIR', 'Cannot pair with yourself');
    return;
  }

  // Check expiry
  if (Date.now() - entry.createdAt > PAIR_CODE_TTL * 1000) {
    pairingCodes.delete(code);
    sendError(ws, 'CODE_EXPIRED', 'Pairing code has expired');
    return;
  }

  // Consume the code
  pairingCodes.delete(code);

  // Create the pair
  const pairId = uuidv4();
  const pair = {
    deviceA: { id: entry.deviceId, ws: entry.ws },
    deviceB: { id: deviceId, ws },
  };
  activePairs.set(pairId, pair);
  deviceToPair.set(entry.deviceId, pairId);
  deviceToPair.set(deviceId, pairId);

  ws._deviceId = deviceId;
  ws._pairId = pairId;
  entry.ws._pairId = pairId;

  // Issue JWTs to both devices
  const tokenA = issueTokens(entry.deviceId, pairId);
  const tokenB = issueTokens(deviceId, pairId);

  send(entry.ws, {
    type: 'paired',
    pairId,
    partnerId: deviceId,
    ...tokenA,
  });

  send(ws, {
    type: 'paired',
    pairId,
    partnerId: entry.deviceId,
    ...tokenB,
  });

  entry.ws._authenticated = true;
  ws._authenticated = true;

  console.log(`[PAIR] Pair ${pairId.slice(0, 8)}… established: ${entry.deviceId.slice(0, 8)}… ↔ ${deviceId.slice(0, 8)}…`);
}

// ─── Auth: reconnect with existing JWT ───────────────────────────────
function handleAuthenticate(ws, msg) {
  const { token } = msg;
  if (!token) {
    sendError(ws, 'MISSING_TOKEN', 'Provide a JWT token');
    return;
  }

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (err) {
    sendError(ws, 'INVALID_TOKEN', 'Token invalid or expired');
    return;
  }

  if (payload.tokenType !== 'access') {
    sendError(ws, 'WRONG_TOKEN_TYPE', 'Use an access token, not a refresh token');
    return;
  }

  const { deviceId, pairId } = payload;
  const pair = activePairs.get(pairId);

  if (!pair) {
    // Pair no longer active on server (server restarted, etc.)
    // Client should re-pair
    sendError(ws, 'PAIR_NOT_FOUND', 'Pair session expired. Please re-pair.');
    return;
  }

  // Re-attach this WebSocket to the pair
  ws._deviceId = deviceId;
  ws._pairId = pairId;
  ws._authenticated = true;

  if (pair.deviceA.id === deviceId) {
    pair.deviceA.ws = ws;
  } else if (pair.deviceB.id === deviceId) {
    pair.deviceB.ws = ws;
  } else {
    sendError(ws, 'DEVICE_MISMATCH', 'Device not part of this pair');
    return;
  }

  deviceToPair.set(deviceId, pairId);

  const partnerId = pair.deviceA.id === deviceId ? pair.deviceB.id : pair.deviceA.id;

  send(ws, {
    type: 'authenticated',
    pairId,
    partnerId,
    partnerOnline: getPartnerWs(pair, deviceId)?.readyState === 1,
  });

  // Notify partner that we're back online
  const partnerWs = getPartnerWs(pair, deviceId);
  if (partnerWs?.readyState === 1) {
    send(partnerWs, { type: 'partner_online' });
  }

  console.log(`[AUTH] Device ${deviceId.slice(0, 8)}… reconnected to pair ${pairId.slice(0, 8)}…`);
}

// ─── Token refresh ───────────────────────────────────────────────────
function handleRefreshToken(ws, msg) {
  const { refreshToken } = msg;
  if (!refreshToken) {
    sendError(ws, 'MISSING_TOKEN', 'Provide a refreshToken');
    return;
  }

  let payload;
  try {
    payload = jwt.verify(refreshToken, JWT_SECRET);
  } catch {
    sendError(ws, 'INVALID_REFRESH_TOKEN', 'Refresh token invalid or expired');
    return;
  }

  if (payload.tokenType !== 'refresh') {
    sendError(ws, 'WRONG_TOKEN_TYPE', 'Use a refresh token');
    return;
  }

  const tokens = issueTokens(payload.deviceId, payload.pairId);
  send(ws, { type: 'token_refreshed', ...tokens });
}

// ─── Sync: forward message delta to partner ──────────────────────────
function handleSync(ws, msg) {
  if (!ws._authenticated) {
    sendError(ws, 'UNAUTHENTICATED', 'Authenticate first');
    return;
  }

  const pair = activePairs.get(ws._pairId);
  if (!pair) {
    sendError(ws, 'PAIR_NOT_FOUND', 'Pair no longer active');
    return;
  }

  const partnerWs = getPartnerWs(pair, ws._deviceId);
  if (!partnerWs || partnerWs.readyState !== 1) {
    send(ws, { type: 'partner_offline' });
    return;
  }

  // Forward the payload directly — zero inspection, maximum speed.
  // The server is a dumb pipe. Payload structure is between the clients.
  send(partnerWs, {
    type: 'sync',
    from: ws._deviceId,
    payload: msg.payload,
    ts: Date.now(),
  });
}

// ─── Disconnect cleanup ──────────────────────────────────────────────
function handleDisconnect(ws) {
  if (!ws._deviceId) return;

  const pairId = ws._pairId || deviceToPair.get(ws._deviceId);
  if (!pairId) return;

  const pair = activePairs.get(pairId);
  if (!pair) return;

  // Notify partner of disconnect (but DON'T destroy the pair — they can reconnect)
  const partnerWs = getPartnerWs(pair, ws._deviceId);
  if (partnerWs?.readyState === 1) {
    send(partnerWs, { type: 'partner_offline' });
  }

  console.log(`[DC] Device ${ws._deviceId.slice(0, 8)}… disconnected from pair ${pairId.slice(0, 8)}…`);
}

// ─── Helpers ─────────────────────────────────────────────────────────
function generatePairCode() {
  let code;
  do {
    code = String(Math.floor(100000 + Math.random() * 900000));
  } while (pairingCodes.has(code));
  return code;
}

function issueTokens(deviceId, pairId) {
  const accessToken = jwt.sign(
    { deviceId, pairId, tokenType: 'access' },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
  const refreshToken = jwt.sign(
    { deviceId, pairId, tokenType: 'refresh' },
    JWT_SECRET,
    { expiresIn: JWT_REFRESH_EXPIRY }
  );
  return { accessToken, refreshToken };
}

function getPartnerWs(pair, myDeviceId) {
  return pair.deviceA.id === myDeviceId ? pair.deviceB.ws : pair.deviceA.ws;
}

function send(ws, data) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

function sendError(ws, code, message) {
  send(ws, { type: 'error', code, message });
}

function checkRateLimit(ip) {
  const now = Date.now();
  const entry = rateLimits.get(ip);

  if (!entry || now - entry.windowStart > 60000) {
    rateLimits.set(ip, { count: 1, windowStart: now });
    return true;
  }

  entry.count++;
  if (entry.count > PAIR_RATE_LIMIT) {
    return false;
  }
  return true;
}

// ─── Periodic cleanup ────────────────────────────────────────────────
setInterval(() => {
  const now = Date.now();

  // Clean expired pairing codes
  for (const [code, entry] of pairingCodes) {
    if (now - entry.createdAt > PAIR_CODE_TTL * 1000) {
      pairingCodes.delete(code);
    }
  }

  // Clean stale pairs (both devices disconnected for > 1 hour)
  for (const [pairId, pair] of activePairs) {
    const aAlive = pair.deviceA.ws?.readyState === 1;
    const bAlive = pair.deviceB.ws?.readyState === 1;
    if (!aAlive && !bAlive) {
      if (!pair._bothOfflineSince) {
        pair._bothOfflineSince = now;
      } else if (now - pair._bothOfflineSince > 3600000) {
        activePairs.delete(pairId);
        deviceToPair.delete(pair.deviceA.id);
        deviceToPair.delete(pair.deviceB.id);
        console.log(`[CLEANUP] Pair ${pairId.slice(0, 8)}… removed (both offline > 1h)`);
      }
    } else {
      pair._bothOfflineSince = null;
    }
  }

  // Clean rate limit entries older than 2 minutes
  for (const [ip, entry] of rateLimits) {
    if (now - entry.windowStart > 120000) {
      rateLimits.delete(ip);
    }
  }
}, 60000);

// ─── Start ───────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(`[LockSync] WebSocket relay server running on port ${PORT}`);
  console.log(`[LockSync] Health check: http://localhost:${PORT}/health`);
});

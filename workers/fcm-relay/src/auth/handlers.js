// Auth routes:
//   POST /auth/telegram      — Telegram Login Widget (one-tap sign-in)
//   POST /auth/whatsapp/start — WhatsApp OTP start
//   POST /auth/whatsapp/verify — WhatsApp OTP verify
//
// Telegram widget hash validation lives in ./telegram.js (this dir).
// Mini App init data validation (used by WhatsApp OTP path) lives in ../otp/telegram.js.

import { putCode, getCode, deleteCode, bumpCounter, getTelegramChat, putTelegramChat, randomCode, sha256Hex, timingSafeEqual } from '../otp/kv.js';
import { sendTelegramCode, validateTelegramInitData } from '../otp/telegram.js';
import { sendWhatsAppCode } from '../otp/whatsapp.js';
import { createCustomToken } from '../otp/custom_token.js';
import { validateTelegramHash } from './telegram.js';

const E164 = /^\+[1-9]\d{7,14}$/;
const ALLOWED_PROVIDERS = new Set(['telegram', 'whatsapp']);

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export async function handleWhatsappStart(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'bad_json' }, 400);
  }
  const { phone, provider, telegramInitData } = body || {};
  if (!E164.test(phone) || !ALLOWED_PROVIDERS.has(provider)) {
    return json({ error: 'bad_request' }, 400);
  }
  const startCount = await bumpCounter(env, 'start', phone);
  if (startCount > 5) return json({ error: 'rate_limited' }, 429);

  const code = randomCode();
  const verificationId = await sha256Hex(`${phone}:${provider}:${Date.now()}:${code}`);
  await putCode(env, `${provider}:${verificationId}:${phone}`, code);

  if (provider === 'telegram') {
    if (telegramInitData) {
      const ok = await validateTelegramInitData(telegramInitData, env.TELEGRAM_BOT_TOKEN);
      if (!ok) return json({ error: 'bad_init_data' }, 400);
      const url = new URLSearchParams(telegramInitData);
      const user = JSON.parse(url.get('user') || '{}');
      if (user.id) await putTelegramChat(env, phone, user.id);
    }
    const chatId = await getTelegramChat(env, phone);
    if (!chatId) return json({ error: 'bot_not_started' }, 409);
    await sendTelegramCode(env, chatId, code);
  } else {
    await sendWhatsAppCode(env, phone, code);
  }

  return json({ verificationId, expiresInSeconds: 300 });
}

export async function handleWhatsappVerify(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'bad_json' }, 400);
  }
  const { phone, provider, verificationId, code } = body || {};
  if (!E164.test(phone) || !ALLOWED_PROVIDERS.has(provider) || !verificationId || !code) {
    return json({ error: 'bad_request' }, 400);
  }
  const verifyCount = await bumpCounter(env, 'verify', phone);
  if (verifyCount > 10) return json({ error: 'rate_limited' }, 429);

  const stored = await getCode(env, `${provider}:${verificationId}:${phone}`);
  if (!stored) return json({ error: 'expired' }, 400);
  if (!timingSafeEqual(stored, code)) return json({ error: 'bad_code' }, 400);

  await deleteCode(env, `${provider}:${verificationId}:${phone}`);
  const uid = await sha256Hex(phone);
  const customToken = await createCustomToken(env, uid);
  return json({ customToken, uid, isNewUser: false });
}

// POST /auth/telegram — Telegram Login Widget callback.
// Body: { id, first_name, last_name?, username?, photo_url?, auth_date, hash }
//
// Validates the hash using the official Login Widget algorithm, then
// looks up / creates the Firebase user keyed by `telegram:<id>` and
// returns a Firebase custom token the Flutter app can exchange for a session.
export async function handleTelegramLogin(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'bad_json' }, 400);
  }
  if (!body || typeof body !== 'object') {
    return json({ error: 'bad_request' }, 400);
  }
  const { id, first_name, last_name, username, photo_url, auth_date, hash } = body;
  if (id == null || !first_name || !auth_date || !hash) {
    return json({ error: 'missing_fields' }, 400);
  }
  const ok = await validateTelegramHash(body, env.TELEGRAM_BOT_TOKEN);
  if (!ok) {
    return json({ error: 'invalid_hash' }, 401);
  }
  const uid = `telegram:${id}`;
  const isNewUser = await upsertTelegramUser(env, {
    uid,
    telegramId: id,
    firstName: first_name,
    lastName: last_name || '',
    username,
    photoUrl: photo_url,
    authDate: auth_date,
  });
  const customToken = await createCustomToken(env, uid);
  return json({ customToken, uid, isNewUser });
}

// ---- Firestore user upsert for Telegram users ----
//
// Uses the Firestore REST API with an OAuth2 access token minted from
// the service account (FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY).
// Reuses the same JWT-bearer token pattern as the main relay index.js.

async function getAccessToken(env) {
  const FIREBASE_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';
  const b64url = (bytes) =>
    btoa(String.fromCharCode(...new Uint8Array(bytes)))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  const pemToPkcs8 = (pem) => {
    const b64 = pem
      .replace(/-----BEGIN PRIVATE KEY-----/, '')
      .replace(/-----END PRIVATE KEY-----/, '')
      .replace(/\\n/g, '\n')
      .replace(/[^\nA-Za-z0-9+/=]/g, '');
    const raw = atob(b64);
    const buf = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
    return buf.buffer;
  };
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({
    iss: env.FIREBASE_CLIENT_EMAIL,
    scope: FIREBASE_SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(env.FIREBASE_PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status}`);
  const j = await res.json();
  return j.access_token;
}

function encodeField(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    return Number.isInteger(val) ? { integerValue: String(val) } : { doubleValue: val };
  }
  return { stringValue: String(val) };
}

function encodeFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) fields[k] = encodeField(v);
  return fields;
}

async function upsertTelegramUser(env, { uid, telegramId, firstName, lastName, username, photoUrl, authDate }) {
  const FIRESTORE_HOST = 'firestore.googleapis.com';
  const accessToken = await getAccessToken(env);
  const docUrl = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${encodeURIComponent(uid)}`;
  const headRes = await fetch(docUrl, { headers: { Authorization: `Bearer ${accessToken}` } });
  const isNewUser = headRes.status === 404;
  const nowMs = Date.now();
  const displayName = `${firstName} ${lastName}`.trim();
  const data = {
    phone: null,
    role: 'collector',
    telegramId,
    displayName,
    lastLoginAt: nowMs,
  };
  if (isNewUser) data.createdAt = nowMs;
  if (username) data.username = username;
  if (photoUrl) data.photoUrl = photoUrl;
  if (authDate) data.authDate = authDate;
  const fields = encodeFields(data);
  const mask = Object.keys(data).map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  const patchUrl = `${docUrl}?${mask}`;
  const patchRes = await fetch(patchUrl, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!patchRes.ok) {
    throw new Error(`firestore upsert failed: ${patchRes.status} ${await patchRes.text()}`);
  }
  return isNewUser;
}

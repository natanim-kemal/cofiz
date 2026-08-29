// Telegram Login Widget hash validation.
// See https://core.telegram.org/bots/api#loginwidget.
//
// Algorithm:
//   1. data_check_string = sorted key=value pairs (excluding `hash`), joined by \n
//   2. secret_key        = sha256(bot_token)
//   3. hash              = hmac_sha256(secret_key, data_check_string)
//
// Distinct from the Telegram Mini App init data check (WebAppData) which is
// handled in src/otp/telegram.js. Kept in a separate file/module on purpose.

export async function sha256Bytes(input) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input)));
}

export function toHex(bytes) {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function buildDataCheckString(fields) {
  // `fields` is an object. The Telegram spec requires sorted (key, value) pairs,
  // joined with '\n', excluding the `hash` key itself.
  const entries = Object.entries(fields)
    .filter(([k]) => k !== 'hash')
    .map(([k, v]) => [k, String(v ?? '')])
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return entries.map(([k, v]) => `${k}=${v}`).join('\n');
}

export async function computeTelegramHash(fields, botToken) {
  const dataCheckString = buildDataCheckString(fields);
  const secretKey = await sha256Bytes(botToken);
  const hmacKey = await crypto.subtle.importKey(
    'raw',
    secretKey,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    hmacKey,
    new TextEncoder().encode(dataCheckString),
  );
  return toHex(new Uint8Array(sig));
}

export async function validateTelegramHash(fields, botToken) {
  if (!fields || typeof fields !== 'object') return false;
  if (fields.id == null) return false;
  if (!fields.hash || typeof fields.hash !== 'string') return false;
  const expected = await computeTelegramHash(fields, botToken);
  return timingSafeEqualHex(expected, fields.hash);
}

// Constant-time hex comparison. Pads to the same length first.
function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// Re-export helpers for tests
export { buildDataCheckString, timingSafeEqualHex };

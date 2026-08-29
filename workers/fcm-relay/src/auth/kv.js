// Shared KV helpers for the auth routes.
const CODE_TTL = 300;       // 5 min
const RL_TTL = 3600;        // 1 hour

export async function putCode(env, key, code) {
  await env.OTP_KV.put(`otp:${key}`, code, { expirationTtl: CODE_TTL });
}
export async function getCode(env, key) {
  return env.OTP_KV.get(`otp:${key}`);
}
export async function deleteCode(env, key) {
  return env.OTP_KV.delete(`otp:${key}`);
}

export async function bumpCounter(env, name, key) {
  const k = `rl:${name}:${key}`;
  const cur = parseInt((await env.OTP_KV.get(k)) || '0', 10);
  const next = cur + 1;
  await env.OTP_KV.put(k, String(next), { expirationTtl: RL_TTL });
  return next;
}

export async function putTelegramChat(env, phone, chatId) {
  await env.OTP_KV.put(`tg:phone:${phone}`, String(chatId));
}
export async function getTelegramChat(env, phone) {
  const v = await env.OTP_KV.get(`tg:phone:${phone}`);
  return v ? Number(v) : null;
}

export function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function randomCode() {
  const n = Math.floor(Math.random() * 1_000_000);
  return String(n).padStart(6, '0');
}

export async function sha256Hex(input) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

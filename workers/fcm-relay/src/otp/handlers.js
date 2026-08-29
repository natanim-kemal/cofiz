import { putCode, getCode, deleteCode, bumpCounter, getTelegramChat, putTelegramChat, randomCode, sha256Hex, timingSafeEqual } from './kv.js';
import { sendTelegramCode, validateTelegramInitData } from './telegram.js';
import { sendWhatsAppCode } from './whatsapp.js';
import { createCustomToken } from './custom_token.js';

const ALLOWED_PROVIDERS = new Set(['telegram', 'whatsapp']);
const E164 = /^\+[1-9]\d{7,14}$/;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export async function handleStart(request, env) {
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

export async function handleVerify(request, env) {
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

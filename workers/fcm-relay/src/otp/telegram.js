export async function sendTelegramCode(env, chatId, code) {
  const text = `Cofiz verification code: ${code}. Valid for 5 minutes.`;
  const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text }),
  });
  if (!res.ok) {
    throw new Error(`telegram ${res.status}`);
  }
}

export function validateTelegramInitData(initData, botToken) {
  const url = new URLSearchParams(initData);
  const hash = url.get('hash');
  url.delete('hash');
  const dataCheckString = [...url.entries()].map(([k, v]) => `${k}=${v}`).sort().join('\n');
  return crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode('WebAppData'),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  ).then((key) => crypto.subtle.sign('HMAC', key, new TextEncoder().encode(botToken)))
    .then((secret) => crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']))
    .then((key) => crypto.subtle.sign('HMAC', key, new TextEncoder().encode(dataCheckString)))
    .then((sig) => Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('') === hash);
}

// TDD for Task 7 — Telegram Login Widget hash validation.
// Run with: node test/auth/handlers_test.js
//
// We exercise the pure `validateTelegramHash` / `computeTelegramHash` helpers
// by importing the auth module. The handler that uses them needs Cloudflare
// `env` bindings and is covered manually via `wrangler dev`.
//
// `crypto.subtle` is available in Node 20+ via `node:crypto`. The worker
// uses the same WebCrypto API so the validation logic is environment-agnostic.

import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';

// Make WebCrypto globally available — matches the Cloudflare Workers
// environment where `crypto.subtle` is a global.
if (!globalThis.crypto) {
  globalThis.crypto = webcrypto;
}

const { validateTelegramHash, computeTelegramHash, buildDataCheckString } =
  await import('../../src/auth/telegram.js');

// Known bot token (test-only) and the standard set of widget fields.
const BOT_TOKEN = '5768337698:AAH5Y7t9oT6XR_lIq5O9C7bW4Kq5Yq1X2XI';

const baseFields = {
  id: 313131,
  first_name: 'Name',
  username: 'username',
  photo_url: 'https://t.me/i/userpic/320/name.jpg',
  auth_date: 1657994581,
};

// Helper: produce a fresh, valid fields object with a freshly-computed hash.
async function freshFields(overrides = {}) {
  const f = { ...baseFields, ...overrides };
  f.hash = await computeTelegramHash(f, BOT_TOKEN);
  return f;
}

// ---- Tests ----

console.log('Testing buildDataCheckString...');
{
  // Sorting + key=value joined by \n, excluding `hash`.
  const s = buildDataCheckString({
    id: 313131,
    first_name: 'Name',
    hash: 'should-be-excluded',
  });
  // Sorted alphabetically: first_name, id
  assert.equal(s, 'first_name=Name\nid=313131');
}
{
  // All string values are stringified; missing fields omitted.
  const s = buildDataCheckString({ b: 2, a: 1, c: null });
  assert.equal(s, 'a=1\nb=2\nc=');
}
console.log('✓ buildDataCheckString');

console.log('Testing validateTelegramHash — valid...');
{
  const f = await freshFields();
  assert.equal(await validateTelegramHash(f, BOT_TOKEN), true);
}
console.log('✓ valid hash');

console.log('Testing validateTelegramHash — invalid hash...');
{
  const f = await freshFields();
  f.hash = '0'.repeat(64);
  assert.equal(await validateTelegramHash(f, BOT_TOKEN), false);
}
console.log('✓ invalid hash');

console.log('Testing validateTelegramHash — missing id...');
{
  const f = { first_name: 'Name', auth_date: 1, hash: 'abc' };
  assert.equal(await validateTelegramHash(f, BOT_TOKEN), false);
}
console.log('✓ missing id');

console.log('Testing validateTelegramHash — missing hash...');
{
  const f = { id: 1, first_name: 'Name', auth_date: 1 };
  assert.equal(await validateTelegramHash(f, BOT_TOKEN), false);
}
console.log('✓ missing hash');

console.log('Testing validateTelegramHash — wrong bot token...');
{
  const f = await freshFields();
  assert.equal(await validateTelegramHash(f, 'wrong:token'), false);
}
console.log('✓ wrong bot token');

console.log('Testing validateTelegramHash — tampered field...');
{
  const f = await freshFields();
  f.first_name = 'Other';
  // Hash was computed for 'Name'; tampering makes it invalid.
  assert.equal(await validateTelegramHash(f, BOT_TOKEN), false);
}
console.log('✓ tampered field');

console.log('Testing validateTelegramHash — non-object...');
{
  assert.equal(await validateTelegramHash(null, BOT_TOKEN), false);
  assert.equal(await validateTelegramHash('not-an-object', BOT_TOKEN), false);
}
console.log('✓ non-object');

console.log('All auth/handlers tests passed.');

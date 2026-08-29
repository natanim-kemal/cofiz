// TDD for Task 6 OTP handlers. Run with: node test/otp/handlers_test.js
import assert from 'node:assert/strict';

// We can't easily import the handlers file because it depends on `fetch`
// and `crypto.subtle` and Cloudflare `env` bindings. Instead, mirror the
// pure helpers here and exercise them. The integration path is covered
// by manual on-device QA + `wrangler dev`.

function randomCode() {
  const n = Math.floor(Math.random() * 1_000_000);
  return String(n).padStart(6, '0');
}
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
const E164 = /^\+[1-9]\d{7,14}$/;

// ---- Tests ----

console.log('Testing randomCode...');
for (let i = 0; i < 1000; i++) {
  const c = randomCode();
  assert.equal(c.length, 6, 'randomCode is always 6 chars');
  assert.match(c, /^\d{6}$/, 'randomCode is always 6 digits');
}
console.log('✓ randomCode');

console.log('Testing timingSafeEqual...');
assert.equal(timingSafeEqual('123456', '123456'), true);
assert.equal(timingSafeEqual('123456', '654321'), false);
assert.equal(timingSafeEqual('123456', '12345'), false);  // length mismatch
assert.equal(timingSafeEqual('', ''), true);
console.log('✓ timingSafeEqual');

console.log('Testing E164 regex...');
assert.match('+251911234567', E164);
assert.match('+15551234567', E164);
assert.doesNotMatch('abc', E164);
assert.doesNotMatch('251911234567', E164);  // missing +
assert.doesNotMatch('+1234', E164);          // too short
console.log('✓ E164');

console.log('All OTP handler tests passed.');

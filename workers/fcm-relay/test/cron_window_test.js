// TDD for Task 5 cron helpers: window calc, Addis bounds, hasTransactionToday
// Run with: node test/cron_window_test.js

import assert from 'node:assert/strict';

// Import helpers from src/index.js (ESM) — copy pure functions here if import fails in plain node.
// For portability we inline the same logic (kept in sync with src/index.js).

function parseTimeToMinutes(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  if (Number.isNaN(h) || Number.isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}
function isInWindow(baseTimeStr, nowMinutes) {
  const baseMin = parseTimeToMinutes(baseTimeStr);
  if (baseMin === null) return false;
  const offsets = [0, 30, 60];
  return offsets.some((o) => nowMinutes === baseMin + o);
}
function getAddisNow(date = new Date()) {
  return new Date(date.toLocaleString('en-US', { timeZone: 'Africa/Addis_Ababa' }));
}
function formatAddisDate(addisNow) {
  const y = addisNow.getFullYear();
  const m = String(addisNow.getMonth() + 1).padStart(2, '0');
  const d = String(addisNow.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}
function getAddisDayBoundsMs(addisNow) {
  const y = addisNow.getFullYear();
  const m = addisNow.getMonth();
  const d = addisNow.getDate();
  const startMs = Date.UTC(y, m, d) - 3 * 3600 * 1000;
  const endMs = startMs + 24 * 3600 * 1000;
  return { startMs, endMs };
}

// Mock hasTransactionToday logic: builds query bounds and checks overlap
function hasTransactionOnDay(transactions, addisNow) {
  const { startMs, endMs } = getAddisDayBoundsMs(addisNow);
  return transactions.some((t) => t.createdAt >= startMs && t.createdAt < endMs);
}

// ---- Tests ----

console.log('Testing parseTimeToMinutes / isInWindow...');
assert.equal(parseTimeToMinutes('20:00'), 1200);
assert.equal(parseTimeToMinutes('09:30'), 570);
assert.equal(parseTimeToMinutes('07:05'), 425);
assert.equal(parseTimeToMinutes('24:00'), null);
assert.equal(parseTimeToMinutes('ab:cd'), null);

assert.equal(isInWindow('20:00', 1200), true); // base
assert.equal(isInWindow('20:00', 1230), true); // +30
assert.equal(isInWindow('20:00', 1260), true); // +60
assert.equal(isInWindow('20:00', 1215), false);
assert.equal(isInWindow('20:00', 1290), false);
assert.equal(isInWindow('09:00', 540), true);
assert.equal(isInWindow('09:00', 570), true);
assert.equal(isInWindow('09:00', 600), true);
assert.equal(isInWindow('09:00', 541), false);
assert.equal(isInWindow('invalid', 540), false);
console.log('✓ window calc');

console.log('Testing Addis bounds & hasTransactionToday...');
{
  // Addis 2026-08-28 10:00 EAT = 07:00 UTC. Use a fixed UTC instant.
  const utcInstant = new Date(Date.UTC(2026, 7, 28, 7, 0, 0)); // 2026-08-28 07:00 UTC
  const addisNow = getAddisNow(utcInstant);
  // Addis wall time should be 10:00 same calendar date 2026-08-28
  assert.equal(addisNow.getHours(), 10);
  assert.equal(formatAddisDate(addisNow), '2026-08-28');
  const { startMs, endMs } = getAddisDayBoundsMs(addisNow);
  // startMs should be Addis midnight 2026-08-28 00:00 EAT = 2026-08-27 21:00 UTC
  assert.equal(startMs, Date.UTC(2026, 7, 27, 21, 0, 0));
  assert.equal(endMs, Date.UTC(2026, 7, 28, 21, 0, 0));

  const txInside = { createdAt: Date.UTC(2026, 7, 28, 8, 0, 0) }; // 11:00 EAT same day -> inside
  const txOutsideBefore = { createdAt: Date.UTC(2026, 7, 27, 20, 0, 0) }; // 23:00 EAT previous day -> outside
  const txOutsideAfter = { createdAt: Date.UTC(2026, 7, 28, 22, 0, 0) }; // 01:00 EAT next day -> outside
  assert.equal(hasTransactionOnDay([txInside], addisNow), true);
  assert.equal(hasTransactionOnDay([txOutsideBefore], addisNow), false);
  assert.equal(hasTransactionOnDay([txOutsideAfter], addisNow), false);
  assert.equal(hasTransactionOnDay([], addisNow), false);
  assert.equal(hasTransactionOnDay([txOutsideBefore, txInside], addisNow), true);
}
{
  // Edge: transaction exactly at startMs inclusive, endMs exclusive
  const addisNow = new Date(2026, 7, 28, 10, 0, 0); // local, but get bounds via same wall date
  // Force addisNow to have correct date; use getAddisDayBoundsMs directly
  const { startMs, endMs } = getAddisDayBoundsMs(new Date(2026, 7, 28, 12, 0, 0));
  // Actually craft addisNow wall date 2026-08-28
  const wall = new Date(2026, 7, 28, 12, 0, 0);
  const bounds = getAddisDayBoundsMs(wall);
  assert.equal(hasTransactionOnDay([{ createdAt: bounds.startMs }], wall), true);
  assert.equal(hasTransactionOnDay([{ createdAt: bounds.endMs }], wall), false);
  assert.equal(hasTransactionOnDay([{ createdAt: bounds.endMs - 1 }], wall), true);
}
console.log('✓ hasTransactionToday bounds');

console.log('All cron_window tests passed.');

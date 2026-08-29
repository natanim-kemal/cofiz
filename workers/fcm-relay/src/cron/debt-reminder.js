// Daily debt reminder — runs inside the existing scheduled handler (every 30 min)
// Query: debts where status != 'paid', group by collector, send one digest per admin/viewer
// Time: 09:00 Africa/Addis_Ababa (06:00 UTC, no DST)
// Uses Firestore REST helpers from src/index.js (getAccessToken, runQuery etc. are inlined here for isolation)

const FIRESTORE_HOST = "firestore.googleapis.com";

function decodeField(v) {
  if (v == null) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('booleanValue' in v) return v.booleanValue === true || v.booleanValue === 'true';
  return null;
}
function decodeDoc(doc) {
  if (!doc || !doc.fields) return null;
  const out = {};
  for (const [k, v] of Object.entries(doc.fields)) out[k] = decodeField(v);
  return out;
}

async function runQuery(env, accessToken, structuredQuery) {
  const url = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:runQuery`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery }),
  });
  if (!res.ok) throw new Error(`runQuery failed: ${res.status} ${await res.text()}`);
  const arr = await res.json();
  return arr.filter((e) => e.document).map((e) => ({ id: e.document.name.split('/').pop(), data: decodeDoc(e.document) }));
}

export async function sendDailyDebtDigest(env, accessToken) {
  // Query all open debts (status == 'open')
  const debts = await runQuery(env, accessToken, {
    from: [{ collectionId: 'debts' }],
    where: { fieldFilter: { field: { fieldPath: 'status' }, op: 'EQUAL', value: { stringValue: 'open' } } },
  });
  if (debts.length === 0) return { sent: 0 };

  // Group by collector
  const byCollector = new Map();
  for (const d of debts) {
    const cur = byCollector.get(d.data.collectorId) || { name: d.data.collectorName || 'Collector', total: 0, count: 0 };
    cur.total += Number(d.data.forgivenAmount || 0);
    cur.count += 1;
    byCollector.set(d.data.collectorId, cur);
  }
  const summary = [...byCollector.entries()].map(([_, v]) => `${v.name}: ${v.count} item(s), ETB ${v.total.toFixed(0)}`).join('; ');
  const title = 'Debt reminder';
  const body = `Reminder: ${summary}`;

  // Fan out to admins + viewers via notifications collection (push handled by existing flow)
  const roles = ['admin', 'viewer'];
  let sent = 0;
  for (const role of roles) {
    const users = await runQuery(env, accessToken, {
      from: [{ collectionId: 'users' }],
      where: { fieldFilter: { field: { fieldPath: 'role' }, op: 'EQUAL', value: { stringValue: role } } },
    });
    for (const u of users) {
      const notifUrl = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/notifications`;
      const nowMs = Date.now();
      const fields = {
        targetUserId: { stringValue: u.id },
        title: { stringValue: title },
        body: { stringValue: body },
        type: { stringValue: 'debtRecorded' },
        isRead: { booleanValue: false },
        createdAt: { integerValue: String(nowMs) },
        senderName: { stringValue: 'System' },
        senderId: { stringValue: 'system-debt-cron' },
      };
      const r = await fetch(notifUrl, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields }),
      });
      if (r.ok) sent += 1;
    }
  }
  return { sent, summary };
}

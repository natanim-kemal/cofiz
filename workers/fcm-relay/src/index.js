// Cofiz FCM relay - deploy to Cloudflare Workers.
// Receives {targetUserId, title, body, type} from the app, looks up the
// target user's fcmToken in Firestore via REST, and sends the push through
// FCM HTTP v1 - all authenticated with a Firebase service account passed
// as environment variables.


const FIREBASE_SCOPE = "https://www.googleapis.com/auth/cloud-platform";
const FIRESTORE_HOST = "firestore.googleapis.com";
const FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects";

const b64url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

const pemToPkcs8 = (pem) => {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "\n")
    .replace(/[^\nA-Za-z0-9+/=]/g, "");
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
};

async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({
    iss: env.FIREBASE_CLIENT_EMAIL,
    scope: FIREBASE_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(env.FIREBASE_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status}`);
  const json = await res.json();
  return json.access_token;
}

async function getFcmToken(env, accessToken, uid) {
  const url = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${uid}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`user lookup failed: ${res.status}`);
  const doc = await res.json();
  const token = doc.fields?.fcmToken?.stringValue;
  return token || null;
}

async function sendPush(env, accessToken, fcmToken, payload) {
  const message = {    message: {
      token: fcmToken,
      notification: { title: payload.title, body: payload.body },
      data: {
        type: payload.type || "info",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "cofiz_main_channel",
          priority: "high",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    },
  };
  const res = await fetch(
    `${FCM_ENDPOINT}/${env.FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    },
  );
  if (!res.ok) {
    const errBody = await res.text();
    console.error(`FCM send failed: ${res.status} ${errBody}`);
    // Stale token cleanup
    if (errBody.includes("registration-token-not-registered") ||
        errBody.includes("invalid-registration-token") ||
        errBody.includes("unregistered")) {
      await fetch(
        `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${payload.targetUserId}?updateMask.fieldPaths=fcmToken`,
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ fields: {} }),
        },
      );
    }
  }
  return res.ok;
}

// ---- Cron helpers (exported for tests) ----

export function parseTimeToMinutes(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  if (Number.isNaN(h) || Number.isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

export function isInWindow(baseTimeStr, nowMinutes) {
  const baseMin = parseTimeToMinutes(baseTimeStr);
  if (baseMin === null) return false;
  // Cron runs every 30 min; allow exact match at +0/+30/+60
  const offsets = [0, 30, 60];
  return offsets.some((o) => nowMinutes === baseMin + o);
}

export function getAddisNow(date = new Date()) {
  // Converts any instant to Addis wall-time Date (Africa/Addis_Ababa = UTC+3, no DST)
  // by extracting locale string then re-parsing as local.
  return new Date(date.toLocaleString('en-US', { timeZone: 'Africa/Addis_Ababa' }));
}

export function formatAddisDate(addisNow) {
  const y = addisNow.getFullYear();
  const m = String(addisNow.getMonth() + 1).padStart(2, '0');
  const d = String(addisNow.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function getAddisDayBoundsMs(addisNow) {
  const y = addisNow.getFullYear();
  const m = addisNow.getMonth();
  const d = addisNow.getDate();
  // Date.UTC gives UTC midnight of Addis calendar date; subtract 3h to get true UTC instant of Addis midnight
  const startMs = Date.UTC(y, m, d) - 3 * 3600 * 1000;
  const endMs = startMs + 24 * 3600 * 1000;
  return { startMs, endMs };
}

// ---- Firestore REST helpers for cron ----

function decodeField(v) {
  if (v == null) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('booleanValue' in v) return v.booleanValue === true || v.booleanValue === 'true';
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) {
    const out = {};
    for (const [k, val] of Object.entries(v.mapValue.fields || {})) out[k] = decodeField(val);
    return out;
  }
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeField);
  return null;
}

function decodeDoc(doc) {
  if (!doc || !doc.fields) return null;
  const out = {};
  for (const [k, v] of Object.entries(doc.fields)) out[k] = decodeField(v);
  return out;
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

async function getDoc(env, accessToken, path) {
  const url = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`getDoc ${path} failed: ${res.status}`);
  const doc = await res.json();
  return decodeDoc(doc);
}

async function setDoc(env, accessToken, path, data) {
  const url = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`;
  const fields = encodeFields(data);
  // PATCH with updateMask for each field (merge)
  const mask = Object.keys(data).map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  const patchUrl = mask ? `${url}?${mask}` : url;
  const res = await fetch(patchUrl, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) throw new Error(`setDoc ${path} failed: ${res.status} ${await res.text()}`);
  return res.json();
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
  // Each entry is {document?: {...}, readTime?}
  return arr.filter((e) => e.document).map((e) => ({ id: e.document.name.split('/').pop(), data: decodeDoc(e.document), raw: e.document }));
}

async function getUsersByRole(env, accessToken, role) {
  const q = {
    from: [{ collectionId: 'users' }],
    where: { fieldFilter: { field: { fieldPath: 'role' }, op: 'EQUAL', value: { stringValue: role } } },
  };
  const docs = await runQuery(env, accessToken, q);
  return docs.map((d) => d.id);
}

async function hasTransactionToday(env, accessToken, addisNow) {
  const { startMs, endMs } = getAddisDayBoundsMs(addisNow);
  const q = {
    from: [{ collectionId: 'transactions' }],
    where: {
      compositeFilter: {
        op: 'AND',
        filters: [
          { fieldFilter: { field: { fieldPath: 'createdAt' }, op: 'GREATER_THAN_OR_EQUAL', value: { integerValue: String(startMs) } } },
          { fieldFilter: { field: { fieldPath: 'createdAt' }, op: 'LESS_THAN', value: { integerValue: String(endMs) } } },
        ],
      },
    },
    limit: 1,
  };
  const docs = await runQuery(env, accessToken, q);
  return docs.length > 0;
}

async function createNotificationDoc(env, accessToken, targetUserId, title, body, type, senderId = 'system-cron') {
  const url = `https://${FIRESTORE_HOST}/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/notifications`;
  const nowMs = Date.now();
  const fields = encodeFields({
    targetUserId,
    title,
    body,
    type,
    isRead: false,
    createdAt: nowMs,
    senderId,
    senderRole: 'system',
  });
  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) console.error(`createNotificationDoc failed: ${res.status} ${await res.text()}`);
  return res.ok;
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return Response.json({ error: "POST only" }, { status: 405 });
    }
    // Shared-secret gate so only the app can hit the relay.
    if (request.headers.get("X-Relay-Secret") !== env.RELAY_SECRET) {
      return Response.json({ error: "unauthorized" }, { status: 401 });
    }

    let payload;
    try {
      payload = await request.json();
    } catch (_) {
      return Response.json({ error: "invalid json" }, { status: 400 });
    }
    const { targetUserId, title, body } = payload;
    if (!targetUserId || !title) {
      return Response.json({ error: "targetUserId and title required" }, { status: 400 });
    }

    try {
      const accessToken = await getAccessToken(env);
      const fcmToken = await getFcmToken(env, accessToken, targetUserId);
      if (!fcmToken) {
        return Response.json({ sent: false, reason: "no fcm token" });
      }
      const ok = await sendPush(env, accessToken, fcmToken, {
        title,
        body: body ?? "",
        type: payload.type,
      });
      return Response.json({ sent: ok }, { status: ok ? 200 : 502 });
    } catch (e) {
      return Response.json({ error: e.message }, { status: 500 });
    }
  },

  async scheduled(event, env, ctx) {
    // Cron every 30 min — nightly admin nudge + viewer weekly check-in (Africa/Addis_Ababa)
    try {
      const accessToken = await getAccessToken(env);
      const cfg = (await getDoc(env, accessToken, 'settings/app')) || {};
      const addisNow = getAddisNow(new Date(event?.scheduledTime ? new Date(event.scheduledTime) : Date.now()));
      const nowMin = addisNow.getHours() * 60 + addisNow.getMinutes();
      const todayStr = formatAddisDate(addisNow);

      // Nightly admin nudge: base +0/+30/+60
      if (cfg.reminderEnabled !== false && cfg.adminReminderTime) {
        const baseStr = String(cfg.adminReminderTime);
        if (isInWindow(baseStr, nowMin)) {
          if (cfg.lastReminderDate !== todayStr) {
            const hasTx = await hasTransactionToday(env, accessToken, addisNow);
            if (!hasTx) {
              const admins = await getUsersByRole(env, accessToken, 'admin');
              for (const uid of admins) {
                const tok = await getFcmToken(env, accessToken, uid);
                if (tok) {
                  await sendPush(env, accessToken, tok, {
                    title: 'Reminder: no record today',
                    body: "No transaction recorded today — add today's purchases/distributions",
                    type: 'nightlyNoRecordReminder',
                    targetUserId: uid,
                  });
                }
                await createNotificationDoc(
                  env,
                  accessToken,
                  uid,
                  'Reminder: no record today',
                  "No transaction recorded today — add today's purchases/distributions",
                  'nightlyNoRecordReminder',
                );
              }
              await setDoc(env, accessToken, 'settings/app', { lastReminderDate: todayStr });
              console.log(`[cron] nightly nudge sent for ${todayStr} to ${admins.length} admins`);
            } else {
              console.log(`[cron] nightly nudge skipped — has transaction on ${todayStr}`);
            }
          } else {
            console.log(`[cron] nightly nudge deduped for ${todayStr}`);
          }
        }
      }

      // Viewer weekly check-in: Monday 09:00 Addis
      if (cfg.viewerCheckInEnabled === true && addisNow.getDay() === 1 && nowMin === 9 * 60) {
        if (cfg.lastViewerCheckInDate !== todayStr) {
          const viewers = await getUsersByRole(env, accessToken, 'viewer');
          for (const uid of viewers) {
            const tok = await getFcmToken(env, accessToken, uid);
            if (tok) {
              await sendPush(env, accessToken, tok, {
                title: 'Weekly check-in',
                body: "Check in: see this week's business",
                type: 'viewerWeeklyCheckIn',
                targetUserId: uid,
              });
            }
            await createNotificationDoc(
              env,
              accessToken,
              uid,
              'Weekly check-in',
              "Check in: see this week's business",
              'viewerWeeklyCheckIn',
            );
          }
          await setDoc(env, accessToken, 'settings/app', { lastViewerCheckInDate: todayStr });
          console.log(`[cron] viewer weekly check-in sent for ${todayStr} to ${viewers.length} viewers`);
        } else {
          console.log(`[cron] viewer check-in deduped for ${todayStr}`);
        }
      }
    } catch (e) {
      console.error(`[cron] scheduled failed: ${e.message}`, e);
    }
  },
};

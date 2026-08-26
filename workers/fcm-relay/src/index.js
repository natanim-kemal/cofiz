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
};

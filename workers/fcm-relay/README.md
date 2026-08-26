# Cofiz FCM Relay (Cloudflare Worker)

Free push relay for Cofiz - no Google billing required. The app POSTs
notification payloads here; the worker reads the target user's `fcmToken`
from Firestore and sends the push via FCM HTTP v1.

## One-time setup

### 1. Firebase service account key

Firebase Console -> Project Settings -> Service Accounts ->
**Generate new private key**. Save the JSON; you need
`project_id`, `client_email`, `private_key`.

> Keep this file private. It grants server-level access to the project.

### 2. Deploy the worker

```bash
cd workers/fcm-relay
npm i -g wrangler   # once
wrangler login      # opens browser, no card needed

wrangler secret put FIREBASE_PROJECT_ID     # paste project_id
wrangler secret put FIREBASE_CLIENT_EMAIL   # paste client_email
wrangler secret put FIREBASE_PRIVATE_KEY    # paste private_key (with \n escapes)
wrangler secret put RELAY_SECRET            # any long random string

wrangler deploy
```

Note the printed URL, e.g. `https://cofiz-fcm-relay.<your-subdomain>.workers.dev`.

### 3. App config

Put the URL + the same RELAY_SECRET into
`app/lib/core/config/relay_config.dart` (`relayUrl`, `relaySecret`).
The sync executor posts every synced distribution/purchase there.

## Verify it works

```bash
curl -X POST https://cofiz-fcm-relay.<sub>.workers.dev/ \
  -H "Content-Type: application/json" \
  -H "X-Relay-Secret: <RELAY_SECRET>" \
  -d '{"targetUserId":"<some-uid-with-token>","title":"Test","body":"Hello"}'
```

Expect `{"sent":true}` and a push on the device.

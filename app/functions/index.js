
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const crypto = require("crypto");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Triggered when a new notification is created in the 'notifications' collection.
 * Sends a push notification to the target user if they have an FCM token.
 */
exports.sendPushNotification = functions.firestore
    .document("notifications/{notificationId}")
    .onCreate(async (snap, context) => {
        const notification = snap.data();
        const notificationId = context.params.notificationId;

        console.log(`New notification created: ${notificationId}`);
        console.log(`Target user: ${notification.targetUserId}`);

        // Get the target user's FCM token
        const targetUserId = notification.targetUserId;
        if (!targetUserId) {
            console.log("No target user ID, skipping push notification");
            return null;
        }

        try {
            const userDoc = await db.collection("users").doc(targetUserId).get();

            if (!userDoc.exists) {
                console.log(`User ${targetUserId} not found`);
                return null;
            }

            const userData = userDoc.data();
            const fcmToken = userData.fcmToken;

            if (!fcmToken) {
                console.log(`User ${targetUserId} has no FCM token`);
                return null;
            }

            // Build the FCM message
            const message = {
                token: fcmToken,
                notification: {
                    title: notification.title || "New Notification",
                    body: notification.body || "",
                },
                data: {
                    notificationId: notificationId,
                    type: notification.type || "info",
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
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                        },
                    },
                },
            };

            // Send the push notification
            const response = await messaging.send(message);
            console.log(`Push notification sent successfully: ${response}`);

            // Update the notification document to mark push as sent
            await snap.ref.update({
                pushSent: true,
                pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return response;
        } catch (error) {
            console.error("Error sending push notification:", error);

            // If the token is invalid, remove it from the user
            if (error.code === "messaging/invalid-registration-token" ||
                error.code === "messaging/registration-token-not-registered") {
                console.log(`Removing invalid FCM token for user ${targetUserId}`);
                await db.collection("users").doc(targetUserId).update({
                    fcmToken: admin.firestore.FieldValue.delete(),
                });
            }

            return null;
        }
    });

/**
 * Optional: Clean up old notifications (older than 30 days)
 * Run daily via Cloud Scheduler
 */
exports.cleanupOldNotifications = functions.pubsub
    .schedule("every 24 hours")
    .onRun(async (context) => {
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - 30);

        const oldNotifications = await db
            .collection("notifications")
            .where("createdAt", "<", cutoffDate.getTime())
            .get();

        const batch = db.batch();
        oldNotifications.docs.forEach((doc) => {
            batch.delete(doc.ref);
        });

        await batch.commit();
        console.log(`Deleted ${oldNotifications.size} old notifications`);

        return null;
    });

/*
 * Firestore security rules to configure in the Firebase console (project `cofiz-9dd0b`):
 *
 *   match /emailVerifications/{uid} {
 *     allow read, write: if request.auth != null && request.auth.uid == uid;
 *   }
 *   match /mail/{document=**} {
 *     allow create: if request.auth != null;
 *     allow read, update, delete: if false;
 *   }
 *   match /users/{uid} {
 *     // existing rules stay; emailVerified is only written by the verifyEmailCode function
 *     // (Admin SDK bypasses rules), so no client-side rule is needed for that field.
 *   }
 */
/*
 * Trigger Email extension (`firebase-extensions/firestore-send-email`):
 * - Install in the Firebase console on project `cofiz-9dd0b`.
 * - Template named `verification`:
 *     subject: "Your Cofiz verification code"
 *     body: "Your verification code is {{code}}. It expires in {{expiresMinutes}} minutes."
 *   (The extension reads `{to, template:{name, data}}` from the `mail` collection.)
 */

/**
 * On-demand email verification: generates a 6-digit code, stores a salted
 * SHA-256 hash in emailVerifications/{uid}, and queues a mail/{autoId} doc
 * for the Trigger Email extension to send.
 *
 * Expected payload: { email: string } (the address to verify)
 * Requires authentication; the uid comes from the caller's auth context.
 */
exports.requestEmailVerification = onCall(async (request) => {
  const uid = request.auth ? request.auth.uid : null;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const email = request.data && request.data.email;
  if (typeof email !== "string" || email.length === 0) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }

  const code = String(100000 + Math.floor(Math.random() * 900000)); // 100000-999999
  const salt = crypto.randomBytes(16).toString("hex");
  const codeHash = crypto.createHash("sha256").update(salt + code).digest("hex");

  await db.collection("emailVerifications").doc(uid).set({
    email,
    codeHash,
    salt,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
    attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection("mail").add({
    to: email,
    template: { name: "verification", data: { code, expiresMinutes: 10 } },
  });

  return { ok: true };
});

/**
 * Verifies a submitted 6-digit code against emailVerifications/{uid}.
 * Enforces 10-minute expiry and a 5-attempt limit atomically (transaction).
 * On success sets users/{uid}.emailVerified = true and deletes the code doc.
 *
 * Expected payload: { code: string }
 */
exports.verifyEmailCode = onCall(async (request) => {
  const uid = request.auth ? request.auth.uid : null;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const input = request.data && request.data.code;
  if (typeof input !== "string") {
    throw new HttpsError("invalid-argument", "A code is required.");
  }

  const ref = db.collection("emailVerifications").doc(uid);

  const result = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "No verification request found. Please resend the code.");
    }
    const doc = snap.data();
    const expiresAt = doc.expiresAt.toMillis ? doc.expiresAt.toMillis() : Date.parse(doc.expiresAt);
    if (expiresAt < Date.now()) {
      throw new HttpsError("deadline-exceeded", "Code expired. Please resend a new code.");
    }
    if (doc.attempts >= 5) {
      throw new HttpsError("resource-exhausted", "Too many attempts. Please resend the code.");
    }
    const hash = crypto.createHash("sha256").update(doc.salt + input).digest("hex");
    if (hash !== doc.codeHash) {
      t.update(ref, { attempts: doc.attempts + 1 });
      throw new HttpsError("invalid-argument", "Invalid code. Try again.");
    }
    t.update(db.collection("users").doc(uid), { emailVerified: true });
    t.delete(ref);
    return { verified: true };
  });

  return result;
});

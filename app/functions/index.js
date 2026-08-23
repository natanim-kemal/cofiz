
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
 *     // DENY all client access: both callables below use the Admin SDK,
 *     // which bypasses rules. Client read/write would let a user overwrite
 *     // their own codeHash and "verify" without receiving any email.
 *     allow read, write: if false;
 *   }
 *   match /mail/{document=**} {
 *     // DENY all client access: mail docs are enqueued only by the
 *     // requestEmailVerification callable (Admin SDK). Client writes would
 *     // let any authenticated user send arbitrary emails (spam/cost).
 *     allow read, write: if false;
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
 * The target address is ALWAYS derived from the caller's verified Firebase
 * auth identity - client-supplied emails are ignored, so a user can only
 * ever verify their own account's address.
 *
 * Requires authentication; the uid comes from the caller's auth context.
 */
const RESEND_COOLDOWN_MS = 60 * 1000; // 1 minute between code requests

exports.requestEmailVerification = onCall(async (request) => {
  const uid = request.auth ? request.auth.uid : null;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const tokenEmail = request.auth.token.email;
  if (typeof tokenEmail !== "string" || tokenEmail.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "Your account has no email address to verify.",
    );
  }
  const email = tokenEmail.toLowerCase();

  const ref = db.collection("emailVerifications").doc(uid);

  // Per-UID resend cooldown so the callable cannot be spammed.
  await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const doc = snap.exists ? snap.data() : null;
    if (doc && doc.createdAt) {
      const created = doc.createdAt.toMillis ? doc.createdAt.toMillis() : Date.parse(doc.createdAt);
      if (Date.now() - created < RESEND_COOLDOWN_MS) {
        throw new HttpsError(
          "resource-exhausted",
          "Please wait a minute before requesting a new code.",
        );
      }
    }
    // Generate inside the transaction with a crypto-secure source.
    const code = String(crypto.randomInt(100000, 1000000)); // 100000-999999
    const salt = crypto.randomBytes(16).toString("hex");
    const codeHash = crypto.createHash("sha256").update(salt + code).digest("hex");
    t.set(ref, {
      email,
      codeHash,
      salt,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Mail enqueue must happen after the transaction commits (no side
    // effects inside transactions); staged below via returned values.
    return { code };
  }).then(async (staged) => {
    await db.collection("mail").add({
      to: email,
      template: { name: "verification", data: { code: staged.code, expiresMinutes: 10 } },
    });
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
      // Commit the attempt increment; the caller-visible error is thrown
      // AFTER the transaction resolves (throwing inside would roll the
      // increment back and give unlimited guesses).
      t.update(ref, { attempts: doc.attempts + 1 });
      return { verified: false };
    }
    t.update(db.collection("users").doc(uid), { emailVerified: true });
    t.delete(ref);
    return { verified: true };
  });

  if (!result.verified) {
    throw new HttpsError("invalid-argument", "Invalid code. Try again.");
  }
  return result;
});

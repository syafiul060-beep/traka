const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Initialize Firebase Admin SDK
admin.initializeApp();

// Konfigurasi SMTP untuk Gmail
// Gunakan GMAIL_EMAIL dan GMAIL_APP_PASSWORD di Firebase Console > Functions > Environment variables
// Atau di .env saat development. Fallback untuk migrasi (jangan commit ke Git di production).
const gmailEmail = process.env.GMAIL_EMAIL || "syafiul060@gmail.com";
const gmailAppPassword = process.env.GMAIL_APP_PASSWORD || "omtlbwhkusqpjlet";

// Buat transporter untuk Nodemailer
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: gmailEmail,
    pass: gmailAppPassword,
  },
});

// Callable: app memanggil ini untuk minta kode verifikasi (bypass Firestore rules)
// Admin SDK menulis ke Firestore, lalu trigger sendVerificationCode kirim email
exports.requestVerificationCode = functions.https.onCall(async (data, context) => {
  const email = data?.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmedEmail)) {
    throw new functions.https.HttpsError("invalid-argument", "Format email tidak valid.");
  }

  // Cek apakah email sudah terdaftar
  const usersSnap = await admin.firestore()
      .collection("users")
      .where("email", "==", trimmedEmail)
      .limit(1)
      .get();
  if (!usersSnap.empty) {
    throw new functions.https.HttpsError(
        "already-exists",
        "Email sudah terdaftar. Gunakan email lainnya yang aktif.",
    );
  }

  // Generate kode 6 digit
  const code = String(100000 + Math.floor(Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 menit

  const ref = admin.firestore().collection("verification_codes").doc(trimmedEmail);

  // Hapus dulu agar onCreate trigger jalan saat set (untuk kirim ulang kode)
  await ref.delete();

  // Tulis ke Firestore pakai Admin SDK (onCreate akan fire → kirim email)
  await ref.set({
    code,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// --- Lupa kata sandi: kirim kode OTP ke email (hanya untuk email yang sudah terdaftar) ---
exports.requestForgotPasswordCode = functions.https.onCall(async (data, context) => {
  const email = data?.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmedEmail)) {
    throw new functions.https.HttpsError("invalid-argument", "Format email tidak valid.");
  }

  const usersSnap = await admin.firestore()
      .collection("users")
      .where("email", "==", trimmedEmail)
      .limit(1)
      .get();
  if (usersSnap.empty) {
    throw new functions.https.HttpsError(
        "not-found",
        "Email tidak terdaftar.",
    );
  }
  const uid = usersSnap.docs[0].id;

  const code = String(100000 + Math.floor(Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 menit

  const ref = admin.firestore().collection("forgot_password_codes").doc(trimmedEmail);
  await ref.delete();
  await ref.set({
    code,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const textTemplate = `
Halo,

Anda meminta kode verifikasi untuk atur ulang kata sandi Traka.

Kode verifikasi Anda: ${code}

Kode ini berlaku 10 menit. Masukkan di aplikasi, lalu verifikasi wajah dan buat kata sandi baru.

Jika Anda tidak meminta ini, abaikan email ini.

Salam,
Tim Traka
  `.trim();

  const htmlTemplate = `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial;line-height:1.6;color:#333;max-width:600px;margin:0 auto;padding:20px;">
  <div style="background:#f9f9f9;padding:30px;border-radius:8px;">
    <h2>Lupa kata sandi</h2>
    <p>Kode verifikasi Anda:</p>
    <div style="background:#2563EB;color:white;font-size:32px;font-weight:bold;text-align:center;padding:20px;border-radius:8px;letter-spacing:5px;">${code}</div>
    <p>Berlaku 10 menit. Masukkan di aplikasi, lalu verifikasi wajah dan buat kata sandi baru.</p>
    <p style="color:#999;font-size:12px;">Jika Anda tidak meminta ini, abaikan email ini.</p>
    <p>Salam,<br>Tim Traka</p>
  </div>
</body>
</html>
  `.trim();

  try {
    await transporter.sendMail({
      from: `"Traka" <${gmailEmail}>`,
      to: trimmedEmail,
      subject: "Kode verifikasi lupa kata sandi - Traka",
      text: textTemplate,
      html: htmlTemplate,
    });
  } catch (err) {
    console.error("requestForgotPasswordCode sendMail error:", err);
    throw new functions.https.HttpsError("internal", "Gagal mengirim email. Coba lagi.");
  }

  return { success: true };
});

// --- Login pertama (no phone): kirim OTP ke email untuk verifikasi device ---
exports.requestLoginVerificationCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const email = data?.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmedEmail)) {
    throw new functions.https.HttpsError("invalid-argument", "Format email tidak valid.");
  }

  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }
  const userEmail = (userSnap.data()?.email || "").trim().toLowerCase();
  if (userEmail !== trimmedEmail) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Email tidak sesuai dengan akun Anda.",
    );
  }

  const code = String(100000 + Math.floor(Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 menit

  const ref = admin.firestore().collection("login_verification_codes").doc(uid);
  await ref.delete();
  await ref.set({
    code,
    email: trimmedEmail,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const textTemplate = `
Halo,

Anda meminta kode verifikasi untuk login pertama di perangkat baru Traka.

Kode verifikasi Anda: ${code}

Kode ini berlaku 10 menit.

Jika Anda tidak meminta ini, abaikan email ini.

Salam,
Tim Traka
  `.trim();

  const htmlTemplate = `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial;line-height:1.6;color:#333;max-width:600px;margin:0 auto;padding:20px;">
  <div style="background:#f9f9f9;padding:30px;border-radius:8px;">
    <h2>Verifikasi login</h2>
    <p>Kode verifikasi Anda:</p>
    <div style="background:#2563EB;color:white;font-size:32px;font-weight:bold;text-align:center;padding:20px;border-radius:8px;letter-spacing:5px;">${code}</div>
    <p>Berlaku 10 menit.</p>
    <p style="color:#999;font-size:12px;">Jika Anda tidak meminta ini, abaikan email ini.</p>
    <p>Salam,<br>Tim Traka</p>
  </div>
</body>
</html>
  `.trim();

  try {
    await transporter.sendMail({
      from: `"Traka" <${gmailEmail}>`,
      to: trimmedEmail,
      subject: "Kode verifikasi login - Traka",
      text: textTemplate,
      html: htmlTemplate,
    });
  } catch (err) {
    console.error("requestLoginVerificationCode sendMail error:", err);
    throw new functions.https.HttpsError("internal", "Gagal mengirim email. Coba lagi.");
  }

  return { success: true };
});

// --- Login pertama: verifikasi OTP email ---
exports.verifyLoginVerificationCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const code = data?.code;
  if (!code || typeof code !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Kode wajib diisi.");
  }
  const trimmedCode = code.trim();

  const ref = admin.firestore().collection("login_verification_codes").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Kode tidak ditemukan atau sudah dipakai. Kirim ulang kode.");
  }
  const d = snap.data();
  const savedCode = d.code;
  const expiresAt = d.expiresAt?.toDate?.() || new Date(0);

  if (trimmedCode !== savedCode) {
    throw new functions.https.HttpsError("invalid-argument", "Kode verifikasi tidak sesuai.");
  }
  if (new Date() > expiresAt) {
    await ref.delete();
    throw new functions.https.HttpsError("failed-precondition", "Kode sudah kedaluwarsa. Kirim ulang kode.");
  }

  await ref.delete();
  return { success: true };
});

// --- Lupa kata sandi: verifikasi OTP email, kembalikan custom token untuk sign in ---
exports.verifyForgotPasswordOtpAndGetToken = functions.https.onCall(async (data, context) => {
  const email = data?.email;
  const code = data?.code;
  if (!email || typeof email !== "string" || !code || typeof code !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email dan kode wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  const trimmedCode = code.trim();

  const ref = admin.firestore().collection("forgot_password_codes").doc(trimmedEmail);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Kode tidak ditemukan atau sudah dipakai. Kirim ulang kode.");
  }
  const d = snap.data();
  const savedCode = d.code;
  const expiresAt = d.expiresAt?.toDate?.() || new Date(0);
  const uid = d.uid;

  if (trimmedCode !== savedCode) {
    throw new functions.https.HttpsError("invalid-argument", "Kode verifikasi tidak sesuai.");
  }
  if (new Date() > expiresAt) {
    await ref.delete();
    throw new functions.https.HttpsError("failed-precondition", "Kode sudah kedaluwarsa. Kirim ulang kode.");
  }

  const customToken = await admin.auth().createCustomToken(uid);
  await ref.delete();

  return { customToken };
});

// Cloud Function yang trigger saat ada document baru di verification_codes
exports.sendVerificationCode = functions.firestore
    .document("verification_codes/{email}")
    .onCreate(async (snap, context) => {
      // Ambil data dari document yang baru dibuat
      const data = snap.data();
      const email = context.params.email; // Email user (document ID)
      const code = data.code; // Kode verifikasi 6 digit

      // Validasi: pastikan field 'code' ada
      if (!code) {
        console.error("Field \"code\" tidak ditemukan di document");
        return null;
      }

      // Template email (Text)
      const textTemplate = `
Halo,

Terima kasih telah mendaftar di Traka.

Kode verifikasi Anda adalah: ${code}

Kode ini berlaku selama 10 menit.

Masukkan kode ini di aplikasi untuk menyelesaikan pendaftaran.

Jika Anda tidak meminta kode ini, abaikan email ini.

Salam,
Tim Traka
    `.trim();

      // Template email (HTML)
      const htmlTemplate = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body {
      font-family: Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
    }
    .container {
      background-color: #f9f9f9;
      padding: 30px;
      border-radius: 8px;
    }
    .code-box {
      background-color: #2563EB;
      color: white;
      font-size: 32px;
      font-weight: bold;
      text-align: center;
      padding: 20px;
      border-radius: 8px;
      margin: 20px 0;
      letter-spacing: 5px;
    }
    .footer {
      margin-top: 30px;
      font-size: 12px;
      color: #666;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>Halo,</h2>
    <p>Terima kasih telah mendaftar di <strong>Traka</strong>.</p>
    
    <p>Kode verifikasi Anda adalah:</p>
    <div class="code-box">${code}</div>
    
    <p>Kode ini berlaku selama <strong>10 menit</strong>.</p>
    <p>Masukkan kode ini di aplikasi untuk menyelesaikan pendaftaran.</p>
    
    <p style="color: #999; font-size: 12px;">
      Jika Anda tidak meminta kode ini, abaikan email ini.
    </p>
    
    <div class="footer">
      <p>Salam,<br>Tim Traka</p>
    </div>
  </div>
</body>
</html>
    `.trim();

      // Konfigurasi email
      const mailOptions = {
        from: `"Traka" <${gmailEmail}>`,
        to: email,
        subject: "Kode Verifikasi Traka",
        text: textTemplate,
        html: htmlTemplate,
      };

      try {
        // Kirim email
        const info = await transporter.sendMail(mailOptions);
        console.log("Email berhasil dikirim:", info.messageId);
        console.log("Email dikirim ke:", email);
        console.log("Kode verifikasi:", code);
        return null;
      } catch (error) {
        console.error("Error mengirim email:", error);
        // Jangan throw error agar document tetap tersimpan di Firestore
        // User bisa kirim ulang kode jika email gagal
        return null;
      }
    });

// --- Notifikasi: ketika order baru dibuat, driver dapat notifikasi ---
exports.onOrderCreated = functions.firestore
    .document("orders/{orderId}")
    .onCreate(async (snap, context) => {
      const orderId = context.params.orderId;
      const data = snap.data();
      const driverUid = data.driverUid || "";
      const passengerName = (data.passengerName || "Penumpang").trim();
      if (!driverUid) return null;

      const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
      if (!driverSnap.exists) return null;
      const fcmToken = driverSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: "Permintaan travel baru",
          body: `${passengerName} ingin pesan travel. Buka chat untuk kesepakatan harga.`,
        },
        data: {
          type: "order",
          orderId,
          passengerName,
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "traka_chat",
            priority: "high",
          },
        },
      };
      try {
        await admin.messaging().send(payload);
      } catch (e) {
        console.error("FCM onOrderCreated error:", e);
      }
      return null;
    });

// --- Notifikasi: ketika penumpang setuju kesepakatan, driver dapat notifikasi ---
exports.onPassengerAgreed = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const orderId = context.params.orderId;
      const before = change.before.data();
      const after = change.after.data();
      
      // Cek apakah passengerAgreed berubah dari false ke true dan status menjadi 'agreed'
      const beforePassengerAgreed = before.passengerAgreed || false;
      const afterPassengerAgreed = after.passengerAgreed || false;
      const afterStatus = after.status || "";
      const driverUid = after.driverUid || "";
      const passengerName = (after.passengerName || "Penumpang").trim();
      
      // Hanya kirim notifikasi jika:
      // 1. passengerAgreed berubah dari false ke true
      // 2. Status menjadi 'agreed' (keduanya sudah setuju)
      // 3. Driver UID valid
      if (!beforePassengerAgreed && afterPassengerAgreed && afterStatus === "agreed" && driverUid) {
        // Ambil FCM token driver
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        if (!driverSnap.exists) return null;
        const fcmToken = driverSnap.data()?.fcmToken;
        if (!fcmToken) return null;

        const payload = {
          notification: {
            title: "Kesepakatan telah terjadi",
            body: `${passengerName} telah menyetujui kesepakatan. Pesanan aktif.`,
          },
          data: {
            type: "order_agreed",
            orderId,
            passengerName,
          },
          token: fcmToken,
          android: {
            priority: "high",
            notification: {
              channelId: "traka_chat",
              priority: "high",
            },
          },
        };
        
        try {
          await admin.messaging().send(payload);
        } catch (e) {
          console.error("FCM onPassengerAgreed error:", e);
        }
      }
      return null;
    });

// --- Notifikasi chat: ketika penumpang kirim pesan, driver dapat notifikasi ---
// Trigger saat ada pesan baru di orders/{orderId}/messages
exports.onChatMessageCreated = functions.firestore
    .document("orders/{orderId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const orderId = context.params.orderId;
      const messageData = snap.data();
      const senderUid = messageData.senderUid || "";
      const messageType = messageData.type || "text";
      const text = (messageData.text || "").trim();
      
      // Tentukan teks notifikasi berdasarkan type pesan
      let notificationText = text;
      let lastMessageText = text;
      
      if (!text || messageType !== "text") {
        // Untuk pesan non-text, gunakan teks default
        if (messageType === "audio") {
          const duration = messageData.audioDuration || 0;
          const durationText = duration > 0 ? ` (${duration}s)` : "";
          notificationText = `🎤 Pesan suara${durationText}`;
          lastMessageText = `🎤 Pesan suara${durationText}`;
        } else if (messageType === "image") {
          notificationText = "📷 Foto";
          lastMessageText = "📷 Foto";
        } else if (messageType === "video") {
          notificationText = "🎥 Video";
          lastMessageText = "🎥 Video";
        } else if (messageType === "barcode_passenger" || messageType === "barcode_driver") {
          notificationText = "📷 Barcode";
          lastMessageText = "📷 Barcode";
        } else if (messageType === "text") {
          notificationText = text.slice(0, 150) || "Pesan baru";
          lastMessageText = text.slice(0, 100) || "Pesan baru";
        } else {
          notificationText = "Pesan baru";
          lastMessageText = "Pesan baru";
        }
      }

      const orderRef = admin.firestore().collection("orders").doc(orderId);
      const orderSnap = await orderRef.get();
      if (!orderSnap.exists) return null;
      const orderData = orderSnap.data();
      const driverUid = orderData.driverUid || "";
      const passengerUid = orderData.passengerUid || "";
      const passengerName = (orderData.passengerName || "Penumpang").trim();
      let driverName = (orderData.driverName || "").trim();
      if (!driverName && driverUid) {
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        driverName = (driverSnap.exists && driverSnap.data()?.displayName) ? driverSnap.data().displayName.trim() : "Driver";
      }
      if (!driverName) driverName = "Driver";

      // Tentukan siapa yang menerima notifikasi
      let recipientUid = "";
      let senderName = "";
      
      if (senderUid === passengerUid) {
        // Penumpang mengirim → kirim notifikasi ke driver
        recipientUid = driverUid;
        senderName = passengerName;
      } else if (senderUid === driverUid) {
        // Driver mengirim → kirim notifikasi ke penumpang
        recipientUid = passengerUid;
        senderName = driverName;
      } else {
        // Sender tidak dikenal, skip
        return null;
      }

      if (!recipientUid) return null;

      // Cooldown 60 detik: jangan kirim notifikasi chat jika baru saja kirim untuk order ini
      const CHAT_NOTIFICATION_COOLDOWN_MS = 60 * 1000;
      const lastChatNotif = orderData.lastChatNotificationAt;
      const nowMs = Date.now();
      const lastMs = lastChatNotif && typeof lastChatNotif.toMillis === "function"
        ? lastChatNotif.toMillis() : 0;
      const inCooldown = lastMs > 0 && (nowMs - lastMs) < CHAT_NOTIFICATION_COOLDOWN_MS;

      // Update order untuk badge unread (lastMessageAt, lastMessageSenderUid, lastMessageText)
      const now = admin.firestore.FieldValue.serverTimestamp();
      const updateData = {
        lastMessageAt: now,
        lastMessageSenderUid: senderUid,
        lastMessageText: lastMessageText.slice(0, 100),
      };
      if (!inCooldown) {
        updateData.lastChatNotificationAt = now;
      }
      await orderRef.update(updateData);

      // Skip FCM jika dalam cooldown (kurangi spam notifikasi saat chat aktif)
      if (inCooldown) return null;

      // Ambil FCM token penerima dari users/{recipientUid}
      const recipientSnap = await admin.firestore().collection("users").doc(recipientUid).get();
      if (!recipientSnap.exists) return null;
      const fcmToken = recipientSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: senderName,
          body: notificationText.slice(0, 150),
        },
        data: {
          type: "chat",
          orderId,
          messageType: messageType,
          senderName: senderName,
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "traka_chat",
            priority: "high",
          },
        },
      };

      try {
        await admin.messaging().send(payload);
      } catch (e) {
        console.error("FCM send error:", e);
      }
      return null;
    });

// --- Notifikasi: driver scan barcode penumpang → penumpang dapat notifikasi "Anda sudah dijemput" ---
// --- Notifikasi: penumpang scan barcode driver → driver dapat notifikasi "Penumpang sudah sampai" ---
exports.onOrderUpdatedScan = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const orderId = context.params.orderId;
      const before = change.before.data();
      const after = change.after.data();
      const orderRef = change.after.ref;

      // Driver baru saja scan barcode penumpang (driverScannedAt baru di-set)
      const driverScannedBefore = before.driverScannedAt != null;
      const driverScannedAfter = after.driverScannedAt != null;
      if (!driverScannedBefore && driverScannedAfter) {
        const passengerUid = after.passengerUid || "";
        if (!passengerUid) return null;
        const passengerSnap = await admin.firestore().collection("users").doc(passengerUid).get();
        if (!passengerSnap.exists) return null;
        const fcmToken = passengerSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Anda sudah dijemput",
            body: "Driver telah memindai barcode Anda. Anda tercatat naik. Saat sampai tujuan, scan barcode driver.",
          },
          data: { type: "order_picked_up", orderId },
          token: fcmToken,
          android: { priority: "high", notification: { channelId: "traka_chat", priority: "high" } },
        };
        try {
          await admin.messaging().send(payload);
        } catch (e) {
          console.error("FCM onOrderUpdatedScan (driverScanned) error:", e);
        }
      }

      // Penumpang baru saja scan barcode driver (passengerScannedAt baru di-set, status completed)
      const passengerScannedBefore = before.passengerScannedAt != null;
      const passengerScannedAfter = after.passengerScannedAt != null;
      if (!passengerScannedBefore && passengerScannedAfter) {
        const driverUid = after.driverUid || "";
        const passengerName = (after.passengerName || "Penumpang").trim();
        if (!driverUid) return null;
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        if (!driverSnap.exists) return null;
        const fcmToken = driverSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Penumpang sudah sampai",
            body: `${passengerName} telah memindai barcode. Perjalanan selesai.`,
          },
          data: { type: "order_completed", orderId },
          token: fcmToken,
          android: { priority: "high", notification: { channelId: "traka_chat", priority: "high" } },
        };
        try {
          await admin.messaging().send(payload);
        } catch (e) {
          console.error("FCM onOrderUpdatedScan (passengerScanned) error:", e);
        }

        // Kontribusi driver: tambah totalPenumpangServed untuk order travel (bukan kirim barang)
        const orderType = (after.orderType || "travel").toString();
        if (orderType === "travel") {
          const jumlahKerabat = typeof after.jumlahKerabat === "number" ? after.jumlahKerabat : 0;
          const totalPenumpang = 1 + jumlahKerabat;
          try {
            await admin.firestore().collection("users").doc(driverUid).update({
              totalPenumpangServed: admin.firestore.FieldValue.increment(totalPenumpang),
            });
          } catch (e) {
            console.error("Kontribusi: increment totalPenumpangServed error:", e);
          }
        }
      }
      return null;
    });

// --- Notifikasi pembatalan pesanan: ketika driver atau penumpang klik Batalkan/Konfirmasi,
//     pihak yang menerima konfirmasi dapat notifikasi ---
exports.onOrderCancellationUpdate = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const orderId = context.params.orderId;
      const before = change.before.data();
      const after = change.after.data();
      const driverUid = after.driverUid || "";
      const passengerUid = after.passengerUid || "";
      const passengerName = (after.passengerName || "Penumpang").trim();
      let driverName = (after.driverName || "").trim();
      if (!driverName && driverUid) {
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        driverName = (driverSnap.exists && driverSnap.data()?.displayName)
          ? driverSnap.data().displayName.trim() : "Driver";
      }
      if (!driverName) driverName = "Driver";

      // Driver baru saja membatalkan → kirim notifikasi ke penumpang
      const driverCancelledBefore = before.driverCancelled || false;
      const driverCancelledAfter = after.driverCancelled || false;
      if (!driverCancelledBefore && driverCancelledAfter && passengerUid) {
        const passengerSnap = await admin.firestore().collection("users").doc(passengerUid).get();
        if (!passengerSnap.exists) return null;
        const fcmToken = passengerSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Pembatalan pesanan",
            body: "Driver telah membatalkan pesanan. Buka Data Order untuk konfirmasi pembatalan.",
          },
          data: { type: "order_cancellation", orderId, initiator: "driver" },
          token: fcmToken,
          android: {
            priority: "high",
            notification: { channelId: "traka_chat", priority: "high" },
          },
        };
        try {
          await admin.messaging().send(payload);
        } catch (e) {
          console.error("FCM onOrderCancellationUpdate (driver->passenger):", e);
        }
      }

      // Penumpang baru saja membatalkan → kirim notifikasi ke driver
      const passengerCancelledBefore = before.passengerCancelled || false;
      const passengerCancelledAfter = after.passengerCancelled || false;
      if (!passengerCancelledBefore && passengerCancelledAfter && driverUid) {
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        if (!driverSnap.exists) return null;
        const fcmToken = driverSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Pembatalan pesanan",
            body: `${passengerName} telah membatalkan pesanan. Buka Data Order untuk konfirmasi pembatalan.`,
          },
          data: { type: "order_cancellation", orderId, initiator: "passenger" },
          token: fcmToken,
          android: {
            priority: "high",
            notification: { channelId: "traka_chat", priority: "high" },
          },
        };
        try {
          await admin.messaging().send(payload);
        } catch (e) {
          console.error("FCM onOrderCancellationUpdate (passenger->driver):", e);
        }
      }

      return null;
    });

// --- Kontribusi driver: verifikasi pembayaran Google Play lalu update contributionPaidUpToCount ---
exports.verifyContributionPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const driverUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const orderId = data?.orderId;
  const productId = (data?.productId || "traka_contribution_once").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken || !orderId) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken dan orderId wajib.");
  }

  const userRef = admin.firestore().collection("users").doc(driverUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }

  // TODO: Verifikasi purchaseToken dengan Google Play Developer API (androidpublisher.purchases.products.get).
  // Untuk production: gunakan service account yang punya akses Play Console, panggil API, baru update.
  // Untuk development: bisa percaya client dan update (hapus di production).
  const verified = true; // Ganti dengan hasil verifikasi API saat production.

  if (!verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const current = userSnap.data();
  const totalPenumpangServed = (current?.totalPenumpangServed ?? 0);
  await userRef.update({
    contributionPaidUpToCount: totalPenumpangServed,
    contributionLastPaidAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true, contributionPaidUpToCount: totalPenumpangServed };
});

// --- Kirim Barang: cek nomor HP mana yang terdaftar sebagai user Traka (untuk contact picker) ---
// Input: { phoneNumbers: string[] } max 50. Output: { registered: [{ phoneNumber, uid, displayName, photoUrl }] }
function normalizePhoneId(phone) {
  if (!phone || typeof phone !== "string") return null;
  let s = phone.replace(/\D/g, "");
  if (s.startsWith("62")) return "+" + s;
  if (s.startsWith("0")) return "+62" + s.substring(1);
  if (s.length >= 9) return "+62" + s;
  return null;
}

exports.checkRegisteredContacts = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const raw = data?.phoneNumbers;
  if (!Array.isArray(raw) || raw.length === 0) {
    return { registered: [] };
  }
  const normalized = [];
  const seen = new Set();
  for (let i = 0; i < Math.min(raw.length, 50); i++) {
    const n = normalizePhoneId(raw[i]);
    if (n && !seen.has(n)) {
      seen.add(n);
      normalized.push(n);
    }
  }
  if (normalized.length === 0) {
    return { registered: [] };
  }
  const db = admin.firestore();
  const registered = [];
  // Firestore 'in' supports max 30 values per query
  for (let i = 0; i < normalized.length; i += 30) {
    const batch = normalized.slice(i, i + 30);
    const snap = await db.collection("users")
        .where("phoneNumber", "in", batch)
        .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      const phone = d.phoneNumber || "";
      if (batch.includes(phone)) {
        registered.push({
          phoneNumber: phone,
          uid: doc.id,
          displayName: d.displayName || null,
          photoUrl: d.photoUrl || null,
        });
      }
    }
  }
  return { registered };
});

// --- Oper Driver: cek kontak yang terdaftar sebagai driver (role=driver) ---
exports.checkRegisteredDrivers = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const raw = data?.phoneNumbers;
  if (!Array.isArray(raw) || raw.length === 0) {
    return { registered: [] };
  }
  const normalized = [];
  const seen = new Set();
  for (let i = 0; i < Math.min(raw.length, 50); i++) {
    const n = normalizePhoneId(raw[i]);
    if (n && !seen.has(n)) {
      seen.add(n);
      normalized.push(n);
    }
  }
  if (normalized.length === 0) {
    return { registered: [] };
  }
  const db = admin.firestore();
  const registered = [];
  for (let i = 0; i < normalized.length; i += 30) {
    const batch = normalized.slice(i, i + 30);
    const snap = await db.collection("users")
        .where("phoneNumber", "in", batch)
        .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      if ((d.role || "") !== "driver") continue;
      const phone = d.phoneNumber || "";
      if (batch.includes(phone)) {
        registered.push({
          phoneNumber: phone,
          uid: doc.id,
          displayName: d.displayName || null,
          photoUrl: d.photoUrl || null,
          email: d.email || null,
          vehicleJumlahPenumpang: d.vehicleJumlahPenumpang ?? null,
        });
      }
    }
  }
  return { registered };
});

// --- Oper Driver: notifikasi ke driver kedua saat transfer dibuat ---
exports.onDriverTransferCreated = functions.firestore
    .document("driver_transfers/{transferId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const toDriverUid = data?.toDriverUid || "";
      const fromDriverUid = data?.fromDriverUid || "";
      if (!toDriverUid) return null;

      const fromDriverSnap = await admin.firestore()
          .collection("users").doc(fromDriverUid).get();
      const fromName = fromDriverSnap.exists
          ? (fromDriverSnap.data()?.displayName || "Driver").trim()
          : "Driver";

      const toDriverSnap = await admin.firestore()
          .collection("users").doc(toDriverUid).get();
      const fcmToken = toDriverSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: "Oper Driver",
          body: `${fromName} ingin mengoper penumpang ke Anda. Buka Data Order > Oper ke Saya.`,
        },
        data: {
          type: "driver_transfer",
          transferId: context.params.transferId,
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "traka_chat",
            priority: "high",
          },
        },
      };

      try {
        await admin.messaging().send(payload);
      } catch (e) {
        console.error("FCM onDriverTransferCreated error:", e);
      }
      return null;
    });

// --- Lacak Driver: penumpang bayar Rp 2000 via Google Play untuk fitur Lacak Driver per order ---
exports.verifyPassengerTrackPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const passengerUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const orderId = data?.orderId;
  const productId = (data?.productId || "traka_lacak_driver").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken || !orderId) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken dan orderId wajib.");
  }

  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }

  const orderData = orderSnap.data();
  const orderPassengerUid = orderData?.passengerUid || "";
  if (orderPassengerUid !== passengerUid) {
    throw new functions.https.HttpsError("permission-denied", "Anda bukan penumpang pesanan ini.");
  }

  // TODO: Verifikasi purchaseToken dengan Google Play Developer API.
  const verified = true;

  if (!verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  await orderRef.update({
    passengerTrackDriverPaidAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// --- Lacak Barang: pengirim atau penerima bayar via Google Play ---
exports.verifyLacakBarangPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const orderId = data?.orderId;
  const payerType = (data?.payerType || "").toString();
  const productId = (data?.productId || "traka_lacak_barang_7500").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken || !orderId) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken dan orderId wajib.");
  }
  if (payerType !== "passenger" && payerType !== "receiver") {
    throw new functions.https.HttpsError("invalid-argument", "payerType harus passenger atau receiver.");
  }

  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }

  const orderData = orderSnap.data();
  const orderType = (orderData?.orderType || "travel").toString();
  if (orderType !== "kirim_barang") {
    throw new functions.https.HttpsError("failed-precondition", "Bukan pesanan kirim barang.");
  }

  if (payerType === "passenger") {
    if (orderData?.passengerUid !== uid) {
      throw new functions.https.HttpsError("permission-denied", "Anda bukan pengirim pesanan ini.");
    }
  } else {
    if (orderData?.receiverUid !== uid) {
      throw new functions.https.HttpsError("permission-denied", "Anda bukan penerima pesanan ini.");
    }
  }

  // TODO: Verifikasi purchaseToken dengan Google Play Developer API.
  const verified = true;
  if (!verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const updateData = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (payerType === "passenger") {
    updateData.passengerLacakBarangPaidAt = admin.firestore.FieldValue.serverTimestamp();
  } else {
    updateData.receiverLacakBarangPaidAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await orderRef.update(updateData);
  return { success: true };
});

// --- Pelanggaran: penumpang bayar Rp 5000 per pelanggaran via Google Play ---
exports.verifyViolationPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const passengerUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const productId = (data?.productId || "traka_violation_fee_5000").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken wajib.");
  }

  const userRef = admin.firestore().collection("users").doc(passengerUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }

  const current = userSnap.data();
  const outstandingFee = (current?.outstandingViolationFee ?? 0);
  const outstandingCount = (current?.outstandingViolationCount ?? 0);
  if (outstandingFee <= 0) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Tidak ada pelanggaran yang perlu dibayar.",
    );
  }

  // TODO: Verifikasi purchaseToken dengan Google Play Developer API.
  const verified = true;

  if (!verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  // Ambil satu violation record penumpang yang belum dibayar (tertua)
  const violationSnap = await admin.firestore()
      .collection("violation_records")
      .where("userId", "==", passengerUid)
      .where("type", "==", "passenger")
      .where("paidAt", "==", null)
      .orderBy("createdAt")
      .limit(1)
      .get();

  if (violationSnap.empty) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Data pelanggaran tidak konsisten.",
    );
  }

  const firstViolation = violationSnap.docs[0];
  const violationAmount = (firstViolation.data()?.amount ?? 5000);
  const deductAmount = Math.min(violationAmount, outstandingFee);

  const batch = admin.firestore().batch();

  // Update user: kurangi outstanding
  batch.update(userRef, {
    outstandingViolationFee: Math.max(0, outstandingFee - deductAmount),
    outstandingViolationCount: Math.max(0, outstandingCount - 1),
  });

  // Tandai satu violation record sebagai paid
  batch.update(firstViolation.ref, {
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  return {
    success: true,
    deductedAmount: deductAmount,
    remainingOutstanding: Math.max(0, outstandingFee - deductAmount),
  };
});

// --- Pembebasan kontribusi driver penguji: set contributionPaidUpToCount = 999999 untuk driver di daftar ---
// Daftar UID di Firestore: app_config/contribution_exempt_drivers, field driverUids: ["uid1", "uid2", ...]
// Berjalan otomatis setiap hari jam 00:00 WIB.
exports.updateContributionExemptDrivers = functions.pubsub
    .schedule("0 0 * * *")
    .timeZone("Asia/Jakarta")
    .onRun(async () => {
      const db = admin.firestore();
      const exemptDoc = await db.collection("app_config")
          .doc("contribution_exempt_drivers")
          .get();

      if (!exemptDoc.exists) {
        console.log("contribution_exempt_drivers: doc tidak ada, skip.");
        return null;
      }

      const driverUids = exemptDoc.data()?.driverUids;
      if (!Array.isArray(driverUids) || driverUids.length === 0) {
        console.log("contribution_exempt_drivers: driverUids kosong, skip.");
        return null;
      }

      const EXEMPT_VALUE = 999999;
      let updated = 0;

      for (const uid of driverUids) {
        if (!uid || typeof uid !== "string") continue;
        try {
          await db.collection("users").doc(uid).update({
            contributionPaidUpToCount: EXEMPT_VALUE,
            contributionExemptUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          updated++;
        } catch (e) {
          console.error("updateContributionExemptDrivers: error for", uid, e);
        }
      }

      if (updated > 0) {
        console.log("updateContributionExemptDrivers: updated", updated, "drivers");
      }
      return null;
    });

// Callable: panggil manual untuk update pembebasan kontribusi (tanpa menunggu jadwal).
exports.runContributionExemptUpdate = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  // Opsional: cek apakah user adalah admin (bisa tambah validasi role)
  const db = admin.firestore();
  const exemptDoc = await db.collection("app_config")
      .doc("contribution_exempt_drivers")
      .get();

  if (!exemptDoc.exists) {
    return { success: false, message: "Dokumen contribution_exempt_drivers tidak ada." };
  }

  const driverUids = exemptDoc.data()?.driverUids;
  if (!Array.isArray(driverUids) || driverUids.length === 0) {
    return { success: false, message: "driverUids kosong." };
  }

  const EXEMPT_VALUE = 999999;
  let updated = 0;

  for (const uid of driverUids) {
    if (!uid || typeof uid !== "string") continue;
    try {
      await db.collection("users").doc(uid).update({
        contributionPaidUpToCount: EXEMPT_VALUE,
        contributionExemptUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updated++;
    } catch (e) {
      console.error("runContributionExemptUpdate: error for", uid, e);
    }
  }

  return { success: true, updated };
});

// --- Voice call cleanup: hapus subcollection ice dan doc voice_calls saat panggilan selesai ---
exports.onVoiceCallEnded = functions.firestore
    .document("voice_calls/{orderId}")
    .onUpdate(async (change, context) => {
      const after = change.after.data();
      const status = after?.status || "";
      if (status !== "ended" && status !== "rejected") return null;

      const orderId = context.params.orderId;
      const db = admin.firestore();
      const iceRef = db.collection("voice_calls").doc(orderId).collection("ice");

      // Hapus semua ICE candidates (batch max 500)
      const BATCH_SIZE = 400;
      let snap = await iceRef.limit(BATCH_SIZE).get();
      while (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (snap.docs.length < BATCH_SIZE) break;
        snap = await iceRef.limit(BATCH_SIZE).get();
      }

      // Hapus doc voice_calls (panggilan sudah selesai, tidak perlu disimpan)
      await change.after.ref.delete();
      console.log("Voice call cleanup: deleted voice_calls/", orderId);
      return null;
    });

// --- Voice call cleanup: hapus voice_calls lama (ended/rejected > 24 jam) - backup jika onUpdate terlewat ---
exports.cleanupOldVoiceCalls = functions.pubsub
    .schedule("every 6 hours")
    .onRun(async () => {
      const db = admin.firestore();
      const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      // Query ended dan rejected terpisah (hindari composite index)
      const [endedSnap, rejectedSnap] = await Promise.all([
        db.collection("voice_calls").where("status", "==", "ended")
            .where("updatedAt", "<", cutoffTs).limit(50).get(),
        db.collection("voice_calls").where("status", "==", "rejected")
            .where("updatedAt", "<", cutoffTs).limit(50).get(),
      ]);
      const allDocs = [...endedSnap.docs, ...rejectedSnap.docs];

      for (const doc of allDocs) {
        try {
          const iceRef = doc.ref.collection("ice");
          let iceSnap = await iceRef.limit(400).get();
          while (!iceSnap.empty) {
            const batch = db.batch();
            iceSnap.docs.forEach((d) => batch.delete(d.ref));
            await batch.commit();
            if (iceSnap.docs.length < 400) break;
            iceSnap = await iceRef.limit(400).get();
          }
          await doc.ref.delete();
        } catch (e) {
          console.error("cleanupOldVoiceCalls error for", doc.id, e);
        }
      }
      if (allDocs.length > 0) {
        console.log("cleanupOldVoiceCalls: deleted", allDocs.length, "old voice_calls");
      }
      return null;
    });

// --- Hapus akun permanen: user dengan scheduledDeletionAt sudah lewat (grace period 30 hari) ---
exports.deleteScheduledAccounts = functions.pubsub
    .schedule("0 2 * * *")
    .timeZone("Asia/Jakarta")
    .onRun(async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      const usersSnap = await db.collection("users")
          .where("scheduledDeletionAt", "<=", now)
          .limit(20)
          .get();

      for (const doc of usersSnap.docs) {
        const uid = doc.id;
        const data = doc.data();
        if (!data.deletedAt || !data.scheduledDeletionAt) continue;
        try {
          await admin.auth().deleteUser(uid);
          await doc.ref.delete();
          console.log("deleteScheduledAccounts: deleted user", uid);
        } catch (e) {
          console.error("deleteScheduledAccounts: error for", uid, e);
        }
      }
      if (usersSnap.size > 0) {
        console.log("deleteScheduledAccounts: processed", usersSnap.size, "accounts");
      }
      return null;
    });

// --- Hapus chat (messages) 24 jam setelah pesanan selesai. Order doc TIDAK dihapus (riwayat driver/penumpang tetap). ---
const SCHEDULE_HOURS = 24;
const BATCH_SIZE = 400;

exports.deleteCompletedOrderChats = functions.pubsub
    .schedule("every 1 hours")
    .onRun(async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
      const cutoff = new Date(now.toMillis() - SCHEDULE_HOURS * 60 * 60 * 1000);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      const ordersSnap = await db.collection("orders")
          .where("status", "==", "completed")
          .where("completedAt", "<", cutoffTs)
          .limit(50)
          .get();

      // Hanya hapus messages (isi chat). Dokumen order TIDAK dihapus agar riwayat driver/penumpang tetap ada.
      for (const orderDoc of ordersSnap.docs) {
        const messagesRef = orderDoc.ref.collection("messages");
        let snap = await messagesRef.orderBy("createdAt").limit(BATCH_SIZE).get();
        while (!snap.empty) {
          const batch = db.batch();
          snap.docs.forEach((d) => batch.delete(d.ref));
          await batch.commit();
          if (snap.docs.length < BATCH_SIZE) break;
          const last = snap.docs[snap.docs.length - 1];
          snap = await messagesRef.orderBy("createdAt").startAfter(last).limit(BATCH_SIZE).get();
        }
      }
      if (ordersSnap.size > 0) {
        console.log("Deleted chat messages (not order docs) for", ordersSnap.size, "completed orders");
      }
      return null;
    });

// --- Broadcast notifikasi ke semua user (admin only) ---
exports.broadcastNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const adminSnap = await admin.firestore().collection("users").doc(context.auth.uid).get();
  if (!adminSnap.exists || adminSnap.data()?.role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Hanya admin yang dapat broadcast.");
  }
  const title = (data?.title || "Traka").toString().trim() || "Traka";
  const body = (data?.body || "").toString().trim();
  if (!body) {
    throw new functions.https.HttpsError("invalid-argument", "Isi pesan wajib.");
  }
  const payload = {
    topic: "traka_broadcast",
    notification: { title, body },
    android: { priority: "high" },
  };
  await admin.messaging().send(payload);
  return { success: true };
});

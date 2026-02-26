const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Konfigurasi SMTP untuk Gmail
// GANTI EMAIL DAN APP PASSWORD ANDA DI SINI!
const gmailEmail = 'mcctv921@gmail.com'; // Ganti dengan email Gmail Anda
const gmailAppPassword = 'your-app-password-here'; // Ganti dengan App Password Gmail Anda (16 karakter, tanpa spasi)

// Buat transporter untuk Nodemailer
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: gmailEmail,
    pass: gmailAppPassword,
  },
});

// Cloud Function yang trigger saat ada document baru di verification_codes
exports.sendVerificationCode = functions.firestore
  .document('verification_codes/{email}')
  .onCreate(async (snap, context) => {
    // Ambil data dari document yang baru dibuat
    const data = snap.data();
    const email = context.params.email; // Email user (document ID)
    const code = data.code; // Kode verifikasi 6 digit
    const expiresAt = data.expiresAt; // Waktu kedaluwarsa

    // Validasi: pastikan field 'code' ada
    if (!code) {
      console.error('Field "code" tidak ditemukan di document');
      return null;
    }

    // Template email (Text)
    const textTemplate = `
Halo,

Terima kasih telah mendaftar di Traka Travel Kalimantan.

Kode verifikasi Anda adalah: ${code}

Kode ini berlaku selama 10 menit.

Masukkan kode ini di aplikasi untuk menyelesaikan pendaftaran.

Jika Anda tidak meminta kode ini, abaikan email ini.

Salam,
Tim Traka Travel Kalimantan
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
    <p>Terima kasih telah mendaftar di <strong>Traka Travel Kalimantan</strong>.</p>
    
    <p>Kode verifikasi Anda adalah:</p>
    <div class="code-box">${code}</div>
    
    <p>Kode ini berlaku selama <strong>10 menit</strong>.</p>
    <p>Masukkan kode ini di aplikasi untuk menyelesaikan pendaftaran.</p>
    
    <p style="color: #999; font-size: 12px;">
      Jika Anda tidak meminta kode ini, abaikan email ini.
    </p>
    
    <div class="footer">
      <p>Salam,<br>Tim Traka Travel Kalimantan</p>
    </div>
  </div>
</body>
</html>
    `.trim();

    // Konfigurasi email
    const mailOptions = {
      from: `"Traka Travel Kalimantan" <${gmailEmail}>`,
      to: email,
      subject: 'Kode Verifikasi Traka Travel Kalimantan',
      text: textTemplate,
      html: htmlTemplate,
    };

    try {
      // Kirim email
      const info = await transporter.sendMail(mailOptions);
      console.log('Email berhasil dikirim:', info.messageId);
      console.log('Email dikirim ke:', email);
      console.log('Kode verifikasi:', code);
      return null;
    } catch (error) {
      console.error('Error mengirim email:', error);
      // Jangan throw error agar document tetap tersimpan di Firestore
      // User bisa kirim ulang kode jika email gagal
      return null;
    }
  });

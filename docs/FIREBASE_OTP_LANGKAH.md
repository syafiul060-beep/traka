# Langkah Firebase OTP (Phone Authentication) – Terperinci

Aplikasi Traka menggunakan **Firebase Phone Authentication** untuk verifikasi nomor telepon via SMS OTP. Dokumen ini menjelaskan langkah konfigurasi dan alur di kode.

---

## 0. Checklist Konfigurasi (Wajib untuk OTP HP Production)

| Langkah | Status | Keterangan |
|---------|--------|-------------|
| **SHA-1 & SHA-256** | ☐ | Tambah ke Firebase Console → Project settings → Your apps → Add fingerprint |
| **google-services.json** | ☐ | Download ulang setelah tambah SHA, ganti di `android/app/` |
| **Play Integrity API** | ☐ | Enable di Google Cloud Console → APIs & Services → Library |
| **Phone Sign-In** | ☐ | Firebase Console → Authentication → Sign-in method → Phone → Enable |
| **Uji di HP asli** | ☐ | OTP sering gagal di emulator; gunakan perangkat fisik |

Jika OTP gagal dengan error "missing app identifier" atau "Play Integrity", lihat **bagian 2.4** di bawah.

---

## 1. Apakah Bisa Menggunakan Firebase OTP?

**Ya.** Firebase menyediakan **Phone Authentication** yang mengirim kode OTP lewat SMS. Tidak perlu backend tambahan; cukup pakai Firebase Auth di Flutter dengan `firebase_auth`.

---

## 2. Konfigurasi di Firebase Console

### 2.1 Aktifkan Phone Sign-In

1. Buka [Firebase Console](https://console.firebase.google.com/) → pilih project **Traka**.
2. **Authentication** → tab **Sign-in method**.
3. Klik **Phone** → nyalakan **Enable** → **Save**.

### 2.2 (Opsional) Tambah nomor penguji

Untuk development tanpa mengonsumsi SMS sungguhan:

1. Di halaman yang sama (**Phone**), gulir ke **Phone numbers for testing**.
2. Klik **Add phone number**.
3. Masukkan nomor (format E.164, contoh: `+6281234567890`) dan kode 6 digit (mis. `123456`).
4. Simpan. Login/verifikasi dengan nomor itu akan dapat kode tersebut tanpa kirim SMS.

### 2.3 Quota & billing

- Phone Auth memakai **quota gratis** terbatas per hari.
- Jika melebihi, perlu **Blaze (pay-as-you-go)** dan mungkin verifikasi domain/nomor.
- Cek **Usage and billing** di Firebase Console.

### 2.4 Jika muncul error "missing app identifier" / Play Integrity / reCAPTCHA (kirim kode SMS gagal)

Pesan merah seperti *"This request is missing a valid app identifier, Play Integrity checks and reCAPTCHA checks were unsuccessful"* berarti Firebase tidak bisa memverifikasi identitas aplikasi. Lakukan:

1. **Tambah SHA-1 dan SHA-256 ke Firebase**
   - Di Android Studio / terminal:  
     `cd android` lalu `./gradlew signingReport` (atau buka **Gradle** → **app** → **Tasks** → **android** → **signingReport**).
   - Salin **SHA-1** dan **SHA-256** (untuk debug dan release).
   - Firebase Console → **Project settings** (ikon roda) → **Your apps** → pilih aplikasi Android → **Add fingerprint** → tempel SHA-1, lalu tambah lagi SHA-256.

2. **Download ulang google-services.json**
   - Buka **Firebase Console** → klik **ikon roda gigi** di kiri bawah (Project settings).
   - Di tab **General**, scroll ke bawah sampai bagian **"Your apps"**.
   - Di kartu aplikasi **Android** (yang berisi package name Anda), cari:
     - Tombol **"Download google-services.json"**, atau
     - Ikon **tiga titik (⋮)** / menu di kanan kartu → pilih **"Download google-services.json"**.
   - Jika tidak ada tombol: pastikan Anda memilih **aplikasi Android** (bukan iOS/Web). File hanya tersedia untuk app Android. Bisa juga coba buka **Project settings** → **General** → gulir ke **Your apps** → klik **nama/ikon app Android** untuk memperluas kartu; tombol download biasanya di sana.
   - Simpan file yang diunduh, lalu **ganti** isi `android/app/google-services.json` di project Flutter dengan isi file baru tersebut.
   - Build ulang: `flutter clean` lalu `flutter run`.

3. **Aktifkan Play Integrity API (Google Cloud)**
   - Buka [Google Cloud Console](https://console.cloud.google.com/) → pilih project yang sama dengan Firebase.
   - **APIs & Services** → **Library** → cari **Google Play Integrity API** → **Enable**.

4. **Uji di HP asli**
   - Phone Auth sering gagal di emulator. Uji di perangkat Android asli yang sudah login Google Play.

5. **(Opsional) Nomor uji**
   - Sementara bisa pakai **Phone numbers for testing** di Firebase (bagian 2.2) agar tidak bergantung SMS dan Play Integrity saat development.

Setelah langkah di atas, coba lagi **Kirim kode SMS**. Jika masih gagal, cek logcat untuk pesan error detail.

### 2.5 Jika muncul "blocked due to unusual activity" (tidak terima OTP)

Pesan *"We have blocked all requests from this device due to unusual activity"* berarti Firebase **sementara memblokir perangkat** (bukan nomor tidak terdaftar). SMS OTP **tidak akan dikirim** selama blokir aktif.

**Penyebab umum:** Terlalu banyak percobaan kirim kode dalam waktu singkat (rate limit / anti-abuse).

**Yang bisa dilakukan:**
- **Tunggu beberapa jam** (biasanya 1–24 jam) lalu coba lagi dari perangkat yang sama.
- Coba dari **jaringan lain** (misalnya Wi‑Fi lain atau data seluler) lalu kirim kode lagi.
- Hindari mengklik "Kirim kode SMS" berulang kali; tunggu sampai layar OTP muncul atau ada pesan gagal sebelum coba lagi.

Nomor **tidak perlu** ditambah di "Phone numbers for testing" untuk terima OTP sungguhan. Kalau perangkat sudah tidak diblokir, SMS OTP akan dikirim ke nomor yang Anda masukkan (yang tidak ada di daftar testing).

---

## 3. Konfigurasi di Flutter (pubspec.yaml)

Tidak perlu paket tambahan. Cukup **firebase_auth** (dan **firebase_core**):

```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
```

Pastikan `flutter pub get` sudah dijalankan.

---

## 4. Alur Verifikasi OTP di Aplikasi

### 4.1 Mengirim kode SMS (verifyPhoneNumber)

1. User memasukkan **nomor telepon** (Indonesia: bisa `08123456789` atau `8123456789`).
2. Aplikasi mengonversi ke format **E.164** (contoh: `+628123456789`).
3. Panggil:

   ```dart
   await FirebaseAuth.instance.verifyPhoneNumber(
     phoneNumber: phoneE164,  // wajib +62...
     verificationCompleted: (PhoneAuthCredential credential) async {
       // Auto-verify (mis. di emulator/instant verification)
       final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
       // lanjutkan login...
     },
     verificationFailed: (FirebaseAuthException e) {
       // tampilkan e.message
     },
     codeSent: (String verificationId, int? resendToken) {
       // simpan verificationId; tampilkan form masukkan OTP
     },
     codeAutoRetrievalTimeout: (String verificationId) {},
   );
   ```

4. Firebase mengirim SMS berisi kode 6 digit ke nomor tersebut.
5. Di callback **codeSent**, simpan `verificationId` (dan opsional `resendToken` untuk kirim ulang).

### 4.2 Memverifikasi kode (signInWithCredential / linkWithCredential)

1. User memasukkan **kode 6 digit** dari SMS.
2. Buat credential:

   ```dart
   final credential = PhoneAuthProvider.credential(
     verificationId: verificationId,  // dari codeSent
     smsCode: code,                     // 6 digit dari user
   );
   ```

3. **Login dengan telepon (akun hanya phone):**

   ```dart
   final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
   String? uid = userCredential.user?.uid;
   ```

4. **Menautkan telepon ke akun email (profil driver):**

   ```dart
   final user = FirebaseAuth.instance.currentUser;
   await user!.linkWithCredential(credential);
   // lalu simpan nomor ke Firestore: users/{uid}.phoneNumber
   ```

---

## 5. Di Mana OTP Dipakai di Traka

| Fitur | File | Kegunaan |
|-------|------|----------|
| **Tambah/Ubah No. Telepon (profil driver)** | `lib/screens/profile_driver_screen.dart` | Dialog `_TeleponVerifikasiDialog`: input nomor → Kirim kode SMS → input OTP → `linkWithCredential` + update Firestore `users/{uid}.phoneNumber`. |
| **Login dengan No. Telepon** | `lib/screens/login_screen.dart` | Toggle "Login dengan No. Telepon" → input nomor → Kirim kode SMS → input OTP → `signInWithCredential(credential)` → `_handlePostLogin(uid)`. |

---

## 6. Format Nomor Indonesia (E.164)

- Format baku: **+62** diikuti nomor tanpa leading zero.  
  Contoh: `08123456789` → `+628123456789`.
- Di kode (helper):

  ```dart
  String _phoneToE164(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = '62${digits.substring(1)}';
    else if (!digits.startsWith('62')) digits = '62$digits';
    return '+$digits';
  }
  ```

---

## 7. Ringkasan Langkah (Checklist)

1. **Firebase Console**: Authentication → Sign-in method → **Phone** → Enable.
2. **Testing**: (opsional) tambah nomor uji di "Phone numbers for testing".
3. **Flutter**: pakai `firebase_auth`; panggil `verifyPhoneNumber` → dapat `verificationId` di `codeSent`.
4. User masukkan OTP → `PhoneAuthProvider.credential(verificationId, smsCode)` → `signInWithCredential` (login) atau `linkWithCredential` (tambah no. ke akun email).
5. Simpan nomor ke Firestore jika dipakai untuk profil/login (contoh: `users/{uid}.phoneNumber`).

Dengan ini, **Firebase OTP** sudah bisa dipakai untuk verifikasi SMS dan login/tambah nomor telepon di Traka.

# Panduan Lengkap Setup Firebase & Konfigurasi Traka

Dokumen ini memandu pengaturan Firebase dan konfigurasi lain agar fitur **login**, **registrasi**, **verifikasi wajah**, serta pembedaan **Penumpang** dan **Driver** berfungsi penuh di aplikasi Traka Travel Kalimantan.

---

## Daftar Isi

1. [Persiapan Awal](#1-persiapan-awal)
2. [Konfigurasi Android untuk Deteksi Wajah (ML Kit)](#2-konfigurasi-android-untuk-deteksi-wajah-ml-kit)
3. [Membuat dan Mengatur Project Firebase](#3-membuat-dan-mengatur-project-firebase)
4. [Menghubungkan App Android ke Firebase](#4-menghubungkan-app-android-ke-firebase)
5. [Menghubungkan App iOS ke Firebase (Opsional)](#5-menghubungkan-app-ios-ke-firebase-opsional)
6. [Menambah Firebase ke Project Flutter](#6-menambah-firebase-ke-project-flutter)
7. [Mengaktifkan Firebase Authentication](#7-mengaktifkan-firebase-authentication)
8. [Mengaktifkan Cloud Firestore](#8-mengaktifkan-cloud-firestore)
9. [Mengaktifkan Firebase Storage](#9-mengaktifkan-firebase-storage)
10. [Alur Kode: Registrasi dan Login](#10-alur-kode-registrasi-dan-login)
11. [Kode Verifikasi Email (Opsional)](#11-kode-verifikasi-email-opsional)
12. [Checklist dan Troubleshooting](#12-checklist-dan-troubleshooting)

---

## 1. Persiapan Awal

### Yang harus sudah ada

- **Akun Google** untuk login ke [Firebase Console](https://console.firebase.google.com/).
- **Flutter** terpasang dan project Traka bisa dijalankan (`flutter run`).
- **Android Studio** atau **VS Code** dengan ekstensi Flutter (untuk mengedit file konfigurasi).
- **Node.js** (opsional, hanya jika nanti pakai Cloud Functions untuk kirim kode verifikasi).

### Yang akan Anda lakukan (ringkasan)

1. Mengatur Android agar fitur deteksi wajah (ML Kit) jalan.
2. Membuat project Firebase dan mendaftarkan app Android (dan iOS jika perlu).
3. Menambah paket Firebase ke Flutter dan inisialisasi Firebase di app.
4. Mengaktifkan Authentication, Firestore, dan Storage di Firebase Console.
5. Menghubungkan alur registrasi dan login di kode dengan Firebase.

Urutan di dokumen ini sengaja diurutkan agar Anda bisa ikuti langkah demi langkah tanpa bingung.

---

## 2. Konfigurasi Android untuk Deteksi Wajah (ML Kit)

### Mengapa perlu diatur?

Fitur **upload foto diri** di halaman registrasi memakai **Google ML Kit Face Detection**. Di Android, ML Kit membutuhkan **minSdkVersion minimal 23** (Android 6.0). Jika tidak diatur, build bisa gagal atau deteksi wajah tidak berjalan.

### Langkah

1. Buka file **`android/app/build.gradle.kts`** di editor.
2. Cari blok **`defaultConfig`** (biasanya ada di dalam blok `android { ... }`).
3. Cari baris yang memuat **`minSdk`** (sering tertulis `minSdk = flutter.minSdkVersion`).
4. Ubah menjadi salah satu:
   - **Opsi A – tetap pakai nilai dari Flutter, tapi minimal 23:**
     ```kotlin
     minSdk = 24  // Flutter default sering 21; 24 aman untuk ML Kit
     ```
   - **Opsi B – nilai tetap 23:**
     ```kotlin
     minSdk = 23
     ```
5. Simpan file.

### Contoh tampilan blok yang diubah

```kotlin
defaultConfig {
    applicationId = "com.example.traka"
    minSdk = 24                    // ← baris yang diubah
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

### Jika muncul error

- Pastikan tidak ada typo (misalnya `minSdk` ditulis `minSDK`).
- Jalankan ulang: `flutter clean` lalu `flutter pub get` dan `flutter run`.

---

## 3. Membuat dan Mengatur Project Firebase

### 3.1 Membuka Firebase Console

1. Buka browser dan kunjungi: **https://console.firebase.google.com/**
2. Login dengan **akun Google** jika diminta.
3. Anda akan melihat daftar project (jika pernah buat) atau layar “Create a project”.

### 3.2 Membuat project baru

1. Klik **“Add project”** atau **“Create a project”**.
2. **Nama project:** isi misalnya **`traka-travel`** (atau nama lain yang mudah diingat).  
   - Nama ini hanya dipakai di Firebase Console, tidak harus sama dengan nama app di HP.
3. Klik **“Continue”**.
4. **Google Analytics:** bisa diaktifkan atau dinonaktifkan.  
   - Untuk pemula, nonaktifkan saja dulu agar wizard lebih singkat. Bisa diaktifkan nanti.
5. Klik **“Create project”** dan tunggu beberapa detik.
6. Setelah muncul **“Your new project is ready”**, klik **“Continue”**.

Anda sekarang ada di **Project Overview** (halaman utama project Firebase).

### 3.3 Memastikan project yang aktif

Di kiri atas, pastikan nama project yang terpilih adalah **traka-travel** (atau nama yang tadi Anda pakai). Jika punya banyak project, selalu pilih project Traka sebelum mengatur Authentication, Firestore, atau Storage.

---

## 4. Menghubungkan App Android ke Firebase

Supaya app Flutter (Android) bisa pakai Authentication, Firestore, dan Storage, app Android harus “didaftarkan” ke project Firebase dan Anda perlu file **google-services.json**.

### 4.1 Mencari Android package name

1. Buka file **`android/app/build.gradle.kts`** di project Traka.
2. Cari baris **`applicationId`** di dalam **`defaultConfig`**.  
   - Biasanya tertulis: **`applicationId = "com.example.traka"`**.
3. Catat nilai ini (misalnya **`com.example.traka`**). Ini yang disebut **Android package name**.

### 4.2 Mendaftarkan app Android di Firebase

Ini langkah agar Firebase “mengenal” app Android Anda dan memberi file **google-services.json**. Tanpa ini, app tidak bisa memakai Authentication, Firestore, atau Storage.

#### Di mana memulai?

Jika Anda sedang di halaman **Firestore**, **Authentication**, atau menu lain:

1. Klik **“Project Overview”** di menu kiri (pojok kiri atas, di bawah nama project seperti **syafiul-traka** atau **traka-travel**).  
2. Anda akan masuk ke **halaman utama project** (Project Overview).

**Cara lain** (tanpa lewat Project Overview):

1. Klik **ikon roda** ⚙️ di samping **“Project Overview”** (Project settings).
2. Gulir ke bagian **“Your apps”**.
3. Klik **“Add app”** lalu pilih ikon **Android** (robot hijau).

---

#### Langkah 1: Buka halaman “tambah app”

1. Pastikan project yang aktif adalah project Traka Anda (nama di kiri atas, misalnya **syafiul-traka**).
2. Klik **“Project Overview”** di menu kiri sehingga Anda ada di halaman utama project.
3. Di tengah halaman, Anda akan melihat **kartu-kartu untuk menambah app**:
   - **Android** (bergambar robot hijau),
   - **iOS** (ikon apel),
   - **Web** (ikon `</>`).
4. Klik kartu **Android** (robot hijau).  
   - Jika ada tulisan **“Add app”** dan beberapa ikon, pilih yang **Android**.

Setelah itu akan terbuka **wizard “Add Firebase to your Android app”**.

---

#### Langkah 2: Isi Android package name dan daftarkan

1. Di layar **“Register app”**, isi:
   - **Android package name:** ketik persis seperti `applicationId` dari **4.1**, misalnya **`com.example.traka`**.  
     - Harus sama persis; salah sedikit akan bikin app tidak jalan.
   - **App nickname (optional):** boleh dikosongkan atau diisi, misalnya “Traka Android”.
   - **Debug signing certificate SHA-1 (optional):** boleh dikosongkan dulu (untuk Login dengan Google nanti bisa ditambah).
2. Klik **“Register app”**.

---

#### Langkah 3: Download google-services.json

1. Di layar berikutnya, Firebase menawarkan **“Download google-services.json”**.
2. Klik **“Download google-services.json”**.
3. File akan terunduh ke komputer (biasanya di folder **Downloads**).
4. Klik **“Next”**.

---

#### Langkah 4: Letakkan file di project Flutter

1. Buka folder project Traka di komputer (folder yang di dalamnya ada **pubspec.yaml**, **android/**, **lib/**, dll.).
2. Masuk ke folder **`android`**, lalu ke folder **`app`**.  
   - Path lengkap: **`traka/android/app/`**  
     (ganti **traka** dengan nama folder project Anda jika berbeda).
3. **Pindahkan** atau **salin** file **google-services.json** dari folder Download ke dalam **`android/app/`**.
4. Pastikan di dalam **`android/app/`** hanya ada **satu** file bernama **google-services.json**.

Contoh path akhir file:

```
traka/
  android/
    app/
      google-services.json   ← file harus ada di sini
      build.gradle.kts
      ...
```

5. Kembali ke browser Firebase, klik **“Next”** lalu **“Continue to console”**.  
   Wizard selesai; app Android sudah terdaftar di project Firebase.

### 4.3 Memastikan plugin Google Services dipakai (Android)

**Penting:** Jika Anda sudah menjalankan **`flutterfire configure`**, plugin **Google Services** biasanya sudah ditambahkan di **`android/settings.gradle.kts`**. Jangan tambah blok **`plugins`** di **`android/build.gradle.kts`** yang berisi `com.android.application`, `kotlin-android`, atau versi plugin lain — itu bisa bentrok dengan konfigurasi di `settings.gradle.kts` (misalnya versi 8.11.1) dan menimbulkan error **"plugin already on classpath with different version"** saat `flutter run`.

Yang perlu dicek:

1. Buka file **`android/app/build.gradle.kts`** (bukan `android/build.gradle.kts`).
2. Gulir ke **paling bawah** file.
3. Pastikan di dalam blok **`plugins { }`** ada baris:
   ```kotlin
   id("com.google.gms.google-services")
   ```
   Jika belum ada, tambahkan di dalam blok `plugins { }` (biasanya setelah `id("dev.flutter.flutter-gradle-plugin")`). Pakai **`id("...")`**, jangan `apply(plugin = "...")` — di Kotlin DSL itu memicu error "Cannot find a parameter with this name: plugin".
4. Simpan file.

Jika setelah `flutterfire configure` tetap ada error soal Google Services, buka **`android/settings.gradle.kts`** dan pastikan di blok **`plugins`** ada baris:
   ```kotlin
   id("com.google.gms.google-services") version("4.3.15") apply false
   ```
   (Versi bisa sedikit berbeda; yang penting plugin ikut terdaftar.)

### 4.4 SHA-1 (opsional, untuk Login dengan Google nanti)

Jika nanti ingin pakai **“Login dengan Google”**, Firebase perlu **SHA-1** dari lingkungan development Anda.

- **Windows (PowerShell):**  
  Buka terminal di folder **`traka`**, jalankan:
  ```bash
  cd android
  .\gradlew signingReport
  ```
- **macOS / Linux:**  
  ```bash
  cd android
  ./gradlew signingReport
  ```
- Di output, cari **“SHA1”** untuk **debug** (bukan release). Salin nilai itu, lalu di Firebase Console → **Project settings** → **Your apps** → pilih app Android → **“Add fingerprint”** → tempel SHA-1.

Untuk **Email/Password** saja, SHA-1 boleh dilewati dulu.

---

## 5. Menghubungkan App iOS ke Firebase (Opsional)

Lakukan bagian ini hanya jika Anda akan menjalankan atau publish app untuk **iOS**.

### 5.1 Mencari iOS Bundle ID

1. Buka project di **Xcode** (buka **`ios/Runner.xcworkspace`**).
2. Pilih target **Runner** di kiri.
3. Tab **General** → bagian **Identity** → **Bundle Identifier**.  
   - Biasanya tertulis **`com.example.traka`**. Catat nilai ini.

### 5.2 Mendaftarkan app iOS di Firebase

1. Di Firebase Console → **Project Overview** → klik ikon **iOS** (apel).
2. **Bundle ID:** isi persis seperti Bundle Identifier tadi, misalnya **`com.example.traka`**.
3. **App nickname** dan **App Store ID** boleh dikosongkan. Klik **“Register app”**.
4. **Download GoogleService-Info.plist** → simpan file.
5. **Menambahkan file ke Xcode:**  
   - Buka **Xcode** → project **Runner**.  
   - Klik kanan folder **Runner** di panel kiri → **“Add Files to Runner…”** → pilih **GoogleService-Info.plist**.  
   - Pastikan **“Copy items if needed”** dicentang dan target **Runner** tercentang. Klik **“Add”**.
6. Klik **“Next”** lalu **“Continue to console”**.

---

## 6. Menambah Firebase ke Project Flutter

Ini langkah agar kode Dart bisa memakai Firebase (Auth, Firestore, Storage).

### 6.1 Menginstal FlutterFire CLI

Di terminal (di luar folder project atau di folder mana saja), jalankan satu kali:

```bash
dart pub global activate flutterfire_cli
```

Pastikan **Dart/Flutter** ada di PATH. Jika perintah tidak dikenali, buka dokumentasi Flutter untuk menambahkan **pub cache** ke PATH.

### 6.2 Menghubungkan project Flutter ke Firebase

1. Buka terminal, lalu pindah ke **akar project Traka**:
   ```bash
   cd path/ke/folder/traka
   ```
2. Jalankan:
   ```bash
   flutterfire configure
   ```
3. Jika diminta login, pilih **“Log in with browser”** dan selesaikan login di browser.
4. Pilih **project Firebase** yang tadi dibuat (misalnya **traka-travel**).
5. Pilih platform yang ingin dikonfigurasi (Android, iOS, Web). Centang **Android** (dan iOS/Web jika dipakai).
6. CLI akan:
   - Membuat atau memperbarui file **`lib/firebase_options.dart`**.
   - Menautkan project Flutter ke project Firebase.

Setelah selesai, di folder **`lib/`** seharusnya ada file **`firebase_options.dart`**. **Jangan hapus dan jangan commit ke repo publik** jika berisi info sensitif; tambahkan ke **.gitignore** jika diperlukan.

### 6.3 Menambah dependency Firebase di pubspec.yaml

1. Buka file **`pubspec.yaml`** di akar project Traka.
2. Di dalam **`dependencies:`**, tambahkan (sesuaikan versi jika ingin pakai versi terbaru):
   ```yaml
   firebase_core: ^3.6.0
   firebase_auth: ^5.3.1
   cloud_firestore: ^5.4.4
   firebase_storage: ^12.3.4
   ```
3. Simpan file, lalu di terminal jalankan:
   ```bash
   flutter pub get
   ```

### 6.4 Inisialisasi Firebase di main.dart

1. Buka **`lib/main.dart`**.
2. Tambahkan import di atas:
   ```dart
   import 'package:firebase_core/firebase_core.dart';
   import 'firebase_options.dart';
   ```
3. Ubah fungsi **`main()`** menjadi **async** dan panggil **`Firebase.initializeApp`** sebelum **`runApp`**:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await Firebase.initializeApp(
       options: DefaultFirebaseOptions.currentPlatform,
     );
     runApp(const TrakaApp());
   }
   ```
4. Simpan dan coba jalankan:
   ```bash
   flutter run
   ```
   Jika tidak ada error, Firebase sudah terhubung ke app.

---

## 7. Mengaktifkan Firebase Authentication

Authentication dipakai untuk **login** dan **registrasi** (email & kata sandi).

### 7.1 Membuka Authentication

1. Di Firebase Console, pastikan project **traka-travel** yang aktif.
2. Di menu kiri, klik **“Build”** → **“Authentication”**.
3. Klik **“Get started”** jika baru pertama kali (ada tombol besar di tengah).

### 7.2 Mengaktifkan metode Email/Password

1. Di halaman Authentication, buka tab **“Sign-in method”**.
2. Dari daftar **“Sign-in providers”**, cari **“Email/Password”**.
3. Klik **“Email/Password”**.
4. Nyalakan **“Enable”** (toggle ke kanan).
5. **“Email link”** boleh tidak diaktifkan dulu (bisa dipakai nanti untuk reset password atau verifikasi).
6. Klik **“Save”**.

Sekarang user bisa daftar dan login dengan **email + password** lewat Firebase Auth.

### 7.3 Login dengan Google (opsional)

1. Masih di **Sign-in method**, pilih **“Google”**.
2. **Enable** → pilih **email dukungan** (biasanya email Anda).
3. **Save**.  
   Untuk mengaktifkan di app, Anda perlu menambah kode dan SHA-1 (lihat bagian 4.4). Bisa dilakukan belakangan.

---

## 8. Mengaktifkan Cloud Firestore

Firestore dipakai untuk menyimpan **role** (penumpang/driver), **nama**, **email**, **photoUrl**, dan data profil lain per user.

### 8.1 Membuka Firestore

1. Di Firebase Console, menu kiri: **“Build”** → **“Firestore Database”**.
2. Klik **“Create database”** jika belum pernah buat.

### 8.2 Memilih mode keamanan

1. Pilih **“Start in test mode”** untuk pengembangan awal.  
   - Di sini, semua baca/tulis diizinkan untuk sementara. **Penting:** sebelum production, harus diganti ke **production rules**.
2. Klik **“Next”**.
3. Pilih **lokasi** (region) terdekat, misalnya **asia-southeast1** (Jakarta).  
   - Lokasi tidak bisa diubah setelah database dibuat.
4. Klik **“Enable”** dan tunggu sampai database siap.

### 8.3 Struktur data yang disarankan

Bagian ini menjelaskan **di mana** dan **dengan bentuk apa** data user (role Penumpang/Driver, nama, email, foto, dll.) disimpan di Firestore, serta **kapan** data itu ditulis dan dibaca.

---

#### Firestore itu apa, singkatnya?

- **Firestore** = database “noSQL” di cloud milik Firebase.
- Di dalamnya ada **collection** (bisa dibayangkan seperti **satu folder**).
- Di dalam collection ada **document** (bisa dibayangkan seperti **satu file**).
- Setiap document punya **field** (nama kolom + nilainya), misalnya `role`, `email`, `displayName`.

Jadi: **satu collection = banyak document**, dan **satu document = banyak field**.

---

#### Kenapa pakai struktur `users`?

Saat **login**, Firebase Auth hanya memberi tahu: “user ini siapa” (lewat **UID** = User ID unik).  
Auth **tidak** menyimpan apakah user itu **Penumpang** atau **Driver**.  
Agar app bisa mengarahkan ke **halaman Penumpang** atau **halaman Driver**, kita simpan **role** (dan data profil lain) di Firestore, dalam collection **`users`**, per user satu document.

---

#### Bentuk struktur yang dipakai

- **Nama collection:** `users` (satu “folder” untuk semua user).
- **Document ID:** **UID** user dari Firebase Auth (satu document per user).  
  - UID didapat dari **`FirebaseAuth.instance.currentUser!.uid`** setelah login/daftar.
- **Field** yang disimpan di dalam document itu:

| Nama field    | Jenis    | Contoh / arti |
|---------------|----------|----------------|
| `role`        | string   | `"penumpang"` atau `"driver"` — dipilih waktu daftar (Penumpang/Driver). |
| `email`       | string   | `"budi@email.com"` |
| `displayName` | string   | `"Budi"` (nama yang diisi di form registrasi). |
| `photoUrl`    | string   | URL foto dari Firebase Storage (mis. setelah upload foto diri). |
| `faceVerificationUrl` | string | URL foto wajah untuk verifikasi login dari perangkat baru (di Storage: `users/{uid}/face_verification.jpg`). |
| `deviceId`    | string   | ID unik perangkat (Android: androidId, iOS: identifierForVendor). Digunakan untuk deteksi login dari perangkat baru. |
| `createdAt`  | timestamp| Waktu mendaftar (mis. `Timestamp.now()` saat simpan). |

---

#### Contoh konkret

User **Budi** mendaftar sebagai **Penumpang**. Setelah **createUserWithEmailAndPassword** berhasil, UID-nya misalnya **`abc123xyz`**.

Maka di Firestore:

- **“Path” document:** **`users`** → **`abc123xyz`**  
  (baca: **collection `users`**, **document dengan ID `abc123xyz`**).

- **Isi document `users/abc123xyz`:**

  | Field        | Nilai              |
  |-------------|--------------------|
  | `role`      | `"penumpang"`      |
  | `email`     | `"budi@email.com"` |
  | `displayName` | `"Budi"`        |
  | `photoUrl`  | `"https://..."`    |
  | `createdAt` | (tanggal/waktu)    |

Di Firebase Console → Firestore Database, Anda akan melihat kira-kira: **`users`** → klik → ada document **`abc123xyz`** → klik → tampil field-field di atas.

---

#### Kapan menulis (save) ke Firestore?

**Saat registrasi berhasil** (setelah akun Firebase Auth dibuat dan foto di-upload):

1. Ambil **UID** dari `FirebaseAuth.instance.currentUser!.uid`.
2. Buat/set document **`users/{uid}`** dengan field:
   - `role`: `"penumpang"` atau `"driver"` (sesuai pilihan user di form daftar),
   - `email`, `displayName`, `photoUrl`, `createdAt`.
3. Di Flutter biasanya pakai **`FirebaseFirestore.instance.collection("users").doc(uid).set({ ... })`**.

Dengan begitu, setiap user yang sudah daftar punya “profil” sendiri di **`users/{uid}`**.

---

#### Kapan membaca (read) dari Firestore?

**Saat login berhasil**:

1. Ambil **UID** dari `FirebaseAuth.instance.currentUser!.uid`.
2. Baca document **`users/{uid}`** (misalnya pakai **`FirebaseFirestore.instance.collection("users").doc(uid).get()`**).
3. Dari snapshot document, ambil field **`role`** (string).
4. Lalu di kode:
   - jika **`role == "penumpang"`** → arahkan ke **halaman Home Penumpang**,
   - jika **`role == "driver"`** → arahkan ke **halaman Home Driver**.

Jadi, **struktur data yang disarankan** = simpan **satu document per user** di **collection `users`**, dengan **Document ID = UID** dan field **`role`**, **`email`**, **`displayName`**, **`photoUrl`**, **`createdAt`**. **Tulis** saat daftar, **baca** (terutama **`role`**) saat login untuk tentukan halaman Penumpang atau Driver.

---

#### Cara mengatur struktur di Firebase Console

Ada **dua cara**: struktur dibuat **otomatis dari kode Flutter** saat user daftar (cara normal), atau dibuat **manual di Firebase Console** untuk uji coba.

---

##### Opsi A: Otomatis dari kode Flutter (cara normal)

**Tidak perlu membuat collection atau document secara manual di Firebase Console.** Struktur akan terbentuk otomatis saat user pertama kali mendaftar lewat app Flutter.

**Yang perlu Anda lakukan:**

1. Pastikan Firestore sudah diaktifkan (lihat bagian **8.1** dan **8.2**).
2. Di kode Flutter, saat registrasi berhasil (setelah `createUserWithEmailAndPassword`), tambahkan kode untuk menyimpan ke Firestore (lihat bagian **10.1** untuk contoh kode).
3. Saat user pertama kali daftar lewat app, collection **`users`** akan otomatis dibuat, dan document dengan ID = UID user akan muncul di dalamnya.

**Cara melihat hasilnya:**

1. Buka Firebase Console → **Firestore Database**.
2. Di panel kiri, Anda akan melihat collection **`users`** muncul setelah ada user yang daftar.
3. Klik **`users`** → akan muncul daftar document (satu per user yang sudah daftar).
4. Klik salah satu document (misalnya UID **`abc123xyz`**) → di panel kanan akan tampil field-field seperti `role`, `email`, `displayName`, dll.

---

##### Opsi B: Buat manual di Firebase Console (untuk uji coba)

Jika ingin melihat struktur atau menguji sebelum ada user yang daftar, Anda bisa membuat collection dan document secara manual:

**Langkah 1: Buat collection `users`**

1. Buka Firebase Console → **Firestore Database**.
2. Klik **“Start collection”** (tombol besar di tengah, atau tombol **“+ Start collection”** di kiri atas).
3. **Collection ID:** ketik **`users`** (huruf kecil, tanpa spasi).
4. Klik **“Next”**.

**Langkah 2: Buat document pertama (contoh)**

1. **Document ID:** pilih **“Auto-ID”** (Firebase akan generate ID otomatis) atau ketik manual, misalnya **`test123`** (untuk uji coba).
2. **Field pertama:**
   - **Field name:** ketik **`role`**
   - **Type:** pilih **string**
   - **Value:** ketik **`"penumpang"`** (dengan tanda kutip, atau tanpa kutip juga bisa)
   - Klik **“Add field”** atau **“Save”** jika ini field terakhir.
3. **Field kedua:**
   - **Field name:** **`email`**
   - **Type:** **string**
   - **Value:** **`"test@email.com"`**
   - Klik **“Add field”**.
4. **Field ketiga:**
   - **Field name:** **`displayName`**
   - **Type:** **string**
   - **Value:** **`"Test User"`**
   - Klik **“Add field”**.
5. **Field keempat:**
   - **Field name:** **`photoUrl`**
   - **Type:** **string**
   - **Value:** **`"https://example.com/photo.jpg"`** (atau kosongkan dulu dengan **`""`**)
   - Klik **“Add field”**.
6. **Field kelima:**
   - **Field name:** **`createdAt`**
   - **Type:** pilih **timestamp**
   - **Value:** klik ikon kalender → pilih tanggal/waktu sekarang, atau klik **“Set to now”** jika ada opsi itu.
   - Klik **“Save”**.

Setelah itu, di Firestore Database Anda akan melihat:
- Collection **`users`** di panel kiri.
- Di dalamnya ada document **`test123`** (atau ID yang Anda buat).
- Saat klik document itu, di panel kanan tampil semua field yang tadi dibuat.

**Catatan:** Document yang dibuat manual ini hanya untuk uji coba. Di production, document dibuat otomatis dari kode Flutter saat user daftar, dengan **Document ID = UID** user (bukan ID manual seperti `test123`).

---

##### Cara mengedit atau menghapus document di Firebase Console

- **Edit field:** Klik document → klik field yang ingin diubah → ubah nilai → klik **“Update”** atau tekan Enter.
- **Hapus field:** Klik field → klik ikon **hapus** (trash) → konfirmasi.
- **Hapus document:** Klik document di daftar → klik ikon **hapus** (trash) di toolbar → konfirmasi.
- **Hapus collection:** Klik collection **`users`** → klik ikon **hapus** (trash) → ketik nama collection untuk konfirmasi → hapus.

**Peringatan:** Menghapus collection atau document akan menghapus data secara permanen. Pastikan Anda yakin sebelum menghapus.

---

### 8.4 Aturan keamanan (untuk production)

Bagian ini menjelaskan cara mengatur **Security Rules** di Firestore agar hanya user yang terautentikasi dan memiliki akses yang sesuai yang bisa membaca/menulis data.

---

#### Apa itu Security Rules?

**Security Rules** = aturan keamanan yang menentukan siapa yang boleh membaca (`read`) atau menulis (`write`) data di Firestore.

- **Test mode** (default saat pertama kali buat Firestore): semua orang bisa baca/tulis selama 30 hari. Cocok untuk development, tapi **tidak aman untuk production**.
- **Production rules**: hanya user yang login dan sesuai kondisi tertentu yang bisa akses. Lebih aman untuk app yang sudah dipakai user.

---

#### Cara membuka dan mengedit Rules di Firebase Console

**Langkah 1: Buka tab Rules**

1. Buka Firebase Console → **Firestore Database**.
2. Di bagian atas halaman Firestore, ada beberapa tab: **Data**, **Indexes**, **Usage**, **Rules**.
3. Klik tab **“Rules”**.

Anda akan melihat editor teks yang berisi rules saat ini (misalnya rules test mode yang membolehkan semua akses).

**Langkah 2: Edit rules**

1. Di editor Rules, Anda akan melihat kode seperti ini (jika masih test mode):
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if false;
       }
     }
   }
   ```
   Atau mungkin seperti ini (jika masih dalam periode test mode 30 hari):
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if request.time < timestamp.date(2024, 2, 28);
       }
     }
   }
   ```

2. **Hapus semua** teks di editor, lalu **paste** rules berikut:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
       }
   }
   }
   ```

**Penjelasan singkat rules di atas:**

- **`match /users/{userId}`**: aturan ini berlaku untuk collection **`users`**, dan **`{userId}`** adalah variabel yang mewakili Document ID (UID user).
- **`allow read, write:`**: izinkan membaca dan menulis.
- **`if request.auth != null`**: hanya jika user sudah login (terautentikasi).
- **`&& request.auth.uid == userId`**: **dan** UID user yang login sama dengan Document ID (`userId`).

Jadi, user hanya bisa membaca/menulis document **`users/{uid}`** jika:
- User sudah login (`request.auth != null`), **dan**
- UID user yang login sama dengan Document ID (`request.auth.uid == userId`).

Contoh: User dengan UID **`abc123`** hanya bisa akses **`users/abc123`**, tidak bisa akses **`users/xyz789`**.

**Langkah 3: Publish rules**

1. Setelah mengetik/paste rules baru, klik tombol **“Publish”** di kanan atas editor.
2. Firebase akan memvalidasi rules. Jika ada error sintaks, akan muncul pesan merah di bawah editor.
3. Jika validasi berhasil, rules akan langsung aktif.

**Catatan:** Setelah publish, rules langsung berlaku untuk semua request ke Firestore. Pastikan rules sudah benar sebelum publish.

---

#### Rules untuk development (test mode)

Jika masih dalam fase development dan ingin semua user bisa baca/tulis tanpa batasan (untuk uji coba), gunakan rules berikut:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

**Peringatan:** Rules ini **tidak aman** untuk production karena semua orang bisa akses semua data. Hanya pakai untuk development/testing.

---

#### Cara menguji rules

1. **Simulasi di Firebase Console:**
   - Di tab **Rules**, ada tombol **“Rules Playground”** atau ikon **simulator**.
   - Klik itu → pilih **location** (misalnya `users/abc123`), **method** (read/write), **authenticated** (ya/tidak), **user ID** (misalnya `abc123`).
   - Klik **“Run”** → akan muncul hasil apakah rules mengizinkan atau menolak akses.

2. **Uji dari app Flutter:**
   - Coba login dengan user A, lalu coba baca document **`users/{uidUserA}`** → seharusnya berhasil.
   - Coba baca document **`users/{uidUserB}`** (user lain) → seharusnya gagal (ditolak rules).
   - Logout, lalu coba baca tanpa login → seharusnya gagal.

---

#### Troubleshooting rules

- **Error: "Missing or insufficient permissions"**  
  - Pastikan user sudah login (`request.auth != null`).
  - Pastikan UID user sama dengan Document ID yang diakses.
  - Pastikan rules sudah di-publish.

- **Rules tidak berlaku setelah publish**  
  - Tunggu beberapa detik (propagasi rules bisa butuh waktu).
  - Refresh halaman atau restart app Flutter.
  - Cek apakah rules yang di-publish benar (tidak ada typo).

- **Ingin mengizinkan semua user membaca data tertentu**  
  - Contoh: semua user boleh baca collection **`public_data`**, tapi hanya pemilik yang boleh tulis:
    ```
    match /public_data/{docId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == resource.data.ownerId;
    }
    ```

Untuk fase development, **test mode** sudah cukup. Saat app siap production, ganti ke production rules yang lebih ketat seperti contoh di atas.

---

## 9. Mengaktifkan Firebase Storage

Storage dipakai untuk menyimpan **foto diri** user yang diupload saat registrasi.

### 9.1 Membuka Storage

1. Di Firebase Console: **“Build”** → **“Storage”**.
2. Klik **“Get started”**.

### 9.2 Memilih mode keamanan

1. Pilih **“Start in test mode”** untuk pengembangan.  
   - Sama seperti Firestore, untuk production nanti rules harus diperketat.
2. Klik **“Next”**.
3. Pilih **lokasi** (bisa sama dengan Firestore, misalnya **asia-southeast1**).
4. Klik **“Done”**.

### 9.3 Struktur folder yang disarankan

Simpan foto profil di path:

- **`users/{userId}/photo.jpg`**

Jadi setiap user punya satu folder **`users/{uid}/`** dan di dalamnya file **`photo.jpg`** (atau nama lain yang konsisten).

### 9.4 Aturan keamanan (untuk production)

Di tab **“Rules”** Storage, contoh rules yang hanya mengizinkan user mengupload ke folder miliknya:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Untuk development, **test mode** boleh dipakai dulu.

---

## 10. Alur Kode: Registrasi dan Login

Bagian ini menjelaskan **urutan logika** yang perlu Anda implementasikan di **`register_screen.dart`** dan **`login_screen.dart`**, tanpa menuliskan semua kode baris per baris.

### 10.1 Alur Registrasi (Tombol “Ajukan”)

Lakukan dengan urutan berikut (bisa disesuaikan detailnya):

1. **Validasi form**
   - Foto wajah sudah diambil dan lulus deteksi.
   - Nama, email, kode verifikasi (jika dipakai), kata sandi, dan konfirmasi kata sandi terisi dan valid.

2. **Buat akun Firebase Auth**
   - Panggil:
     ```dart
     FirebaseAuth.instance.createUserWithEmailAndPassword(
       email: emailController.text.trim(),
       password: passwordController.text,
     );
     ```
   - Simpan **uid** dari **`userCredential.user!.uid`**.

3. **Verifikasi kode** (jika pakai kode 6 digit)
   - Sebelum atau sesudah `createUserWithEmailAndPassword`, cek kode yang user input dengan kode yang disimpan di Firestore/Cloud Function (lihat bagian 11).

4. **Upload foto ke Storage**
   - Gunakan **uid** tadi.
   - Path: **`users/{uid}/photo.jpg`**.
   - Ambil **download URL** setelah upload.

5. **Simpan profil di Firestore**
   - Collection **`users`**, document ID = **uid**.
   - Field: **`role`** (`"penumpang"` atau `"driver"` sesuai pilihan user), **`email`**, **`displayName`**, **`photoUrl`** (dari Storage), **`createdAt`** (Timestamp.now()).

6. **Feedback ke user**
   - Tampilkan pesan: **“Pendaftaran berhasil silahkan login”**.
   - Navigasi kembali ke halaman login (misalnya **`Navigator.popUntil`** ke route pertama).

7. **Jika ada error** (email sudah dipakai, network gagal, dll.)
   - Tangkap exception dari **`createUserWithEmailAndPassword`** atau dari upload/ Firestore.
   - Tampilkan: **“Pendaftaran belum berhasil silahkan periksa ulang data pendaftaran yang benar”** (atau pesan yang lebih spesifik jika ingin).

### 10.2 Alur Login (Tombol “Masuk”)

1. **Validasi**  
   - Email dan kata sandi tidak kosong.

2. **Login ke Firebase Auth**
   - Panggil:
     ```dart
     FirebaseAuth.instance.signInWithEmailAndPassword(
       email: emailController.text.trim(),
       password: passwordController.text,
     );
     ```
   - Ambil **uid** dari **`userCredential.user!.uid`**.

3. **Ambil role dari Firestore**
   - Baca document **`users/{uid}`**.
   - Ambil field **`role`** (string).

4. **Navigasi berdasarkan role**
   - Jika **`role == "penumpang"`** → arahkan ke **Home Penumpang** (nama widget/route bisa Anda tentukan).
   - Jika **`role == "driver"`** → arahkan ke **Home Driver**.

5. **Remember me**
   - Jika user mencentang “Remember me”, simpan **email** (atau token) di **SharedPreferences** seperti yang sudah ada di kode sekarang. Saat buka app lagi, boleh auto-isikan email atau auto-login sesuai kebijakan Anda.

---

## 11. Kode Verifikasi Email (Opsional)

Jika ingin kolom **“Masukkan kode verifikasi”** benar-benar dipakai, Anda punya dua pendekatan umum.

### Opsi A: Verifikasi bawaan Firebase (tanpa kode 6 digit)

- Setelah **`createUserWithEmailAndPassword`** berhasil, panggil **`user.sendEmailVerification()`**.
- User membuka email dan klik link verifikasi.
- Di app, Anda bisa cek **`user.emailVerified`** sebelum mengizinkan akses penuh.  
- Kolom “Masukkan kode verifikasi” di form bisa disembunyikan atau dipakai untuk alur lain (misalnya reset password).

### Opsi B: Kode 6 digit langsung di Flutter (sudah diimplementasikan)

Implementasi ini sudah diterapkan di **`register_screen.dart`**. Kode verifikasi di-generate dan disimpan di Firestore langsung dari Flutter, tanpa perlu Cloud Functions untuk generate dan simpan kode.

**Cara kerja:**

1. **Generate dan simpan kode (saat klik tombol “Kirim kode”)**
   - User klik tombol **refresh** (ikon circular arrow) di samping kolom “Masukkan kode verifikasi”.
   - App generate kode 6 digit random (100000–999999).
   - Kode disimpan di Firestore: collection **`verification_codes`**, document ID = **email user**, dengan field:
     - **`code`** (string): kode 6 digit
     - **`expiresAt`** (timestamp): waktu kedaluwarsa (10 menit dari sekarang)
     - **`createdAt`** (timestamp): waktu dibuat
   - Untuk **development/testing**: kode ditampilkan di SnackBar hijau agar bisa langsung dipakai tanpa perlu cek email.
   - Untuk **production**: tambahkan Cloud Function atau email service untuk kirim email berisi kode (lihat catatan di bawah).

2. **Verifikasi kode (saat klik “Ajukan”)**
   - Sebelum **`createUserWithEmailAndPassword`**, app:
     - Baca document **`verification_codes/{email}`** dari Firestore.
     - Bandingkan kode yang diinput user dengan kode yang tersimpan.
     - Cek apakah kode belum kedaluwarsa (bandingkan `expiresAt` dengan waktu sekarang).
     - Jika kode valid → lanjut buat akun, upload foto, simpan ke Firestore.
     - Jika kode tidak valid atau kedaluwarsa → tampilkan error, user harus kirim ulang kode.

3. **Setelah registrasi berhasil**
   - Document **`verification_codes/{email}`** dihapus (kode sudah dipakai).

**Struktur Firestore untuk kode verifikasi:**

- **Collection:** `verification_codes`
- **Document ID:** email user (misalnya `"budi@email.com"`)
- **Field:**
  - `code` (string): kode 6 digit
  - `expiresAt` (timestamp): waktu kedaluwarsa
  - `createdAt` (timestamp): waktu dibuat

**Catatan untuk production (kirim email):**

Saat ini, untuk development, kode ditampilkan di SnackBar. Untuk production, Anda bisa:

- **Opsi 1:** Pakai **Firebase Extensions** → **“Trigger Email”** atau **“Send Email via SMTP”** yang otomatis kirim email saat ada document baru di **`verification_codes`**.
- **Opsi 2:** Buat **Cloud Function** yang:
  - Trigger saat ada document baru di **`verification_codes/{email}`**.
  - Baca field **`code`**.
  - Kirim email berisi kode (pakai **SendGrid**, **Mailgun**, **Nodemailer + SMTP**, atau layanan email lain).
- **Opsi 3:** Pakai layanan email pihak ketiga yang bisa dipanggil dari Flutter (misalnya **EmailJS**, **SendGrid API**, dll.).

**Kode sudah diimplementasikan di `register_screen.dart`:**
- Fungsi **`_sendVerificationCode()`**: generate kode, simpan ke Firestore, tampilkan di SnackBar (development).
- Fungsi **`_onSubmit()`**: verifikasi kode sebelum create user, lalu hapus kode setelah berhasil.

---

#### Langkah-langkah mengatur Firebase untuk kode verifikasi email

Agar fitur kode verifikasi email berfungsi, Anda perlu mengatur beberapa hal di Firebase Console:

---

##### Langkah 1: Pastikan Firestore sudah aktif

1. Buka Firebase Console → **Firestore Database**.
2. Jika belum pernah membuat database, ikuti langkah di bagian **8.1** dan **8.2** (Create database → Start in test mode → pilih lokasi → Enable).
3. Jika sudah ada database, pastikan statusnya **aktif** (tidak ada error di halaman Firestore).

**Catatan:** Collection **`verification_codes`** akan dibuat otomatis saat user pertama kali klik tombol "Kirim kode" di app. Tidak perlu membuat collection ini secara manual.

---

##### Langkah 2: Mengatur Security Rules untuk collection `verification_codes`

Collection **`verification_codes`** perlu diatur agar:
- **Semua orang** bisa **menulis** (create document) saat klik "Kirim kode" (user belum login, jadi tidak bisa pakai `request.auth.uid`).
- **Semua orang** bisa **membaca** document dengan email mereka untuk verifikasi kode.
- Document bisa **dihapus** setelah verifikasi berhasil.

**Cara mengatur:**

1. Di Firebase Console → **Firestore Database** → tab **"Rules"**.
2. Di editor Rules, tambahkan rules untuk collection **`verification_codes`**. Contoh rules lengkap (gabungkan dengan rules untuk `users`):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Rules untuk collection users
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Rules untuk collection verification_codes
    match /verification_codes/{email} {
      // Semua orang bisa membuat document baru (untuk kirim kode)
      allow create: if true;
      // Semua orang bisa membaca document dengan email mereka
      allow read: if true;
      // Semua orang bisa menghapus document (setelah verifikasi berhasil)
      allow delete: if true;
      // Tidak boleh update (hanya create, read, delete)
      allow update: if false;
    }
  }
}
```

3. Klik **"Publish"** untuk menerapkan rules.

**Penjelasan rules di atas:**

- **`allow create: if true`**: siapa saja bisa membuat document baru di `verification_codes/{email}` saat klik "Kirim kode".
- **`allow read: if true`**: siapa saja bisa membaca document untuk verifikasi kode (karena user belum login, tidak bisa pakai `request.auth`).
- **`allow delete: if true`**: siapa saja bisa menghapus document setelah verifikasi berhasil.
- **`allow update: if false`**: tidak boleh update document (hanya create, read, delete).

**Untuk development (test mode):**

Jika Firestore masih dalam **test mode**, rules di atas sudah cukup. Test mode mengizinkan semua read/write selama 30 hari.

**Untuk production (opsional, lebih aman):**

Jika ingin lebih ketat, bisa batasi berdasarkan email yang diinput:

```
match /verification_codes/{email} {
  // Hanya bisa create dengan email yang sesuai
  allow create: if request.resource.id == request.resource.data.email;
  // Hanya bisa read document dengan email tertentu (dari request)
  allow read: if true; // Tetap true karena user belum login
  // Hanya bisa delete document dengan email tertentu
  allow delete: if true; // Tetap true karena user belum login
  allow update: if false;
}
```

Tapi untuk development, rules pertama (`allow create/read/delete: if true`) sudah cukup.

---

##### Langkah 3: Mengatur Security Rules untuk collection `users` (jika belum)

Pastikan collection **`users`** juga punya rules yang sesuai (lihat bagian **8.4**). Contoh:

```
match /users/{userId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

---

##### Langkah 4: Menguji fitur kode verifikasi (development)

1. Jalankan app Flutter: **`flutter run`**.
2. Buka halaman registrasi.
3. Isi email → klik tombol **refresh** (ikon circular arrow) di samping kolom kode verifikasi.
4. **Kode 6 digit akan muncul di SnackBar hijau** (contoh: "Kode verifikasi: 123456").
5. Salin kode dari SnackBar → paste ke kolom "Masukkan kode verifikasi".
6. Lengkapi form lainnya → klik "Ajukan".
7. Jika kode valid, registrasi akan berhasil.

**Cek di Firebase Console:**

- Buka **Firestore Database** → **Data**.
- Anda akan melihat collection **`verification_codes`** muncul setelah klik "Kirim kode".
- Di dalamnya ada document dengan ID = email user (misalnya `"budi@email.com"`).
- Klik document itu → akan tampil field `code`, `expiresAt`, `createdAt`.
- Setelah registrasi berhasil, document ini akan terhapus otomatis.

---

##### Langkah 5: Mengatur kirim email otomatis (opsional, untuk production)

Saat ini, kode ditampilkan di SnackBar (untuk development). Untuk production, Anda bisa kirim email otomatis. Pilih salah satu opsi:

**Opsi A: Firebase Extensions (paling mudah)**

1. Di Firebase Console → **Extensions** (di menu kiri, atau **Build** → **Extensions**).
2. Klik **"Browse all extensions"** atau cari extension **"Trigger Email"** atau **"Send Email via SMTP"**.
3. Install extension → ikuti wizard:
   - Pilih collection: **`verification_codes`**
   - Template email: buat template yang menampilkan field **`code`**
   - SMTP settings: isi SMTP server Anda (Gmail, SendGrid, dll.)
4. Setelah terinstall, setiap kali ada document baru di **`verification_codes`**, extension akan otomatis kirim email berisi kode.

**Opsi B: Cloud Functions (lebih fleksibel)**

1. Install Firebase CLI: **`npm install -g firebase-tools`**.
2. Login: **`firebase login`**.
3. Di folder project Flutter, jalankan: **`firebase init functions`**.
4. Buat function yang trigger saat ada document baru di **`verification_codes`**:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendVerificationCode = functions.firestore
  .document('verification_codes/{email}')
  .onCreate(async (snap, context) => {
    const email = context.params.email;
    const code = snap.data().code;
    
    // Kirim email menggunakan Nodemailer, SendGrid, atau service lain
    // Contoh dengan Nodemailer:
    const nodemailer = require('nodemailer');
    const transporter = nodemailer.createTransport({
      service: 'gmail', // atau SMTP lain
      auth: {
        user: 'your-email@gmail.com',
        pass: 'your-app-password'
      }
    });
    
    await transporter.sendMail({
      from: 'your-email@gmail.com',
      to: email,
      subject: 'Kode Verifikasi Traka',
      text: `Kode verifikasi Anda: ${code}`,
      html: `<p>Kode verifikasi Anda: <strong>${code}</strong></p>`
    });
  });
```

5. Deploy: **`firebase deploy --only functions`**.

**Opsi C: Email service pihak ketiga dari Flutter**

Pakai package seperti **`mailer`** atau **EmailJS** yang bisa dipanggil langsung dari Flutter. Tambahkan di **`_sendVerificationCode()`** setelah simpan ke Firestore.

---

##### Checklist untuk kode verifikasi email

| No | Yang perlu diatur | Sudah? | Catatan |
|----|-------------------|--------|---------|
| 1 | **Firestore aktif** | ☐ | Lihat bagian 8.1-8.2 |
| 2 | **Security Rules untuk `verification_codes`** | ☐ | `allow create/read/delete: if true` untuk development |
| 3 | **Security Rules untuk `users`** | ☐ | `allow read/write: if request.auth.uid == userId` |
| 4 | **Uji kirim kode** | ☐ | Kode muncul di SnackBar (development) |
| 5 | **Uji verifikasi kode** | ☐ | Input kode → registrasi berhasil |
| 6 | **Kirim email otomatis (production)** | ☐ | Opsional: Firebase Extensions atau Cloud Functions |

---

##### Troubleshooting kode verifikasi

- **Error: "Missing or insufficient permissions" saat kirim kode**  
  - Pastikan Security Rules untuk **`verification_codes`** sudah di-publish dengan **`allow create: if true`**.
  - Pastikan Firestore tidak dalam mode yang terlalu ketat.

- **Error: "Kode verifikasi tidak ditemukan"**  
  - Pastikan email yang diinput saat kirim kode sama dengan email yang dipakai saat verifikasi.
  - Cek di Firestore Console apakah document **`verification_codes/{email}`** ada.

- **Error: "Kode verifikasi sudah kedaluwarsa"**  
  - Kode hanya berlaku 10 menit. Minta user klik "Kirim kode" lagi untuk dapat kode baru.

- **Kode tidak muncul di SnackBar**  
  - Cek koneksi internet.
  - Cek console/debug untuk error dari Firestore.
  - Pastikan **`cloud_firestore`** sudah ditambahkan di `pubspec.yaml` dan sudah di-`flutter pub get`.

---

## 12. Checklist dan Troubleshooting

### Checklist singkat

| No | Yang perlu diatur | Sudah? | Catatan |
|----|-------------------|--------|---------|
| 1 | **minSdk Android ≥ 23** | ☐ | Di `android/app/build.gradle.kts` |
| 2 | **Project Firebase dibuat** | ☐ | Nama misalnya traka-travel |
| 3 | **App Android didaftarkan** | ☐ | Package name = applicationId |
| 4 | **google-services.json** di `android/app/` | ☐ | Dari Firebase Console |
| 5 | **Plugin Google Services** di `android/build.gradle.kts` dan `android/app/build.gradle.kts` | ☐ | Lihat bagian 4.3 |
| 6 | **flutterfire configure** sudah dijalankan | ☐ | Ada file `lib/firebase_options.dart` |
| 7 | **firebase_core, firebase_auth, cloud_firestore, firebase_storage** di pubspec.yaml | ☐ | Lalu `flutter pub get` |
| 8 | **Firebase.initializeApp** di main.dart | ☐ | Sebelum runApp() |
| 9 | **Authentication – Email/Password** diaktifkan | ☐ | Sign-in method |
| 10 | **Firestore** dibuat (test mode dulu) | ☐ | Collection `users` dan `verification_codes` |
| 11 | **Storage** dibuat (test mode dulu) | ☐ | Path users/{uid}/photo.jpg |
| 12 | **Security Rules untuk `verification_codes`** | ☐ | `allow create/read/delete: if true` untuk development |
| 13 | **Alur registrasi** di kode (createUser, upload foto, simpan Firestore) | ☐ | register_screen.dart |
| 14 | **Alur login** dan baca role dari Firestore, navigasi Penumpang/Driver | ☐ | login_screen.dart |
| 15 | **Uji kode verifikasi email** | ☐ | Kirim kode → verifikasi → registrasi berhasil |

### Troubleshooting singkat

- **“MissingPluginException” atau “Firebase not initialized”**  
  - Pastikan **Firebase.initializeApp** dipanggil sebelum **runApp**.  
  - Pastikan **google-services.json** (Android) atau **GoogleService-Info.plist** (iOS) benar-benar ada di tempat yang disebutkan dan project dibuild ulang (`flutter clean` lalu `flutter run`).

- **Login/daftar tidak berjalan**  
  - Cek di Firebase Console → **Authentication** → **Sign-in method**: Email/Password harus **Enabled**.  
  - Cek koneksi internet dan pesan error di console/debug.

- **Build Android gagal terkait “minSdk” atau “compileSdk”**  
  - Pastikan di **`android/app/build.gradle.kts`** nilai **minSdk** ≥ 23 dan konsisten dengan dependency (termasuk ML Kit).

- **Foto tidak bisa diupload ke Storage**  
  - Pastikan **Storage** sudah **Get started** dan (untuk development) pakai **test mode**.  
  - Cek **Rules** di tab Storage jika nanti pakai production rules.

- **Role tidak terbaca setelah login**  
  - Pastikan di alur registrasi Anda sudah menulis ke **Firestore** collection **`users`** dengan field **`role`**.  
  - Pastikan path baca di login: **`users/{uid}`** dan **uid** sama dengan **FirebaseAuth.instance.currentUser!.uid**.

- **Kode verifikasi tidak bisa dikirim atau diverifikasi**  
  - Pastikan Security Rules untuk **`verification_codes`** sudah diatur (lihat bagian **11**).  
  - Pastikan collection **`verification_codes`** bisa dibuat (cek di Firestore Console setelah klik "Kirim kode").  
  - Cek apakah kode sudah kedaluwarsa (hanya berlaku 10 menit).

- **Warning: "17 packages have newer versions incompatible with dependency constraints"**  
  - Ini adalah **warning**, bukan error. Build tetap bisa berjalan.  
  - Artinya ada package yang punya versi lebih baru, tapi tidak bisa di-update karena constraint dari package lain.  
  - **Tidak perlu khawatir** untuk development. App tetap berfungsi normal.  
  - Jika ingin update, jalankan **`flutter pub outdated`** untuk lihat detail, lalu update manual di `pubspec.yaml` jika diperlukan (hati-hati dengan breaking changes).

- **Note: "uses unchecked or unsafe operations" atau "deprecated API" dari Google ML Kit**  
  - Ini adalah **catatan kompilasi Java**, bukan error.  
  - Muncul dari package **`google_mlkit_face_detection`** dan **`google_mlkit_commons`**.  
  - **Tidak menghalangi build** atau fungsi app. Deteksi wajah tetap berjalan normal.  
  - Ini adalah warning dari compiler Java tentang penggunaan API yang deprecated atau unchecked operations di kode native package tersebut.  
  - Bisa diabaikan untuk development. Jika ingin hilangkan warning, tunggu update dari maintainer package ML Kit.

- **Error: "Connection closed before full header was received" atau "failed to connect to http://127.0.0.1"**  
  - Error ini muncul saat **`flutter run`** berhasil build APK dan install, tapi koneksi debugging gagal.  
  - **Penyebab umum:** Masalah port forwarding USB antara PC dan HP, atau firewall memblokir koneksi localhost.  
  - **Solusi 1 – Restart ADB via Flutter (tanpa perlu install ADB terpisah):**  
    - Tutup semua terminal Flutter.  
    - Buka terminal baru → masuk ke folder project:
      ```bash
      cd "c:\Users\syafi\OneDrive\Dokumen\Traka\traka"
      ```
    - Cek device terdeteksi:
      ```bash
      flutter devices
      ```
    - Jika HP muncul di daftar, lanjut ke Solusi 2.  
    - Jika HP tidak muncul, cabut dan pasang lagi kabel USB → di HP pilih "Izinkan debugging USB" → jalankan **`flutter devices`** lagi.
    - Setelah device terdeteksi, jalankan:
      ```bash
      flutter run
      ```
  - **Solusi 1b – Jika perlu ADB langsung (opsional):**  
    - ADB biasanya sudah terinstall bersama Android Studio atau Flutter SDK.  
    - Lokasi ADB biasanya di: **`C:\Users\<username>\AppData\Local\Android\Sdk\platform-tools\adb.exe`**  
    - Atau pakai path lengkap saat menjalankan:
      ```bash
      C:\Users\syafi\AppData\Local\Android\Sdk\platform-tools\adb.exe kill-server
      C:\Users\syafi\AppData\Local\Android\Sdk\platform-tools\adb.exe start-server
      ```
    - Atau tambahkan ke PATH Windows (Settings → System → Advanced → Environment Variables → Path → Add → masukkan path ke `platform-tools`).
  - **Solusi 2 – Cek firewall Windows:**  
    - Buka **Windows Defender Firewall** → **Advanced settings**.  
    - Cek **Inbound Rules** dan **Outbound Rules** → pastikan tidak ada rule yang memblokir Flutter atau ADB.  
    - Atau nonaktifkan firewall sementara untuk uji (tidak disarankan untuk jangka panjang).  
    - Tambahkan exception untuk **Flutter**, **Android Studio**, atau **adb.exe** jika perlu.
  - **Solusi 3 – Cek koneksi USB dan USB debugging:**  
    - Cabut dan pasang lagi kabel USB ke HP.  
    - Di HP, pastikan **USB debugging** aktif dan muncul notifikasi "Izinkan debugging USB?" → pilih **Izinkan** (centang "Selalu izinkan dari komputer ini" jika muncul).  
    - Pastikan mode USB = **"Transfer file"** atau **"MTP"**, bukan "Hanya mengisi daya".  
    - Cek device terdeteksi: **`flutter devices`** atau **`adb devices`**.
  - **Solusi 4 – Restart Flutter daemon:**  
    - Tutup semua terminal Flutter.  
    - Buka terminal baru → jalankan:
      ```bash
      flutter clean
      flutter pub get
      flutter run
      ```
  - **Solusi 5 – Coba dengan flag tambahan:**  
    - Jalankan dengan flag untuk skip connection check:
      ```bash
      flutter run --no-sound-null-safety --disable-service-auth-codes
      ```
  - **Solusi 6 – Untuk WiFi Indihome + USB debugging:**  
    - Jika pakai WiFi Indihome dan USB debugging, pastikan:
      - **WiFi di HP dan PC tidak perlu sama** (debugging lewat USB, bukan WiFi).
      - **Tidak ada proxy** di HP (Settings → WiFi → pilih jaringan Indihome → Advanced → Proxy = None).
      - **Tidak ada VPN** aktif di HP atau PC.
      - **USB debugging** aktif dan diizinkan.
    - Jika masih error, coba nonaktifkan WiFi di HP sementara (hanya pakai USB) untuk isolasi masalah.
  - **Catatan penting:**  
    - **App tetap ter-install dan bisa jalan di HP** meski error ini muncul.  
    - Error ini hanya mempengaruhi **hot reload** dan **debugging** (breakpoint, log real-time).  
    - Untuk **testing Firebase** (login, registrasi, dll.), app yang sudah ter-install di HP sudah cukup.  
    - Setelah app ter-install, buka langsung di HP dan uji fitur Firebase.  
    - Jika perlu lihat log, pakai **Android Studio → Logcat** atau **`adb logcat`** di terminal.

---

Setelah semua langkah di atas selesai, integrasikan panggilan Firebase (Auth, Firestore, Storage) ke **`register_screen.dart`** dan **`login_screen.dart`** sesuai alur di bagian 10. Pesan **“Pendaftaran berhasil silahkan login”** dan **“Pendaftaran belum berhasil silahkan periksa ulang data pendaftaran yang benar”** sudah disiapkan di UI; Anda tinggal memanggilnya di saat sukses atau gagal sesuai alur tersebut.

# Keamanan Aplikasi Traka

Dokumen ini menjelaskan langkah keamanan yang diterapkan untuk melindungi pengguna dan aplikasi Traka, termasuk proteksi terhadap **kloning aplikasi** dan **Fake GPS / lokasi palsu**.

---

## 1. Proteksi Fake GPS / Lokasi Palsu

### Tujuan

- Melindungi pengguna dari modus kejahatan yang memanfaatkan lokasi palsu (mis. penipuan, manipulasi region driver).
- Memastikan driver mendaftar dengan lokasi GPS asli, sehingga region/provinsi yang tersimpan di Firestore dapat dipercaya.

### Cara Kerja (Android)

1. **Saat pendaftaran driver**, aplikasi meminta lokasi melalui **platform channel** ke kode native Android.
2. Di **Android**, digunakan **FusedLocationProviderClient** untuk mendapatkan lokasi terbaru.
3. Objek **Location** dari Android memiliki:
   - **API 31+ (Android 12):** `Location.isMock`
   - **API 18–30:** `Location.isFromMockProvider()` (deprecated di API 31)
4. Jika lokasi ditandai sebagai **mock** (Fake GPS / lokasi palsu), aplikasi **tidak melanjutkan** pendaftaran dan menampilkan peringatan.

### Pesan Peringatan

Jika pengguna memakai Fake GPS / lokasi palsu, akan muncul SnackBar merah dengan teks:

- **Indonesia:**  
  *"Aplikasi Traka melindungi pengguna dari berbagai modus kejahatan yang disengaja, matikan Fake GPS/Lokasi palsu jika ingin menggunakan Traka...!"*

- **English:**  
  *"Traka protects users from intentional fraud; turn off Fake GPS/spoofed location to use Traka...!"*

### Kapan Peringatan Muncul

- Hanya saat **pendaftaran driver** (bukan penumpang).
- Hanya di **Android** (deteksi mock location memakai API Android).
- Di **iOS**, deteksi mock location sangat terbatas oleh sistem; perilaku default adalah melanjutkan tanpa cek mock (dapat ditingkatkan nanti jika diperlukan).

### Cara Mengatasi Peringatan

- Pengguna harus **mematikan** aplikasi Fake GPS / "Mock location" di Pengaturan Developer.
- Atau **mencabang** aplikasi mock dari "Select mock location app" (jika ada).
- Setelah itu, gunakan lagi **lokasi GPS asli** dan ulangi pendaftaran driver.

---

## 2. Anti-Kloning dan Keamanan Aplikasi (Rekomendasi)

Berikut langkah yang **disarankan** untuk mengurangi risiko aplikasi di-kloning dan penyalahgunaan. Sebagian dapat diterapkan bertahap.

### 2.1 ProGuard / R8 (Obfuscation)

- **Tujuan:** Mengaburkan kode dan nama class/method di release build sehingga reverse engineering dan kloning lebih sulit.
- **Cara:** Di **`android/app/build.gradle.kts`**, pastikan minify diaktifkan untuk build **release**:

```kotlin
buildTypes {
    release {
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt", "proguard-rules.pro"),
            "proguard-rules.pro"
        )
        signingConfig = signingConfigs.getByName("debug") // ganti dengan signing config release
    }
}
```

- Buat file **`android/app/proguard-rules.pro`** dan tambahkan rule yang diperlukan (mis. keep rule untuk Flutter/Firebase jika ada peringatan).

### 2.2 Signing Config Release (Keamanan Distribusi)

- **Tujuan:** Aplikasi yang di-install dari sumber resmi (mis. Play Store) ditandai dengan signature yang sama; kloning biasanya memakai signature berbeda.
- **Cara:**
  1. Buat **keystore** untuk release (jangan pakai debug key di production).
  2. Di **`android/app/build.gradle.kts`**, gunakan **signingConfig** release dengan keystore tersebut.
  3. Jangan commit file keystore atau password ke repository publik; gunakan variabel lingkungan atau CI secret.

### 2.3 Play App Signing & Play Integrity (Opsional, untuk Play Store)

- **Play App Signing:** Memungkinkan Google mengelola key signing; membantu mendeteksi aplikasi yang di-upload oleh pihak lain.
- **Play Integrity API:** Dapat digunakan nanti untuk memverifikasi bahwa aplikasi berjalan di lingkungan asli (bukan di device yang di-root atau di-modifikasi). Ini melengkapi deteksi Fake GPS dengan verifikasi integritas device/app.

### 2.4 Keamanan Tambahan (Opsional)

- **Certificate pinning** untuk request ke backend/API Anda (jika ada).
- **SafetyNet / Play Integrity** di sisi server untuk validasi token dari client.
- **Pengecekan root** (opsional): di Android bisa mendeteksi root; jika terdeteksi, bisa menampilkan peringatan atau membatasi fitur (mis. hanya tampilkan peringatan, tanpa memblokir sepenuhnya).

---

## 3. Keamanan Device ID

| Fitur | Status | Keterangan |
|-------|--------|------------|
| **Cegah spam device** | ✅ Diimplementasikan | Maks 1 akun per role per device (penumpang + driver = OK). |
| **Rate limit login** | ✅ Diimplementasikan | Maks 10 gagal login per jam per device. |
| **Deteksi emulator** | ✅ Diimplementasikan | Registrasi dan login dari emulator diblokir (`emulator_checker`). |
| **OS + Model + Install ID** | ✅ Diimplementasikan | Disimpan di Firestore untuk audit. |

**Pengecualian**: Device sama untuk akun penumpang dan akun driver diperbolehkan.

- **Layanan**: `lib/services/device_security_service.dart`
- **Device info**: `lib/services/device_service.dart` (getDeviceInfo, getInstallId)

---

## 4. Ringkasan Implementasi Saat Ini

| Fitur | Status | Keterangan |
|-------|--------|------------|
| **Deteksi Fake GPS (Android)** | ✅ Diimplementasikan | Via `Location.isMock` / `isFromMockProvider()` di MainActivity, dipanggil dari Flutter lewat method channel. |
| **Peringatan lokasi palsu** | ✅ Diimplementasikan | Pesan l10n: "Aplikasi Traka melindungi pengguna... matikan Fake GPS/Lokasi palsu...". |
| **Blokir pendaftaran driver jika mock** | ✅ Diimplementasikan | Pendaftaran tidak lanjut; hanya SnackBar peringatan. |
| **ProGuard/R8** | ⏳ Rekomendasi | Bisa diaktifkan di build release (lihat 2.1). |
| **Signing config release** | ⏳ Rekomendasi | Untuk production (lihat 2.2). |
| **Play Integrity** | ⏳ Opsional | Untuk validasi lanjutan di masa depan. |

---

## 5. File yang Terkait

- **Android – deteksi mock location:**  
  `android/app/src/main/kotlin/com/example/traka/MainActivity.kt`  
  (Method channel `traka/location`, method `getLocationWithMockCheck`.)

- **Flutter – layanan lokasi:**  
  `lib/services/location_service.dart`  
  (Pemanggilan method channel, penanganan `isMock`, errorCode `fake_gps`.)

- **Flutter – tampilan peringatan:**  
  `lib/screens/register_screen.dart`  
  (Jika `locationResult.isFakeGpsDetected`, tampilkan `l10n.fakeGpsWarning`.)

- **L10n – teks peringatan:**  
  `lib/l10n/app_localizations.dart`  
  (String `fakeGpsWarning`.)

---

## 6. Testing

### Fake GPS (Android)

1. Aktifkan **Developer options** di HP Android.
2. Pilih **"Select mock location app"** dan pilih aplikasi Fake GPS (mis. "Fake GPS" dari Play Store).
3. Jalankan aplikasi Fake GPS dan set lokasi di luar Indonesia atau di Indonesia (terserah).
4. Buka Traka → Daftar sebagai **Driver** → lengkapi form dan klik **Ajukan**.
5. **Hasil yang diharapkan:** Muncul SnackBar merah dengan pesan:  
   *"Aplikasi Traka melindungi pengguna dari berbagai modus kejahatan yang disengaja, matikan Fake GPS/Lokasi palsu jika ingin menggunakan Traka...!"*  
   Pendaftaran tidak lanjut.

### Lokasi Asli (Android)

1. Matikan atau cabang aplikasi Fake GPS / mock location.
2. Pastikan lokasi perangkat **asli** (GPS/Wi‑Fi/seluler).
3. Daftar lagi sebagai **Driver** dengan lokasi di Indonesia.
4. **Hasil yang diharapkan:** Pendaftaran berhasil dan data driver (termasuk region) tersimpan di Firestore.

---

Dengan ini, aplikasi Traka memiliki proteksi terhadap penggunaan Fake GPS/lokasi palsu saat pendaftaran driver, dan dokumentasi keamanan untuk anti-kloning serta langkah lanjutan yang dapat diterapkan bertahap.

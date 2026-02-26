# Checklist Upload Play Store - Traka

## ✅ Sudah Dicek

### Versi & Build
- **Version:** 1.0.5+6 (versionName: 1.0.5, versionCode: 6)
- **Application ID:** id.traka.app

### Konfigurasi Android
- **Signing:** key.properties + upload-keystore.jks (pastikan file ada)
- **ProGuard:** proguard-rules.pro untuk ML Kit
- **Min/Target SDK:** Mengikuti Flutter default
- **INTERNET permission:** Sudah ditambahkan di manifest utama

### Firebase & Dependencies
- Firebase Core, Auth, Firestore, Storage, Messaging, Crashlytics ✓
- google-services.json ✓
- firebase_options.dart ✓

### Dark Mode
- **Profile driver:** Menu card & Email sheet pakai `Theme.of(context).colorScheme` ✓
- **Profile penumpang:** Email sheet pakai theme-aware colors ✓
- **Data kendaraan:** Form & dropdown pakai theme-aware colors ✓
- **Penumpang screen:** Driver sheet, bottom nav, search bar, loading overlay ✓
- **Map type zoom controls:** Background & outline pakai theme ✓

### Keamanan
- **Google Maps API Key:** Hardcoded di AndroidManifest - pastikan di Google Cloud Console:
  - Restrict by package name: `id.traka.app`
  - Restrict by SHA-1 (dari upload keystore)
- **key.properties:** JANGAN commit ke Git (sudah di .gitignore?)

---

## ⚠️ Perlu Verifikasi Manual

### 1. Build Release
```bash
cd traka
flutter clean
flutter pub get
flutter build appbundle
```
File output: `build/app/outputs/bundle/release/app-release.aab`

### 2. Signing
- Pastikan `android/key.properties` ada dan berisi:
  - storePassword, keyPassword, keyAlias, storeFile
- Pastikan `upload-keystore.jks` ada di path yang benar

### 3. Google Play Console
- [ ] Buat/update aplikasi di Play Console
- [ ] Isi Store Listing (deskripsi, screenshot, dll.)
- [ ] Content rating questionnaire
- [ ] Privacy policy URL (jika belum)
- [ ] Data safety form (Firebase, lokasi, kamera, dll.)

### 4. API Keys
- [ ] Google Maps API: Restrict di Cloud Console
- [ ] Firebase: Pastikan project production-ready

### 5. Testing
- [ ] Test di device fisik (bukan emulator)
- [ ] Test login, pesan travel, kirim barang
- [ ] Test verifikasi wajah & KTP
- [ ] Test in-app purchase (jika ada)
- [ ] Test notifikasi push

---

## 📋 Linter Warnings (Non-blocking)

Beberapa warning yang ada (tidak menghalangi build):
- Unused fields/declarations di penumpang_screen, driver_screen
- Bisa dibersihkan nanti

---

## 🔧 Debug/Print

- `kDebugMode` guard: Semua debugPrint sudah dibungkus kDebugMode ✓
- `main.dart`: debugPrint saat Firebase error (acceptable - critical error)
- `local_storage_service.dart`: print dengan `// ignore: avoid_print` (error logging)

---

## Versi Baru?

Saat upload versi baru, update di `pubspec.yaml`:
```yaml
version: 1.0.6+7  # +1 untuk versionCode
```

# Build Traka untuk Google Play Store

## Persiapan

### 1. Versi (tetap 1.0.1)

Di `pubspec.yaml` sudah ada `version: 1.0.1+2`:
- **1.0.1** = versionName (yang tampil di Play Store)
- **+2** = versionCode (harus naik tiap upload baru ke Play Store)

**Penting:** Jika ini upload **baru** (bukan yang pertama), naikkan build number:
- Upload pertama: `1.0.1+2` ✓
- Upload kedua: ubah jadi `1.0.1+3`
- Upload ketiga: `1.0.1+4`, dst.

Edit `pubspec.yaml` baris 19 jika perlu:
```yaml
version: 1.0.1+3   # naikkan +3, +4, dst untuk tiap upload baru
```

### 2. Signing (key.properties)

Pastikan file `android/key.properties` ada dan berisi:

```properties
storePassword=password_keystore_anda
keyPassword=password_key_anda
keyAlias=upload
storeFile=upload-keystore.jks
```

Dan file `upload-keystore.jks` ada di folder `android/` (atau sesuaikan path di `storeFile`).

> Jika sudah pernah build ke Play Store, file ini biasanya sudah ada. Jangan commit ke Git.

---

## Langkah Build

### 1. Bersihkan build lama

```batch
cd D:\Traka\traka
flutter clean
flutter pub get
```

### 2. Build App Bundle (format untuk Play Store)

```batch
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

> Gunakan **appbundle** (.aab), bukan APK. Play Store meminta AAB sejak 2021.

### 3. Jika Gradle error / stuck

```batch
cd D:\Traka\traka\android
gradlew --stop
cd ..
flutter build appbundle --release
```

Lihat juga `docs/BUILD_STUCK_SOLUSI.md` dan `docs/BUILD_TANPA_DAEMON.md` jika ada masalah.

---

## Upload ke Play Console

1. Buka [Google Play Console](https://play.google.com/console)
2. Pilih aplikasi **Traka**
3. **Production** (atau **Internal testing** / **Closed testing** untuk uji dulu)
4. **Create new release**
5. Upload file: `build/app/outputs/bundle/release/app-release.aab`
6. Isi **Release notes** (perubahan di versi ini)
7. **Review release** → **Start rollout**

---

## Ringkasan Cepat

```batch
cd D:\Traka\traka
flutter clean
flutter pub get
flutter build appbundle --release
```

File hasil: `D:\Traka\traka\build\app\outputs\bundle\release\app-release.aab`

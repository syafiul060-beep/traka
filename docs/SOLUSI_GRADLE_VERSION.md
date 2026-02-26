# Solusi Error Gradle Version Mismatch

## Masalah
Error saat build:
```
Minimum supported Gradle version is 8.13. Current version is 8.9.
Try updating the 'distributionUrl' property in gradle-wrapper.properties
```

## Penyebab
Android Gradle Plugin memerlukan Gradle version yang lebih baru daripada yang terinstall.

## Solusi yang Sudah Diterapkan

### 1. Update Gradle Wrapper
File `android/gradle/wrapper/gradle-wrapper.properties` sudah diupdate:
```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-all.zip
```

### 2. Downgrade Android Gradle Plugin
File `android/settings.gradle.kts` sudah diupdate:
```kotlin
id("com.android.application") version "8.7.3" apply false
```

Version 8.7.3 kompatibel dengan Gradle 8.9 yang sudah terinstall.

## Langkah Selanjutnya

### 1. Download Gradle Baru (Otomatis)
Saat build berikutnya, Gradle akan otomatis download versi 8.13:
```bash
flutter clean
flutter pub get
flutter run
```

Atau force download sekarang:
```bash
cd android
gradlew wrapper --gradle-version 8.13
cd ..
```

### 2. Atau Gunakan Versi yang Sudah Ada
Jika tidak ingin download Gradle baru, Android Gradle Plugin sudah di-downgrade ke 8.7.3 yang kompatibel dengan Gradle 8.9.

Coba build lagi:
```bash
flutter clean
flutter pub get
flutter run
```

## Verifikasi Versi

Cek versi Gradle yang terinstall:
```bash
cd android
gradlew --version
cd ..
```

## Troubleshooting

### Error: "Gradle version masih 8.9"
**Solusi:**
1. Hapus Gradle cache:
   ```bash
   rmdir /s /q "%USERPROFILE%\.gradle\wrapper\dists\gradle-8.9-*"
   ```
2. Build lagi - Gradle akan download versi baru

### Error: "Failed to download Gradle"
**Solusi:**
1. Cek koneksi internet
2. Atau download manual dari: https://gradle.org/releases/
3. Extract ke: `%USERPROFILE%\.gradle\wrapper\dists\gradle-8.13-all\`

### Ingin Upgrade ke Versi Terbaru
Jika ingin menggunakan Android Gradle Plugin terbaru:
1. Update Gradle wrapper ke 8.13 atau lebih baru
2. Update Android Gradle Plugin ke 8.11.1 atau lebih baru
3. Pastikan kompatibilitas: https://developer.android.com/studio/releases/gradle-plugin

## Catatan Penting

- **Gradle 8.13** diperlukan untuk Android Gradle Plugin 8.11.1+
- **Gradle 8.9** kompatibel dengan Android Gradle Plugin 8.7.3
- **Downgrade plugin** lebih cepat daripada upgrade Gradle (tidak perlu download)
- **Build pertama setelah update** akan lebih lambat karena download Gradle baru

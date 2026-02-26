# Cara Memperbaiki Error "Unable to load zip library: zip.dll"

## Masalah
Error muncul saat build Flutter:
```
Error occurred during initialization of VM
Unable to load zip library: C:\Program Files\Android\Android Studio\jbr\bin\zip.dll
Gradle task assembleDebug failed with exit code 1
```

Ini terjadi karena Android Studio's JBR (JetBrains Runtime) mengalami masalah dengan file `zip.dll`.

## Solusi

### Solusi 1: Update Android Studio (Paling Direkomendasikan)
1. Buka **Android Studio**
2. Klik **Help** → **Check for Updates**
3. Update ke versi terbaru
4. Restart komputer
5. Coba build lagi: `flutter clean && flutter pub get && flutter run`

### Solusi 2: Download JDK Standalone dan Set di Gradle
1. **Download JDK 17** dari:
   - Oracle: https://www.oracle.com/java/technologies/downloads/#java17
   - Atau OpenJDK: https://adoptium.net/temurin/releases/?version=17
   
2. **Install JDK** ke folder seperti: `C:\Program Files\Java\jdk-17`

3. **Edit file `android/gradle.properties`**:
   ```properties
   org.gradle.java.home=C:\\Program Files\\Java\\jdk-17
   ```
   (Ganti path sesuai lokasi instalasi JDK Anda)

4. **Stop Gradle daemon**:
   ```bash
   cd android
   gradlew --stop
   ```

5. **Coba build lagi**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

### Solusi 3: Repair Android Studio Installation
1. Buka **Settings** → **Apps** → **Android Studio**
2. Klik **Modify** atau **Repair**
3. Pilih **Repair** dan tunggu proses selesai
4. Restart komputer
5. Coba build lagi

### Solusi 4: Gunakan Flutter's Bundled JDK (Jika Ada)
Jika Flutter sudah include JDK, coba set path ke Flutter's JDK:

1. Cek apakah ada JDK di Flutter SDK:
   - Lokasi biasanya: `C:\Users\<username>\AppData\Local\Android\Sdk\jbr`
   - Atau: `C:\src\flutter\bin\cache\artifacts\gradle_wrapper\jdk`

2. Jika ada, edit `android/gradle.properties`:
   ```properties
   org.gradle.java.home=C:\\Users\\syafi\\AppData\\Local\\Android\\Sdk\\jbr
   ```
   (Ganti path sesuai lokasi JDK Flutter Anda)

3. Stop Gradle daemon dan build lagi

### Solusi 5: Reinstall Android Studio (Last Resort)
Jika semua solusi di atas tidak berhasil:

1. **Backup project** Anda
2. **Uninstall Android Studio** dari Settings → Apps
3. **Hapus folder Android Studio**:
   - `C:\Users\<username>\AppData\Local\Android\Sdk` (backup dulu jika perlu)
   - `C:\Users\<username>\.android`
   - `C:\Users\<username>\.gradle` (opsional, bisa dihapus untuk fresh start)

4. **Download dan install Android Studio** versi terbaru dari:
   https://developer.android.com/studio

5. **Setup Android SDK** melalui Android Studio
6. **Restore project** dan coba build lagi

## Verifikasi Setelah Perbaikan
Setelah menerapkan salah satu solusi di atas, verifikasi dengan:

```bash
flutter doctor -v
```

Pastikan tidak ada error terkait Java/JDK.

## Catatan
- Solusi 1 (Update Android Studio) biasanya paling efektif
- Solusi 2 (JDK Standalone) memberikan kontrol lebih besar
- Setelah memperbaiki, pastikan `android/gradle.properties` sudah dikonfigurasi dengan benar

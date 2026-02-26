# Cara Edit android/gradle.properties

## Penjelasan
File `android/gradle.properties` adalah file konfigurasi untuk Gradle (build tool Android). File ini menentukan pengaturan seperti memori yang digunakan dan lokasi JDK (Java Development Kit).

## Langkah-langkah Edit File

### Metode 1: Edit di Cursor/VS Code (Paling Mudah)
1. **Buka file** `android/gradle.properties` di Cursor/VS Code
2. **Cari baris** yang ada tanda `#` di depannya:
   ```properties
   # org.gradle.java.home=C:\\Program Files\\Java\\jdk-17
   ```
3. **Hapus tanda `#`** di depan baris tersebut
4. **Sesuaikan path** sesuai lokasi JDK di komputer Anda

### Metode 2: Edit dengan Notepad
1. **Buka File Explorer** (Windows Explorer)
2. **Navigasi ke folder project**: `C:\Users\syafi\OneDrive\Dokumen\Traka\traka\android`
3. **Klik kanan** pada file `gradle.properties`
4. **Pilih "Open with"** → **Notepad** (atau text editor lain)
5. **Edit file** sesuai kebutuhan
6. **Save** (Ctrl+S)

## Cara Menentukan Path JDK yang Benar

### Opsi A: Jika Sudah Install JDK Standalone
1. **Cek lokasi JDK** di komputer Anda:
   - Biasanya di: `C:\Program Files\Java\jdk-17` atau `C:\Program Files\Java\jdk-21`
   - Atau cek di folder lain jika Anda install di tempat lain

2. **Copy path lengkap** folder JDK tersebut

3. **Edit baris** di `gradle.properties`:
   ```properties
   org.gradle.java.home=C:\\Program Files\\Java\\jdk-17
   ```
   **PENTING**: 
   - Gunakan **backslash ganda** (`\\`) untuk Windows path
   - Ganti path sesuai lokasi JDK Anda

### Opsi B: Gunakan Android Studio JBR (Jika Masih Ada)
Jika Android Studio masih terinstall dengan baik, bisa gunakan JBR-nya:

1. **Cek lokasi Android Studio JBR**:
   - Biasanya: `C:\Program Files\Android\Android Studio\jbr`
   - Atau: `C:\Users\<username>\AppData\Local\Android\Sdk\jbr`

2. **Edit baris** di `gradle.properties`:
   ```properties
   org.gradle.java.home=C:\\Program Files\\Android\\Android Studio\\jbr
   ```

### Opsi C: Download JDK Baru (Jika Belum Ada)
Jika belum ada JDK di komputer:

1. **Download JDK 17** dari:
   - **Adoptium (Temurin)**: https://adoptium.net/temurin/releases/?version=17
   - Pilih: **Windows x64**, format **.msi**

2. **Install JDK** (biarkan default path: `C:\Program Files\Eclipse Adoptium\jdk-17.x.x-hotspot`)

3. **Edit baris** di `gradle.properties`:
   ```properties
   org.gradle.java.home=C:\\Program Files\\Eclipse Adoptium\\jdk-17.0.13.11-hotspot
   ```
   (Sesuaikan dengan versi yang terinstall)

## Contoh File gradle.properties Setelah Edit

**Sebelum edit** (baris di-comment dengan `#`):
```properties
org.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC -Dfile.encoding=UTF-8
android.useAndroidX=true
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configureondemand=true

# Uncomment and set path to JDK if Android Studio JBR has issues
# org.gradle.java.home=C:\\Program Files\\Java\\jdk-17
```

**Setelah edit** (hapus `#` dan sesuaikan path):
```properties
org.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC -Dfile.encoding=UTF-8
android.useAndroidX=true
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configureondemand=true

# Path ke JDK (uncomment dan sesuaikan path)
org.gradle.java.home=C:\\Program Files\\Java\\jdk-17
```

## Tips
- **Backslash ganda (`\\`)** wajib untuk Windows path di file properties
- **Jangan ada spasi** di awal atau akhir path
- **Pastikan folder JDK benar-benar ada** sebelum menambahkan path
- **Setelah edit**, stop Gradle daemon: `cd android && gradlew --stop`
- **Lalu coba build lagi**: `flutter clean && flutter pub get && flutter run`

## Verifikasi Path JDK Benar
Untuk memastikan path benar, cek apakah folder tersebut ada:
- Buka File Explorer
- Copy-paste path ke address bar
- Jika folder terbuka dan ada file `bin\java.exe` di dalamnya, path sudah benar

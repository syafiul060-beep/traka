# Setup Signing untuk Build Release

## Langkah 1: Buat Keystore

`keytool` adalah bagian dari JDK. Jika muncul error "keytool is not recognized", gunakan **full path**:

**Jika pakai Android Studio** (paling umum):
```powershell
cd D:\Traka\traka\android
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Jika JDK terinstall di lokasi lain**, cari keytool:
```powershell
Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "keytool.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
```
Lalu ganti path di atas dengan hasil pencarian.

Saat diminta, isi:
- **Keystore password:** Buat password (catat!).
- **Key password:** Bisa sama dengan keystore password (tekan Enter).
- **Nama, organisasi, dll:** Isi sesuai (bisa singkat, mis. Traka).

## Langkah 2: Buat key.properties

1. Salin file contoh:
   ```
   copy D:\Traka\traka\android\key.properties.example D:\Traka\traka\android\key.properties
   ```

2. Buka `android/key.properties` dan ganti nilai:
   ```
   storePassword=password_keystore_anda
   keyPassword=password_key_anda
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
   Ganti `password_keystore_anda` dan `password_key_anda` dengan password yang Anda buat di Langkah 1.

## Langkah 3: Build

```cmd
cd D:\Traka\traka
flutter build appbundle
```

File hasil: `build/app/outputs/bundle/release/app-release.aab`

---

**Penting:** Simpan `upload-keystore.jks` dan password di tempat aman. Jika hilang, Anda tidak bisa update aplikasi di Play Store.

# Optimasi Performa untuk RAM 4GB

Dokumen ini menjelaskan optimasi yang telah diterapkan untuk membuat aplikasi Traka lebih responsif di perangkat dengan RAM 4GB.

## Optimasi yang Telah Diterapkan

### 1. **Image Caching dengan `cached_network_image`**
- **Sebelum**: Menggunakan `NetworkImage` langsung tanpa cache
- **Sesudah**: Menggunakan `CachedNetworkImageProvider` untuk caching gambar
- **Dampak**: Mengurangi penggunaan RAM karena gambar di-cache di disk, tidak di memory
- **File yang diubah**:
  - `cari_travel_screen.dart`
  - `data_order_driver_screen.dart`
  - `profile_driver_screen.dart`
  - `profile_penumpang_screen.dart`

### 2. **Optimasi ListView dengan `cacheExtent`**
- **Sebelum**: ListView cache semua item di luar viewport
- **Sesudah**: Membatasi cache hanya 100-200px di luar viewport
- **Dampak**: Mengurangi penggunaan RAM untuk list yang panjang
- **File yang diubah**:
  - `penumpang_screen.dart` (autocomplete: 100px)
  - `cari_travel_screen.dart` (driver list: 200px)
  - `data_order_driver_screen.dart` (orders: 200px)
  - `data_order_screen.dart` (orders: 200px)
  - `driver_jadwal_rute_screen.dart` (jadwal sama: 100px)

### 3. **Pengurangan Frequency Update Lokasi**
- **Sebelum**: Update lokasi setiap 10 detik
- **Sesudah**: Update lokasi setiap 15 detik
- **Dampak**: Mengurangi beban CPU dan RAM dari geocoding yang terlalu sering
- **File yang diubah**:
  - `penumpang_screen.dart`
  - `driver_screen.dart`

### 4. **Optimasi Threshold Update Camera Map**
- **Sebelum**: Update camera jika perpindahan > 10 meter
- **Sesudah**: Update camera jika perpindahan > 20 meter (penumpang) atau > 10 meter (driver saat bergerak)
- **Dampak**: Mengurangi update kamera yang terlalu sering, menghemat RAM dan baterai
- **File yang diubah**:
  - `penumpang_screen.dart`
  - `driver_screen.dart`

### 5. **Pengurangan Jumlah Autocomplete Results**
- **Sebelum**: Maksimal 8 hasil autocomplete
- **Sesudah**: Maksimal 5 hasil autocomplete
- **Dampak**: Mengurangi penggunaan RAM dan waktu loading
- **File yang diubah**:
  - `penumpang_screen.dart`

### 6. **Peningkatan Debounce Autocomplete**
- **Sebelum**: Debounce 500ms
- **Sesudah**: Debounce 800ms
- **Dampak**: Mengurangi beban CPU dari geocoding yang terlalu sering saat user mengetik
- **File yang diubah**:
  - `penumpang_screen.dart`

### 7. **Pengurangan Ukuran Icon Mobil**
- **Sebelum**: Icon mobil 60px
- **Sesudah**: Icon mobil 50px
- **Dampak**: Mengurangi penggunaan RAM untuk rendering icon
- **File yang diubah**:
  - `driver_screen.dart`

## Rekomendasi Tambahan (Opsional)

### 1. **Lazy Loading untuk List Panjang**
Jika ada list yang sangat panjang (>100 item), pertimbangkan menggunakan pagination atau virtual scrolling.

### 2. **Image Compression**
Untuk foto profil yang di-upload, pertimbangkan kompresi gambar sebelum upload ke Firebase Storage.

### 3. **Dispose Resources**
Pastikan semua controller, timer, dan subscription di-dispose dengan benar di `dispose()` method.

### 4. **Google Maps Optimization**
- Gunakan `liteMode: true` untuk map yang tidak interaktif
- Batasi jumlah marker yang ditampilkan sekaligus
- Gunakan clustering untuk marker yang berdekatan

### 5. **Memory Profiling**
Gunakan Flutter DevTools untuk memonitor penggunaan memory dan mengidentifikasi memory leaks.

## Cara Menggunakan

1. **Install dependencies baru**:
   ```bash
   flutter pub get
   ```

2. **Build aplikasi**:
   ```bash
   flutter build apk --release
   ```

3. **Test di perangkat dengan RAM 4GB**:
   - Monitor penggunaan RAM dengan Android Studio Profiler
   - Test navigasi antar halaman
   - Test scrolling di list panjang
   - Test loading gambar

## Hasil yang Diharapkan

- Penggunaan RAM berkurang 20-30%
- Aplikasi lebih responsif saat scrolling
- Loading gambar lebih cepat (karena cache)
- Baterai lebih awet (karena update lokasi lebih jarang)
- Aplikasi tidak lag saat navigasi antar halaman

## Catatan

Optimasi ini dibuat khusus untuk perangkat dengan RAM 4GB. Jika aplikasi masih lambat, pertimbangkan:
- Mengurangi jumlah data yang di-load sekaligus
- Menggunakan pagination untuk list panjang
- Menambahkan loading indicator yang lebih jelas
- Mengoptimalkan query Firestore (gunakan limit dan index)

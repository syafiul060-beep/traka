# Validasi Foto Wajah – Pendaftaran

Dokumen ini menjelaskan validasi foto wajah yang diterapkan saat pendaftaran (Penumpang & Driver).

---

## 1. Ringkasan Validasi

| Tahap | Validasi | Reject jika |
|-------|----------|-------------|
| **1. Sebelum ML** | Kamera & Input | Resolusi < 480p, cahaya gelap/terang, blur |
| **2. Face Detection** | Jumlah & ukuran wajah | Lebih dari 1 wajah, wajah terlalu kecil |
| **3. Bounding Box** | Proporsi wajah | Wajah terpotong, aspect ratio abnormal |
| **4. Landmark** | Mata, hidung, mulut | Kurang dari 3 landmark terdeteksi |
| **5. Pose** | Yaw, pitch, roll | Wajah tidak menghadap kamera |
| **6. Occlusion** | Mata tertutup | Mata tertutup / kacamata gelap |
| **7. Rate Limit** | Percobaan per jam | Lebih dari 10 percobaan per jam |

---

## 2. Validasi Kamera & Input (Sebelum ML)

- **Resolusi minimal**: 480×480 piksel (480p)
- **Cahaya cukup**: Rata-rata brightness 40–220 (terlalu gelap/terang → reject)
- **Tidak blur**: Laplacian variance ≥ 100 (blur → reject)
- **Wajah menghadap kamera**: Dicek via pose (yaw/pitch/roll)

---

## 3. Validasi Face Detection

- **Hanya 1 wajah**: Lebih dari 1 wajah → reject
- **Ukuran wajah**: Minimal 10% dari lebar/tinggi gambar
- **Bounding box proporsional**: Aspect ratio wajah 0.5–2.5

---

## 4. Validasi Landmark

Landmark yang dicek: mata kiri, mata kanan, hidung, mulut bawah. Minimal 3 dari 4 landmark harus terdeteksi.

---

## 5. Validasi Pose (Yaw / Pitch / Roll)

- Batas sudut: ±25 derajat
- Wajah harus menghadap kamera

---

## 6. Validasi Occlusion

- **Probabilitas mata terbuka**: Minimal 0.2
- Mata tertutup atau kacamata gelap → reject

---

## 7. Validasi Liveness & Anti-Fraud

**Passive Liveness** (sudah diterapkan):

- Brightness / Sharpness → via validasi blur & cahaya
- Pose → validasi yaw/pitch/roll
- Occlusion → validasi mata terbuka

**Active Liveness – Kedip** (sudah diterapkan):

- Layar `ActiveLivenessScreen` menampilkan preview kamera depan
- Instruksi jelas: "Silakan kedip satu kali"
- Frame sampling **250ms** (4 FPS) agar ringan di device
- Deteksi: mata tertutup (prob < 0.3) → mata terbuka (prob > 0.5) = kedip terdeteksi
- Setelah kedip terdeteksi, foto di-capture dan dikembalikan ke register

---

## 8. Rate Limit

- Maksimal **10 percobaan** upload foto wajah per jam per device
- Reset otomatis setelah 1 jam
- Disimpan di SharedPreferences (`face_photo_attempts`, `face_photo_attempt_reset`)

---

## 9. Validasi Device & Session

- **Device ID**: Sudah diambil di `DeviceService.getDeviceId()`
- **OS version, App version**: Tersedia di `SessionValidationService.getDeviceInfo()`
- **Root / Jailbreak**: Belum diimplementasi (bisa ditambah pakai `flutter_jailbreak_detection`)

---

## 10. File Terkait

| File | Fungsi |
|------|--------|
| `lib/services/face_validation_service.dart` | Validasi resolusi, brightness, blur, wajah, pose, occlusion |
| `lib/services/session_validation_service.dart` | Rate limit, info device |
| `lib/screens/register_screen.dart` | Memanggil validasi saat ambil foto |

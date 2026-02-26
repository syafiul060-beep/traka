# Face Embedding (Vektor) – Setup

Verifikasi berbasis **face embedding (vektor 128D)** dengan `tensorflow_face_verification`.

## Implementasi

- **Paket**: `tensorflow_face_verification: ^0.1.2`
- **Model**: `packages/face_verification/assets/models/facenet.tflite` (atau `assets/models/facenet.tflite` jika tersedia)
- **Layanan**: `lib/services/face_embedding_service.dart`

## Alur

1. **Registrasi**: Ekstrak embedding dari foto → simpan `faceEmbedding` di Firestore
2. **Cek duplikat**: Prioritas embedding (tanpa download gambar), fallback image-based
3. **Login dari device baru**: Pool update juga memperbarui `faceEmbedding` jika berhasil

## Firestore

```
users/{uid}:
  faceEmbedding: [0.123, -0.456, ...]  // array 128 angka
  faceVerificationUrl: "https://..."
  ...
```

## Catatan

- Model face_verification dan tensorflow_face_verification bisa berbeda format (512D vs 128D); uji di device fisik
- Jika embedding gagal, fallback ke image-based tetap berjalan

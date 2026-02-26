# Struktur Data Vehicle Brands di Firestore

## Collection: `vehicle_brands`

Collection ini digunakan untuk menyimpan data merek dan type mobil yang bisa diupdate oleh admin tanpa perlu update aplikasi.

### Struktur Document

Setiap document merepresentasikan satu merek mobil.

**Document ID**: Nama merek (contoh: `Toyota`, `Honda`, `Tesla`, dll)

**Fields**:
- `name` (string): Nama merek mobil (contoh: "Toyota")
- `types` (array of string): Daftar type mobil untuk merek tersebut
- `capacities` (map): Mapping jumlah penumpang untuk setiap type
  - `list` (array of int): Array jumlah penumpang sesuai urutan types

### Contoh Document

**Document ID**: `Toyota`

```json
{
  "name": "Toyota",
  "types": [
    "Avanza",
    "Innova",
    "Fortuner",
    "Rush",
    "Alphard",
    "Camry",
    "Corolla",
    "Yaris",
    "Vios",
    "Sienta",
    "Hiace"
  ],
  "capacities": {
    "list": [7, 7, 7, 7, 7, 5, 5, 5, 5, 7, 15]
  }
}
```

**Document ID**: `Tesla` (Contoh mobil listrik baru)

```json
{
  "name": "Tesla",
  "types": [
    "Model 3",
    "Model Y",
    "Model S",
    "Model X"
  ],
  "capacities": {
    "list": [5, 7, 5, 7]
  }
}
```

## Cara Menambahkan Merek Baru

1. Buka Firebase Console → Firestore Database
2. Klik collection `vehicle_brands`
3. Klik "Add document"
4. **Document ID**: Masukkan nama merek (contoh: `Tesla`)
5. **Fields**:
   - `name` (string): Nama merek (contoh: "Tesla")
   - `types` (array): Tambahkan type mobil (contoh: ["Model 3", "Model Y"])
   - `capacities` (map):
     - `list` (array): Tambahkan jumlah penumpang sesuai urutan types (contoh: [5, 7])

## Cara Menambahkan Type Baru ke Merek yang Sudah Ada

1. Buka Firebase Console → Firestore Database
2. Klik collection `vehicle_brands`
3. Klik document merek yang ingin ditambahkan type-nya
4. Edit field `types`: Tambahkan type baru ke array
5. Edit field `capacities.list`: Tambahkan jumlah penumpang sesuai urutan type baru

## Fallback ke Data Default

Jika collection `vehicle_brands` kosong atau terjadi error saat membaca dari Firestore, aplikasi akan menggunakan data default dari `VehicleModel` yang ada di kode.

## Rules Firestore

Rules untuk collection `vehicle_brands`:
- **Read**: Semua user yang login boleh baca
- **Write**: Untuk sementara semua user yang login boleh tulis (nanti bisa dibatasi ke admin saja)

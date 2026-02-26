# Tarif Per KM (Rupiah)

Tarif perjalanan dihitung dari **titik jemput** (saat driver scan barcode penumpang) sampai **titik turun** (saat penumpang scan barcode driver di tujuan).

> **Langkah terperinci (program manual / referensi):** lihat **[LANGKAH_TARIF_PER_KM_DAN_SCAN_TERPERINCI.md](LANGKAH_TARIF_PER_KM_DAN_SCAN_TERPERINCI.md)**.

- **Rumus:** `Tarif (Rp) = Jarak (km) × Tarif per km (Rp)`  
- **Default:** 50 Rupiah per 1 km.

## Mengubah tarif per km (Web Admin)

Nilai tarif per km bisa diubah lewat Firestore:

1. Buka Firebase Console → Firestore.
2. Buat/ubah dokumen: **Collection** `app_config` → **Document** `settings`.
3. Field: `tarifPerKm` (number). Contoh: `50` untuk 50 Rp/km, `100` untuk 100 Rp/km.
4. Jika dokumen atau field tidak ada, app memakai **default 50** Rp/km.

Contoh isi `app_config/settings`:

```json
{
  "tarifPerKm": 50
}
```

Setelah diubah, perhitungan tarif untuk order baru (saat penumpang scan barcode driver) akan memakai nilai terbaru.

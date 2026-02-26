# Rencana: Rute Selesai & Riwayat per Rute (Driver)

## Yang diminta
- Data pemesanan **tidak dihapus otomatis**; yang dihapus hanya **list chat** (isi messages) — sudah di Cloud Function `deleteCompletedOrderChats`.
- Saat driver klik **"Pekerjaan selesai" / "Rute driver selesai"**: data pemesanan (yang selesai) **pindah ke Riwayat**, dikategorikan per rute.
- Di **Riwayat**: driver melihat daftar **rute** (yang sudah diselesaikan). Saat driver klik satu rute → tampil **penumpang yang sudah dijemput dan diantar** sampai lokasi (order dengan status completed untuk rute itu).

## Yang sudah dilakukan
- Menu **Pemesanan Selesai**: tombol Chat dan Lokasi dihapus; hanya tampil info order + **Jarak: X km** (dari titik jemput sampai titik turun).
- **Jarak**: saat penumpang scan barcode driver, lokasi turun (drop) disimpan; jarak dihitung dari `passengerLat/Lng` (jemput) ke drop; field `tripDistanceKm`, `dropLat`, `dropLng` di order.
- **Beranda driver**: **Jumlah Penumpang** dan **Jumlah Barang** dari order status agreed + picked_up (travel = penumpang, kirim_barang = barang). Angka berkurang otomatis saat order pindah ke Pemesanan Selesai (completed).

## Yang sudah diprogram
- **"Rute selesai"**: Saat driver tap **"Berhenti Kerja"** (toggle merah), sesi rute disimpan ke collection `route_sessions` (driverUid, routeJourneyNumber, routeOriginText, routeDestText, endedAt, dll.) lalu status driver di-set tidak_aktif.
- **Riwayat** tab (Data Order): daftar rute dari `route_sessions` (urut endedAt terbaru); tap satu rute → halaman **Detail Rute** yang menampilkan daftar order **completed** untuk rute itu (penumpang/barang yang sudah dijemput dan diantar, dengan no. pesanan, nama, jarak).
- Index Firestore: `route_sessions` (driverUid ASC, endedAt DESC).

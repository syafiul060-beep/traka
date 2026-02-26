import 'package:cloud_firestore/cloud_firestore.dart';

/// Model pesanan (order) penumpang–driver.
/// Nomor pesanan dibuat otomatis ketika driver dan penumpang sama-sama klik kesepakatan.
class OrderModel {
  final String id;
  final String? orderNumber;
  final String passengerUid;
  final String driverUid;
  final String routeJourneyNumber;
  final String passengerName;
  final String? passengerPhotoUrl;
  final String originText;
  final String destText;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final double? passengerLat;
  final double? passengerLng;
  final String? passengerLocationText;
  final String status;
  final bool driverAgreed;
  final bool passengerAgreed;

  /// Apakah driver sudah klik batalkan.
  final bool driverCancelled;

  /// Apakah penumpang sudah klik batalkan.
  final bool passengerCancelled;

  /// Apakah admin membatalkan pesanan.
  final bool adminCancelled;

  /// Waktu admin membatalkan.
  final DateTime? adminCancelledAt;

  /// Alasan admin membatalkan (untuk audit).
  final String? adminCancelReason;

  /// travel = penumpang sendiri/kerabat; kirim_barang = kirim barang (ada penerima).
  final String orderType;

  /// UID penerima barang (untuk kirim_barang). Bisa sama dengan passengerUid atau beda.
  final String? receiverUid;

  /// Nama dan foto penerima (untuk kirim_barang, tampilan).
  final String? receiverName;
  final String? receiverPhotoUrl;

  /// Waktu penerima setuju jadi penerima (order lalu ke driver).
  final DateTime? receiverAgreedAt;

  /// Lokasi penerima (untuk antar barang).
  final double? receiverLat;
  final double? receiverLng;
  final String? receiverLocationText;

  /// Waktu penerima scan barcode driver (barang diterima).
  final DateTime? receiverScannedAt;

  /// Jumlah kerabat (untuk travel dengan kerabat). Null = pesan sendiri.
  final int? jumlahKerabat;

  /// Harga yang diusulkan driver (Rupiah). Diset saat driver klik Kesepakatan dan kirim.
  final double? agreedPrice;

  /// Waktu driver mengirim harga kesepakatan.
  final DateTime? agreedPriceAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Waktu pesanan selesai (status completed). Untuk auto-hapus chat 24 jam kemudian.
  final DateTime? completedAt;

  /// Waktu pesan terakhir (di-set Cloud Function saat ada pesan baru).
  final DateTime? lastMessageAt;

  /// UID pengirim pesan terakhir (untuk badge unread driver).
  final String? lastMessageSenderUid;

  /// Teks pesan terakhir (potongan, untuk notifikasi).
  final String? lastMessageText;

  /// Waktu terakhir driver membuka chat untuk order ini (untuk hitung unread).
  final DateTime? driverLastReadAt;

  /// Chat disembunyikan dari list Pesan oleh penumpang (riwayat tetap tampil).
  final bool chatHiddenByPassenger;

  /// Chat disembunyikan dari list Pesan oleh driver (riwayat tetap tampil).
  final bool chatHiddenByDriver;

  /// Waktu terakhir penumpang membuka chat (untuk hitung unread). Di-set saat sembunyikan.
  final DateTime? passengerLastReadAt;

  /// Payload barcode penumpang (untuk di-scan driver). Di-set saat penumpang setuju.
  final String? passengerBarcodePayload;

  /// Payload barcode driver (untuk di-scan penumpang). Di-set setelah driver scan barcode penumpang.
  final String? driverBarcodePayload;

  /// Waktu driver berhasil scan barcode penumpang (order pindah ke "penumpang").
  final DateTime? driverScannedAt;

  /// Titik jemput penumpang (lokasi driver saat scan barcode penumpang). Untuk hitung jarak perjalanan.
  final double? pickupLat;
  final double? pickupLng;

  /// Waktu penumpang berhasil scan barcode driver (perjalanan selesai).
  final DateTime? passengerScannedAt;

  /// Titik turun penumpang (saat penumpang scan barcode driver). Untuk hitung jarak.
  final double? dropLat;
  final double? dropLng;

  /// Jarak perjalanan (km): dari titik jemput sampai titik turun.
  final double? tripDistanceKm;

  /// Tarif perjalanan (Rupiah): jarak × tarif per km (70–85 Rp/km, bisa diubah di admin).
  final double? tripFareRupiah;

  /// ID jadwal driver (pesanan terjadwal dari Pesan nanti). Format: driverUid_yMd_departureMs.
  final String? scheduleId;

  /// Tanggal jadwal (y-m-d) untuk pesanan terjadwal.
  final String? scheduledDate;

  /// Waktu driver sampai di titik penjemputan (dalam radius 300 m). Untuk notifikasi penumpang dan auto-confirm 5 menit.
  final DateTime? driverArrivedAtPickupAt;

  /// Waktu penumpang bayar Lacak Driver (Rp 3000) untuk order ini.
  final DateTime? passengerTrackDriverPaidAt;

  /// Waktu pengirim bayar Lacak Barang (kirim barang).
  final DateTime? passengerLacakBarangPaidAt;

  /// Waktu penerima bayar Lacak Barang (kirim barang).
  final DateTime? receiverLacakBarangPaidAt;

  /// Konfirmasi penjemputan tanpa scan barcode (driver klik konfirmasi otomatis).
  final bool autoConfirmPickup;

  /// Konfirmasi selesai tanpa scan barcode (penumpang klik konfirmasi otomatis).
  final bool autoConfirmComplete;

  /// Biaya pelanggaran penumpang (Rp) karena tidak scan barcode saat sampai tujuan.
  final double? passengerViolationFee;

  /// Biaya pelanggaran driver (Rp) karena tidak scan barcode saat jemput penumpang.
  final double? driverViolationFee;

  /// Rating penumpang untuk driver (1-5) setelah perjalanan selesai.
  final int? passengerRating;

  /// Review/ulasan penumpang untuk driver.
  final String? passengerReview;

  /// Waktu penumpang memberi rating.
  final DateTime? passengerRatedAt;

  const OrderModel({
    required this.id,
    this.orderNumber,
    required this.passengerUid,
    required this.driverUid,
    required this.routeJourneyNumber,
    required this.passengerName,
    this.passengerPhotoUrl,
    required this.originText,
    required this.destText,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.passengerLat,
    this.passengerLng,
    this.passengerLocationText,
    required this.status,
    required this.driverAgreed,
    required this.passengerAgreed,
    this.driverCancelled = false,
    this.passengerCancelled = false,
    this.adminCancelled = false,
    this.adminCancelledAt,
    this.adminCancelReason,
    this.orderType = 'travel',
    this.receiverUid,
    this.receiverName,
    this.receiverPhotoUrl,
    this.receiverAgreedAt,
    this.receiverLat,
    this.receiverLng,
    this.receiverLocationText,
    this.receiverScannedAt,
    this.jumlahKerabat,
    this.agreedPrice,
    this.agreedPriceAt,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.lastMessageAt,
    this.lastMessageSenderUid,
    this.lastMessageText,
    this.driverLastReadAt,
    this.chatHiddenByPassenger = false,
    this.chatHiddenByDriver = false,
    this.passengerLastReadAt,
    this.passengerBarcodePayload,
    this.driverBarcodePayload,
    this.driverScannedAt,
    this.pickupLat,
    this.pickupLng,
    this.passengerScannedAt,
    this.dropLat,
    this.dropLng,
    this.tripDistanceKm,
    this.tripFareRupiah,
    this.scheduleId,
    this.scheduledDate,
    this.driverArrivedAtPickupAt,
    this.passengerTrackDriverPaidAt,
    this.passengerLacakBarangPaidAt,
    this.receiverLacakBarangPaidAt,
    this.autoConfirmPickup = false,
    this.autoConfirmComplete = false,
    this.passengerViolationFee,
    this.driverViolationFee,
    this.passengerRating,
    this.passengerReview,
    this.passengerRatedAt,
  });

  factory OrderModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return OrderModel(
      id: doc.id,
      orderNumber: d['orderNumber'] as String?,
      passengerUid: (d['passengerUid'] as String?) ?? '',
      driverUid: (d['driverUid'] as String?) ?? '',
      routeJourneyNumber: (d['routeJourneyNumber'] as String?) ?? '',
      passengerName: (d['passengerName'] as String?) ?? '',
      passengerPhotoUrl: d['passengerPhotoUrl'] as String?,
      originText: (d['originText'] as String?) ?? '',
      destText: (d['destText'] as String?) ?? '',
      originLat: (d['originLat'] as num?)?.toDouble(),
      originLng: (d['originLng'] as num?)?.toDouble(),
      destLat: (d['destLat'] as num?)?.toDouble(),
      destLng: (d['destLng'] as num?)?.toDouble(),
      passengerLat: (d['passengerLat'] as num?)?.toDouble(),
      passengerLng: (d['passengerLng'] as num?)?.toDouble(),
      passengerLocationText: d['passengerLocationText'] as String?,
      status: (d['status'] as String?) ?? 'pending_agreement',
      driverAgreed: (d['driverAgreed'] as bool?) ?? false,
      passengerAgreed: (d['passengerAgreed'] as bool?) ?? false,
      driverCancelled: (d['driverCancelled'] as bool?) ?? false,
      passengerCancelled: (d['passengerCancelled'] as bool?) ?? false,
      adminCancelled: (d['adminCancelled'] as bool?) ?? false,
      adminCancelledAt: (d['adminCancelledAt'] as Timestamp?)?.toDate(),
      adminCancelReason: d['adminCancelReason'] as String?,
      orderType: (d['orderType'] as String?) ?? 'travel',
      receiverUid: d['receiverUid'] as String?,
      receiverName: d['receiverName'] as String?,
      receiverPhotoUrl: d['receiverPhotoUrl'] as String?,
      receiverAgreedAt: (d['receiverAgreedAt'] as Timestamp?)?.toDate(),
      receiverLat: (d['receiverLat'] as num?)?.toDouble(),
      receiverLng: (d['receiverLng'] as num?)?.toDouble(),
      receiverLocationText: d['receiverLocationText'] as String?,
      receiverScannedAt: (d['receiverScannedAt'] as Timestamp?)?.toDate(),
      jumlahKerabat: (d['jumlahKerabat'] as num?)?.toInt(),
      agreedPrice: (d['agreedPrice'] as num?)?.toDouble(),
      agreedPriceAt: (d['agreedPriceAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderUid: d['lastMessageSenderUid'] as String?,
      lastMessageText: d['lastMessageText'] as String?,
      driverLastReadAt: (d['driverLastReadAt'] as Timestamp?)?.toDate(),
      chatHiddenByPassenger: (d['chatHiddenByPassenger'] as bool?) ?? false,
      chatHiddenByDriver: (d['chatHiddenByDriver'] as bool?) ?? false,
      passengerLastReadAt: (d['passengerLastReadAt'] as Timestamp?)?.toDate(),
      passengerBarcodePayload: d['passengerBarcodePayload'] as String?,
      driverBarcodePayload: d['driverBarcodePayload'] as String?,
      driverScannedAt: (d['driverScannedAt'] as Timestamp?)?.toDate(),
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      passengerScannedAt: (d['passengerScannedAt'] as Timestamp?)?.toDate(),
      dropLat: (d['dropLat'] as num?)?.toDouble(),
      dropLng: (d['dropLng'] as num?)?.toDouble(),
      tripDistanceKm: (d['tripDistanceKm'] as num?)?.toDouble(),
      tripFareRupiah: (d['tripFareRupiah'] as num?)?.toDouble(),
      scheduleId: d['scheduleId'] as String?,
      scheduledDate: d['scheduledDate'] as String?,
      driverArrivedAtPickupAt: (d['driverArrivedAtPickupAt'] as Timestamp?)?.toDate(),
      passengerTrackDriverPaidAt: (d['passengerTrackDriverPaidAt'] as Timestamp?)?.toDate(),
      passengerLacakBarangPaidAt: (d['passengerLacakBarangPaidAt'] as Timestamp?)?.toDate(),
      receiverLacakBarangPaidAt: (d['receiverLacakBarangPaidAt'] as Timestamp?)?.toDate(),
      autoConfirmPickup: (d['autoConfirmPickup'] as bool?) ?? false,
      autoConfirmComplete: (d['autoConfirmComplete'] as bool?) ?? false,
      passengerViolationFee: (d['passengerViolationFee'] as num?)?.toDouble(),
      driverViolationFee: (d['driverViolationFee'] as num?)?.toDouble(),
      passengerRating: (d['passengerRating'] as num?)?.toInt(),
      passengerReview: d['passengerReview'] as String?,
      passengerRatedAt: (d['passengerRatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isTravel => orderType == OrderModel.typeTravel;
  bool get isKirimBarang => orderType == OrderModel.typeKirimBarang;

  /// Konstanta jenis pesanan (untuk program/fungsi nanti).
  static const String typeKirimBarang = 'kirim_barang';
  static const String typeTravel = 'travel';

  /// Apakah pesan travel sendiri (1 orang).
  bool get isTravelSendiri =>
      orderType == typeTravel && (jumlahKerabat == null || jumlahKerabat == 0);

  /// Apakah pesan travel dengan kerabat (2+ orang).
  bool get isTravelKerabat =>
      orderType == typeTravel && jumlahKerabat != null && jumlahKerabat! > 0;

  /// Jumlah total penumpang: 1 jika sendiri, 1 + jumlahKerabat jika dengan kerabat.
  int get totalPenumpang {
    if (orderType != typeTravel) return 0;
    if (jumlahKerabat == null || jumlahKerabat! <= 0) return 1;
    return 1 + jumlahKerabat!;
  }

  /// Label untuk tampilan & pesan otomatis di chat (Kirim Barang / Pesan Travel 1 orang / Pesan Travel X orang - dengan kerabat).
  String get orderTypeDisplayLabel {
    if (orderType == typeKirimBarang) return 'Kirim Barang';
    if (orderType != typeTravel) return 'Pesan';
    if (jumlahKerabat == null || jumlahKerabat! <= 0)
      return 'Pesan Travel (1 orang)';
    final total = 1 + jumlahKerabat!;
    return 'Pesan Travel ($total orang - dengan kerabat)';
  }

  /// Buat teks pesan otomatis "Jenis pesanan: ..." untuk dikirim ke chat.
  String get orderTypeAutoMessageText =>
      'Jenis pesanan: $orderTypeDisplayLabel';

  bool get isAgreed => status == 'agreed';
  bool get isPickedUp => status == 'picked_up';
  bool get isCompleted => status == 'completed';
  bool get isPendingAgreement => status == 'pending_agreement';
  /// Kirim barang: menunggu penerima setuju (penerima belum konfirmasi).
  bool get isPendingReceiver => status == 'pending_receiver';
  bool get canDriverAgree => !driverAgreed;
  bool get canPassengerAgree => driverAgreed && !passengerAgreed;
  bool get hasPassengerLocation => passengerLat != null && passengerLng != null;

  /// Apakah sudah ada yang klik batalkan (driver, penumpang, atau admin).
  bool get isCancelled =>
      driverCancelled || passengerCancelled || adminCancelled;

  /// Apakah driver sudah klik batalkan.
  bool get isDriverCancelled => driverCancelled;

  /// Apakah penumpang sudah klik batalkan.
  bool get isPassengerCancelled => passengerCancelled;

  /// Apakah admin membatalkan pesanan.
  bool get isAdminCancelled => adminCancelled;
  bool get hasPassengerBarcode =>
      passengerBarcodePayload != null && passengerBarcodePayload!.isNotEmpty;
  bool get hasDriverBarcode =>
      driverBarcodePayload != null && driverBarcodePayload!.isNotEmpty;
  bool get hasDriverScannedPassenger => driverScannedAt != null;
  bool get hasPassengerScannedDriver => passengerScannedAt != null;

  /// Untuk kirim_barang: apakah penerima sudah scan barcode driver (barang diterima).
  bool get hasReceiverScannedDriver => receiverScannedAt != null;

  /// Pesanan dari "Pesan nanti" (terjadwal), bukan driver aktif.
  bool get isScheduledOrder => scheduleId != null && scheduleId!.isNotEmpty;
}

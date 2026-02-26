import 'package:cloud_firestore/cloud_firestore.dart';

/// Cek kelengkapan data verifikasi user.
/// Penumpang: face + KTP + phone
/// Driver: face + vehicle + SIM + phone
class VerificationService {
  VerificationService._();

  /// Interval verifikasi wajah ulang: 6 bulan.
  static const int faceReverifyMonths = 6;

  /// Apakah user perlu verifikasi wajah ulang (setiap 6 bulan).
  /// Return true jika: punya faceVerificationUrl TAPI (belum pernah ada lastVerifiedAt ATAU sudah lewat 6 bulan).
  static bool needsFaceReverify(Map<String, dynamic> data) {
    final faceUrl = (data['faceVerificationUrl'] as String?)?.trim();
    if (faceUrl == null || faceUrl.isEmpty) return false;

    final lastVerified = data['faceVerificationLastVerifiedAt'];
    if (lastVerified == null) return true;

    DateTime? dt;
    if (lastVerified is DateTime) {
      dt = lastVerified;
    } else if (lastVerified is Timestamp) {
      dt = lastVerified.toDate();
    }
    if (dt == null) return true;

    final now = DateTime.now();
    final diff = now.difference(dt);
    return diff.inDays >= (faceReverifyMonths * 30); // ~6 bulan
  }

  /// Penumpang terverifikasi lengkap: foto wajah + KTP + nomor HP.
  static bool isPenumpangVerified(Map<String, dynamic> data) {
    final face = (data['faceVerificationUrl'] as String?)?.trim();
    final hasFace = face != null && face.isNotEmpty;
    final hasKTP = data['passengerKTPVerifiedAt'] != null ||
        data['passengerKTPNomorHash'] != null;
    final phone = ((data['phoneNumber'] as String?) ?? '').trim();
    return hasFace && hasKTP && phone.isNotEmpty;
  }

  /// Driver terverifikasi lengkap: foto wajah + kendaraan + SIM + nomor HP.
  static bool isDriverVerified(Map<String, dynamic> data) {
    final face = (data['faceVerificationUrl'] as String?)?.trim();
    final hasFace = face != null && face.isNotEmpty;
    final hasVehicle =
        data['vehiclePlat'] != null || data['vehicleUpdatedAt'] != null;
    final hasDriver = data['driverSIMVerifiedAt'] != null ||
        data['driverSIMNomorHash'] != null;
    final phone = ((data['phoneNumber'] as String?) ?? '').trim();
    return hasFace && hasVehicle && hasDriver && phone.isNotEmpty;
  }
}

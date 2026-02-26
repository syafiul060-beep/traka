import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vehicle_model.dart';

/// Service untuk membaca data merek dan type mobil dari Firestore
/// Data bisa diupdate oleh admin tanpa perlu update aplikasi
class VehicleBrandService {
  static final _firestore = FirebaseFirestore.instance;

  /// Mendapatkan daftar merek mobil dari Firestore (dengan fallback ke data default)
  static Future<List<String>> getMerekMobil() async {
    try {
      final snapshot = await _firestore
          .collection('vehicle_brands')
          .orderBy('name')
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Jika ada data di Firestore, gunakan data tersebut
        return snapshot.docs
            .map((doc) => doc.data()['name'] as String)
            .toList();
      }
    } catch (e) {
      // Jika error, gunakan data default
    }

    // Fallback ke data default dari VehicleModel
    return VehicleModel.merekMobilIndonesia;
  }

  /// Mendapatkan daftar type mobil berdasarkan merek dari Firestore
  static Future<List<String>> getTypeByMerek(String merek) async {
    try {
      final snapshot = await _firestore
          .collection('vehicle_brands')
          .where('name', isEqualTo: merek)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final types = doc.data()['types'] as List<dynamic>?;
        if (types != null && types.isNotEmpty) {
          final list = types.map((t) => t.toString()).toList();
          if (!list.contains(VehicleModel.typeMicrobus)) {
            list.add(VehicleModel.typeMicrobus);
          }
          return list;
        }
      }
    } catch (e) {
      // Jika error, gunakan data default
    }

    // Fallback ke data default dari VehicleModel
    return VehicleModel.getTypeByMerek(merek);
  }

  /// Mendapatkan jumlah penumpang berdasarkan merek dan type dari Firestore
  static Future<int?> getJumlahPenumpang(String merek, String type) async {
    try {
      final snapshot = await _firestore
          .collection('vehicle_brands')
          .where('name', isEqualTo: merek)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final types = doc.data()['types'] as List<dynamic>?;
        final capacities = doc.data()['capacities'] as Map<String, dynamic>?;

        if (types != null && capacities != null) {
          // Cari type di dalam types array
          final typeIndex = types.indexWhere((t) => t.toString() == type);
          if (typeIndex >= 0) {
            // Gunakan index untuk mendapatkan capacity
            final capacityList = capacities['list'] as List<dynamic>?;
            if (capacityList != null && typeIndex < capacityList.length) {
              final capacity = capacityList[typeIndex];
              if (capacity is int) {
                return capacity;
              } else if (capacity is String) {
                return int.tryParse(capacity);
              }
            }
          }
          // Microbus (Minibus) mungkin ditambah di app tapi belum di Firestore capacities
          if (type == VehicleModel.typeMicrobus) {
            return 12;
          }
        }
      }
    } catch (e) {
      // Jika error, gunakan data default
    }

    // Fallback ke data default dari VehicleModel
    return VehicleModel.getJumlahPenumpang(merek, type);
  }

  /// Stream untuk mendapatkan daftar merek mobil (real-time updates)
  static Stream<List<String>> streamMerekMobil() {
    return _firestore
        .collection('vehicle_brands')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return VehicleModel.merekMobilIndonesia;
          }
          return snapshot.docs
              .map((doc) => doc.data()['name'] as String)
              .toList();
        });
  }
}

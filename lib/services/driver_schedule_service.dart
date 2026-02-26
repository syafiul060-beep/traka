import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk jadwal keberangkatan driver (driver_schedules).
/// - Menyembunyikan jadwal hari ini ketika driver klik "Mulai Rute ini" (agar tidak tampil ke penumpang).
/// - Menghapus jadwal yang sudah lewat (date < hari ini) secara otomatis.
class DriverScheduleService {
  static final _firestore = FirebaseFirestore.instance;

  /// Tanggal hari ini 00:00:00 (timezone lokal) untuk perbandingan.
  static DateTime get _todayStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Cek apakah tanggal schedule sudah lewat (sebelum hari ini).
  static bool _isPast(DateTime? date) {
    if (date == null) return true;
    final d = DateTime(date.year, date.month, date.day);
    return d.isBefore(_todayStart);
  }

  /// Sembunyikan jadwal yang tanggalnya hari ini. Dipanggil saat driver klik "Mulai Rute ini".
  /// Jadwal yang hidden tidak ditampilkan ke penumpang saat mencari travel.
  static Future<void> markTodaySchedulesHidden(String driverUid) async {
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(driverUid)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final list = data['schedules'] as List<dynamic>?;
      if (list == null || list.isEmpty) return;

      final now = FieldValue.serverTimestamp();
      bool changed = false;
      final updated = <Map<String, dynamic>>[];

      for (final e in list) {
        final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
        final dateStamp = map['date'] as Timestamp?;
        final hiddenAt = map['hiddenAt'];
        if (hiddenAt != null) {
          updated.add(map);
          continue;
        }
        final date = dateStamp?.toDate();
        if (date == null) {
          updated.add(map);
          continue;
        }
        final scheduleDate = DateTime(date.year, date.month, date.day);
        if (scheduleDate == _todayStart) {
          map['hiddenAt'] = now;
          changed = true;
        }
        updated.add(map);
      }

      if (changed) {
        await _firestore.collection('driver_schedules').doc(driverUid).update({
          'schedules': updated,
          'updatedAt': now,
        });
      }
    } catch (_) {}
  }

  /// Hapus jadwal yang tanggalnya sudah lewat (sebelum hari ini). Dipanggil saat load jadwal.
  /// Jadwal kemarin akan terhapus ketika driver buka halaman jadwal besok.
  static Future<List<Map<String, dynamic>>> cleanupPastSchedules(
    String driverUid,
  ) async {
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(driverUid)
          .get();

      if (!doc.exists || doc.data() == null) {
        return [];
      }

      final data = doc.data()!;
      final list = data['schedules'] as List<dynamic>?;
      if (list == null || list.isEmpty) return [];

      final kept = <Map<String, dynamic>>[];
      for (final e in list) {
        final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
        final dateStamp = map['date'] as Timestamp?;
        final date = dateStamp?.toDate();
        if (!_isPast(date)) {
          kept.add(map);
        }
      }

      if (kept.length < list.length) {
        await _firestore.collection('driver_schedules').doc(driverUid).update({
          'schedules': kept,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return kept;
    } catch (_) {
      return [];
    }
  }

  /// Cek apakah jam keberangkatan sudah lewat (untuk jadwal tanggal hari ini).
  static bool _isDepartureTimePassed(Map<String, dynamic> map) {
    final depStamp = map['departureTime'] as Timestamp?;
    if (depStamp == null) return false;
    return depStamp.toDate().isBefore(DateTime.now());
  }

  /// Daftar jadwal yang masih tampil ke penumpang: tanggal >= hari ini, belum hidden,
  /// dan jam keberangkatan belum lewat (tanggal hari ini + jam lewat = disembunyikan).
  static Future<List<Map<String, dynamic>>> getVisibleSchedulesForDriver(
    String driverUid,
  ) async {
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(driverUid)
          .get();

      if (!doc.exists || doc.data() == null) return [];

      final list = doc.data()!['schedules'] as List<dynamic>?;
      if (list == null) return [];

      final result = <Map<String, dynamic>>[];
      for (final e in list) {
        final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
        final dateStamp = map['date'] as Timestamp?;
        if (_isPast(dateStamp?.toDate())) continue;
        if (map['hiddenAt'] != null) continue;
        if (_isDepartureTimePassed(map)) continue;
        result.add(map);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Semua jadwal dari semua driver untuk tanggal tertentu (tanpa filter rute).
  /// Dipakai sebagai fallback di penumpang agar jadwal driver tetap muncul saat filter rute kosong.
  static Future<List<Map<String, dynamic>>> getAllSchedulesForDate(
    DateTime date,
  ) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final snap = await _firestore.collection('driver_schedules').get();
      final result = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final driverUid = doc.id;
        final list = doc.data()['schedules'] as List<dynamic>?;
        if (list == null) continue;
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
          final dateStamp = map['date'] as Timestamp?;
          if (dateStamp == null) continue;
          final scheduleDate = dateStamp.toDate();
          final scheduleDateOnly = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );
          if (scheduleDateOnly != dateStart) continue;
          if (map['hiddenAt'] != null) continue;
          if (scheduleDateOnly == _todayStart && _isDepartureTimePassed(map)) {
            continue;
          }
          result.add({...map, 'driverUid': driverUid});
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Jadwal dari semua driver untuk tanggal dan rute (awal tujuan + tujuan) tertentu.
  /// Cocok jika teks awal/tujuan mengandung kata kunci (case-insensitive).
  /// Setiap item berisi schedule map + driverUid.
  static Future<List<Map<String, dynamic>>> getSchedulesByDateAndRoute(
    DateTime date,
    String originKeyword,
    String destinationKeyword,
  ) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final snap = await _firestore.collection('driver_schedules').get();
      final result = <Map<String, dynamic>>[];
      final o = originKeyword.trim().toLowerCase();
      final d = destinationKeyword.trim().toLowerCase();
      if (o.isEmpty && d.isEmpty) return result;

      for (final doc in snap.docs) {
        final driverUid = doc.id;
        final list = doc.data()['schedules'] as List<dynamic>?;
        if (list == null) continue;
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
          final dateStamp = map['date'] as Timestamp?;
          if (dateStamp == null) continue;
          final scheduleDate = dateStamp.toDate();
          final scheduleDateOnly = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );
          if (scheduleDateOnly != dateStart) continue;
          if (map['hiddenAt'] != null) continue;
          if (scheduleDateOnly == _todayStart && _isDepartureTimePassed(map))
            continue;
          final origin = (map['origin'] as String?)?.trim().toLowerCase() ?? '';
          final dest =
              (map['destination'] as String?)?.trim().toLowerCase() ?? '';
          final matchOrigin = o.isEmpty || origin.contains(o);
          final matchDest = d.isEmpty || dest.contains(d);
          if (!matchOrigin || !matchDest) continue;
          result.add({...map, 'driverUid': driverUid});
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}

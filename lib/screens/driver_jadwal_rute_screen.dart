import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../utils/placemark_formatter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/driver_schedule_service.dart';
import '../services/order_service.dart';

/// Satu item jadwal dari Firebase: tujuan awal, tujuan akhir, jam, tanggal (hanya tampil).
class _JadwalItem {
  final String tujuanAwal;
  final String tujuanAkhir;
  final TimeOfDay jam;
  final DateTime tanggal;

  _JadwalItem({
    required this.tujuanAwal,
    required this.tujuanAkhir,
    required this.jam,
    required this.tanggal,
  });
}

class DriverJadwalRuteScreen extends StatefulWidget {
  /// Dipanggil saat user tap icon rute di card: beralih ke Beranda dan muat rute dari jadwal. [scheduleId] untuk sinkron pesanan terjadwal.
  final void Function(String origin, String dest, String? scheduleId)?
  onOpenRuteFromJadwal;
  final bool disableRouteIconForToday;
  /// Jika false, blokir tambah jadwal dan tampilkan dialog lengkapi verifikasi.
  final bool isDriverVerified;
  /// Dipanggil saat user coba tambah jadwal tapi belum terverifikasi.
  final VoidCallback? onVerificationRequired;

  const DriverJadwalRuteScreen({
    super.key,
    this.onOpenRuteFromJadwal,
    this.disableRouteIconForToday = false,
    this.isDriverVerified = true,
    this.onVerificationRequired,
  });

  @override
  State<DriverJadwalRuteScreen> createState() => _DriverJadwalRuteScreenState();
}

class _DriverJadwalRuteScreenState extends State<DriverJadwalRuteScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final List<_JadwalItem> _items = [];
  bool _loading = true;

  /// PageView jadwal per tanggal: geser kiri = tanggal berikutnya, geser kanan = kembali.
  final PageController _jadwalPageController = PageController();

  /// Bulan yang sedang ditampilkan di kalender (hari pertama bulan).
  DateTime _displayMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  static const List<String> _weekdayLabels = [
    'Min',
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
  ];

  @override
  void initState() {
    super.initState();
    _loadJadwal();
  }

  @override
  void dispose() {
    _jadwalPageController.dispose();
    super.dispose();
  }

  Future<void> _loadJadwal() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final kept = await DriverScheduleService.cleanupPastSchedules(user.uid);
      _items.clear();
      for (final map in kept) {
        final timeStamp = map['departureTime'] as Timestamp?;
        final dateStamp = map['date'] as Timestamp?;
        TimeOfDay jam = TimeOfDay.now();
        if (timeStamp != null) {
          final d = timeStamp.toDate();
          jam = TimeOfDay(hour: d.hour, minute: d.minute);
        }
        final date = dateStamp?.toDate() ?? DateTime.now();
        final origin = (map['origin'] as String?) ?? '';
        final dest = (map['destination'] as String?) ?? '';
        _items.add(
          _JadwalItem(
            tujuanAwal: origin,
            tujuanAkhir: dest,
            jam: jam,
            tanggal: date,
          ),
        );
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Ambil nama kecamatan dan kabupaten saja (segmen pertama dan kedua dari alamat).
  static String _kecamatanDanKabupaten(String s) {
    if (s.trim().isEmpty) return '–';
    final parts = s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return s;
    if (parts.length >= 2) return '${parts[0]}, ${parts[1]}';
    return parts[0];
  }

  static DateTime _dateOnly(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  /// Hari ini (untuk bandingan terlewat/belum).
  static DateTime get _today => _dateOnly(DateTime.now());

  /// Cek apakah tanggal sudah lewat (sebelum hari ini).
  bool _isPast(DateTime d) {
    return _dateOnly(d).isBefore(_today);
  }

  /// Jadwal sudah lewat: tanggal = hari ini tapi jam keberangkatan sudah lewat.
  /// (Jadwal dengan tanggal kemarin sudah terhapus dari Firebase.)
  bool _isScheduleTimePassed(_JadwalItem item) {
    final today = _today;
    final scheduleDate = _dateOnly(item.tanggal);
    if (scheduleDate != today) return false;
    final departure = DateTime(
      item.tanggal.year,
      item.tanggal.month,
      item.tanggal.day,
      item.jam.hour,
      item.jam.minute,
    );
    return DateTime.now().isAfter(departure);
  }

  /// Icon rute berfungsi hanya jika: tanggal jadwal = hari ini dan dalam 4 jam sebelum keberangkatan.
  bool _isRuteAvailableForJadwal(_JadwalItem item) {
    final today = _today;
    final scheduleDate = _dateOnly(item.tanggal);
    if (scheduleDate != today) return false;
    final departure = DateTime(
      item.tanggal.year,
      item.tanggal.month,
      item.tanggal.day,
      item.jam.hour,
      item.jam.minute,
    );
    final now = DateTime.now();
    final windowStart = departure.subtract(const Duration(hours: 4));
    return (now.isAfter(windowStart) || now.isAtSameMomentAs(windowStart)) &&
        (now.isBefore(departure) || now.isAtSameMomentAs(departure));
  }

  /// ID jadwal (sama dengan format di Pesan nanti penumpang) untuk sinkron pesanan terjadwal.
  String _scheduleIdForItem(_JadwalItem item) {
    final uid = _auth.currentUser?.uid ?? '';
    final d = item.tanggal;
    final dateKey =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final departure = DateTime(
      d.year,
      d.month,
      d.day,
      item.jam.hour,
      item.jam.minute,
    );
    return '${uid}_${dateKey}_${departure.millisecondsSinceEpoch}';
  }

  /// Jumlah jadwal yang sudah tersimpan untuk tanggal [d] (maks 1 per tanggal).
  int _scheduleCountForDate(DateTime d) {
    final key = _dateOnly(d);
    return _items.where((i) => _dateOnly(i.tanggal) == key).length;
  }

  /// Daftar tanggal yang punya jadwal, masing-masing berisi list index jadwal (urutan isi = urutan tampil).
  List<MapEntry<DateTime, List<int>>> _groupedByDate() {
    final map = <DateTime, List<int>>{};
    for (var i = 0; i < _items.length; i++) {
      final key = _dateOnly(_items[i].tanggal);
      map.putIfAbsent(key, () => []).add(i);
    }
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted;
  }

  /// Daftar hari untuk kalender bulan [month]: minggu pertama mungkin berisi hari bulan sebelumnya,
  /// minggu terakhir mungkin berisi hari bulan berikutnya, agar grid 7x5/6 rapi.
  List<DateTime?> _calendarDaysForMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final startWeekday = first.weekday % 7; // 0 = Minggu
    final daysInMonth = last.day;

    final result = <DateTime?>[];
    // Kosongkan sel sebelum hari pertama
    for (var i = 0; i < startWeekday; i++) {
      result.add(null);
    }
    for (var d = 1; d <= daysInMonth; d++) {
      result.add(DateTime(month.year, month.month, d));
    }
    // Isi sisa sel sampai kelipatan 7 (opsional, agar baris terakhir penuh)
    final remainder = result.length % 7;
    if (remainder != 0) {
      for (var i = 0; i < 7 - remainder; i++) {
        result.add(null);
      }
    }
    return result;
  }

  String _monthYearLabel(DateTime month) {
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${months[month.month - 1]} ${month.year}';
  }

  static const List<String> _dayNames = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  static String _formatPlacemark(Placemark p) =>
      PlacemarkFormatter.formatDetail(p);

  /// Ambil teks lokasi driver saat ini (untuk isi tujuan awal).
  Future<String?> _getCurrentLocationText() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final list = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (list.isEmpty) return null;
      return _formatPlacemark(list.first);
    } catch (_) {
      return null;
    }
  }

  String _formatDateWithDay(DateTime d) {
    final dayName = _dayNames[d.weekday % 7];
    return '$dayName, ${d.day}/${d.month}/${d.year}';
  }

  /// Tanggal diklik: tampilkan opsi "Atur jadwal dan rute", lalu form.
  void _onDateTapped(DateTime date) {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    if (_isPast(date)) return; // Tanggal lewat tidak bisa diatur
    final count = _scheduleCountForDate(date);
    if (count >= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '1 jadwal per tanggal. Gunakan icon pensil untuk edit.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              child: Icon(Icons.add, color: Theme.of(context).colorScheme.primary, size: 26),
            ),
            title: const Text(
              'Atur jadwal dan rute',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Text(
              _formatDateWithDay(date),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _showAturJadwalForm(date);
            },
          ),
        ),
      ),
    );
  }

  void _showAturJadwalForm(
    DateTime selectedDate, {
    int? editIndex,
    _JadwalItem? editItem,
  }) {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final date = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final formSaving = ValueNotifier<bool>(false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AturJadwalFormContent(
        date: date,
        formatDateWithDay: _formatDateWithDay,
        formatTime: _formatTime,
        getCurrentLocationText: _getCurrentLocationText,
        formatPlacemark: _formatPlacemark,
        auth: _auth,
        firestore: _firestore,
        formSaving: formSaving,
        onSaved: () async {
          await _loadJadwal();
          if (mounted) setState(() {});
        },
        editScheduleIndex: editIndex,
        initialOrigin: editItem?.tujuanAwal,
        initialDest: editItem?.tujuanAkhir,
        initialJam: editItem?.jam,
        isDriverVerified: widget.isDriverVerified,
        onVerificationRequired: widget.onVerificationRequired,
      ),
    ).then((_) {
      formSaving.dispose();
    });
  }

  Widget _buildCalendarSection() {
    final days = _calendarDaysForMonth(_displayMonth);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: colorScheme.onSurface.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Navigasi bulan (bisa ganti ke bulan sebelumnya atau berikutnya)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _displayMonth = DateTime(
                        _displayMonth.year,
                        _displayMonth.month - 1,
                        1,
                      );
                    });
                  },
                  icon: Icon(
                    Icons.chevron_left,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  _monthYearLabel(_displayMonth),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _displayMonth = DateTime(
                        _displayMonth.year,
                        _displayMonth.month + 1,
                        1,
                      );
                    });
                  },
                  icon: Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Header hari (Min, Sen, ...)
            Row(
              children: List.generate(7, (i) {
                return Expanded(
                  child: Center(
                    child: Text(
                      _weekdayLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 4),
            // Grid tanggal (1 bulan penuh) — tap untuk atur jadwal
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.1,
              children: days.map<Widget>((d) {
                if (d == null) {
                  return const SizedBox.shrink();
                }
                final isPast = _isPast(d);
                final isToday = _dateOnly(d) == _today;
                final count = _scheduleCountForDate(d);
                return InkWell(
                  onTap: () => _onDateTapped(d),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Tanggal selalu terlihat
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isPast
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                        ),
                        // Tanda sudah isi jadwal: titik kecil di bawah angka (tidak menutupi tanggal)
                        if (count >= 1) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              count.clamp(1, 2),
                              (_) => Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, color: Theme.of(context).colorScheme.onSurface, size: 24),
            const SizedBox(width: 8),
            Text(
              'Jadwal dan rute Travel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Kalender 1 bulan penuh + navigasi bulan
                    _buildCalendarSection(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadJadwal,
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 32),
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Belum ada jadwal tersimpan',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tap tanggal di kalender untuk menambah jadwal.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Geser kiri: tanggal berikutnya · Geser kanan: kembali',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    child: PageView.builder(
                                      controller: _jadwalPageController,
                                      itemCount: _groupedByDate().length,
                                      itemBuilder: (context, pageIndex) {
                                        final grouped = _groupedByDate();
                                        if (pageIndex >= grouped.length) {
                                          return const SizedBox.shrink();
                                        }
                                        final entry = grouped[pageIndex];
                                        final date = entry.key;
                                        final indices = entry.value;
                                        return SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.only(
                                            bottom: 24,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                  bottom: 12,
                                                ),
                                                child: Text(
                                                  _formatDateWithDay(date),
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                              ...indices.map(
                                                (index) => _buildJadwalCard(
                                                  index,
                                                  _items[index],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildJadwalCard(int index, _JadwalItem item) {
    final kecAwal = _kecamatanDanKabupaten(item.tujuanAwal);
    final kecAkhir = _kecamatanDanKabupaten(item.tujuanAkhir);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Baris 1: [icon kalender] hari dan tanggal | [icon jam] jam | icon edit (kanan)
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDateWithDay(item.tanggal),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(item.jam),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                FutureBuilder<({int totalPenumpang, int kirimBarangCount})>(
                  future: OrderService.getScheduledBookingCounts(
                    _scheduleIdForItem(item),
                  ),
                  builder: (context, snap) {
                    final counts = snap.data;
                    final hasBookings =
                        ((counts?.totalPenumpang ?? 0) +
                            (counts?.kirimBarangCount ?? 0)) >
                        0;
                    return IconButton(
                      icon: Icon(
                        Icons.edit,
                        size: 18,
                        color: hasBookings
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      tooltip: hasBookings
                          ? 'Pada tanggal ini sudah ada yang pesan. Batalkan pesanan dulu untuk mengubah jadwal.'
                          : 'Edit jadwal',
                      onPressed: () =>
                          _onEditJadwalTapped(item, index, hasBookings),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Baris 2: tujuan awal => tujuan akhir (kecamatan, kabupaten) - tampil penuh tanpa titik
            Text(
              '$kecAwal => $kecAkhir',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            // Baris 3: [icon rute] | [icon pemesan] | [icon barang]
            Builder(
              builder: (context) {
                final timePassed = _isScheduleTimePassed(item);
                final disableByHomeRoute =
                    widget.disableRouteIconForToday &&
                    _dateOnly(item.tanggal) == _today;
                final routeAvailable = _isRuteAvailableForJadwal(item);
                final bool routeEnabled = !timePassed;
                Color? routeIconColor;
                Color? routeLabelColor;
                if (timePassed) {
                  // warna default akan digreyscale oleh _buildBaris3Chip
                } else if (disableByHomeRoute) {
                  routeIconColor = Theme.of(context).colorScheme.onSurfaceVariant;
                  routeLabelColor = Theme.of(context).colorScheme.onSurfaceVariant;
                } else if (!routeAvailable) {
                  routeIconColor = Colors.red;
                  routeLabelColor = Colors.red;
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBaris3Chip(
                        icon: Icons.route,
                        label: 'Rute',
                        enabled: routeEnabled,
                        iconColor: routeIconColor,
                        labelColor: routeLabelColor,
                        onTap: () {
                          if (disableByHomeRoute) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Rute aktif berasal dari Beranda. Selesaikan rute tersebut terlebih dahulu.',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          if (routeAvailable) {
                            widget.onOpenRuteFromJadwal?.call(
                              item.tujuanAwal,
                              item.tujuanAkhir,
                              _scheduleIdForItem(item),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Rute tersedia mulai 4 jam sebelum jam keberangkatan (${_formatTime(item.jam)}) pada hari H.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPemesanChip(item: item, timePassed: timePassed),
                      const SizedBox(width: 6),
                      _buildBarangChip(item: item, timePassed: timePassed),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPemesanChip({
    required _JadwalItem item,
    required bool timePassed,
  }) {
    final scheduleId = _scheduleIdForItem(item);
    return FutureBuilder<({int totalPenumpang, int kirimBarangCount})>(
      future: OrderService.getScheduledBookingCounts(scheduleId),
      builder: (context, snap) {
        final n = snap.data?.totalPenumpang ?? 0;
        final label = n > 0 ? 'Pemesan ($n)' : 'Pemesan';
        return _buildBaris3Chip(
          icon: Icons.people_outline,
          label: label,
          enabled: !timePassed,
          onTap: () => _showPemesanSheet(scheduleId),
        );
      },
    );
  }

  Widget _buildBarangChip({
    required _JadwalItem item,
    required bool timePassed,
  }) {
    final scheduleId = _scheduleIdForItem(item);
    return FutureBuilder<({int totalPenumpang, int kirimBarangCount})>(
      future: OrderService.getScheduledBookingCounts(scheduleId),
      builder: (context, snap) {
        final n = snap.data?.kirimBarangCount ?? 0;
        final label = n > 0 ? 'Barang ($n)' : 'Barang';
        return _buildBaris3Chip(
          icon: Icons.inventory_2_outlined,
          label: label,
          enabled: !timePassed,
          onTap: () => _showBarangSheet(scheduleId),
        );
      },
    );
  }

  void _onEditJadwalTapped(_JadwalItem item, int index, bool hasBookings) {
    if (hasBookings) {
      final scheduleId = _scheduleIdForItem(item);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tidak dapat mengubah jadwal'),
          content: const Text(
            'Pada tanggal ini sudah ada yang pesan. Jika ingin mengubah jadwal, pesanan di tanggal tersebut dengan penumpang dibatalkan dulu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showPemesanSheet(scheduleId);
              },
              child: const Text('Lihat pemesan'),
            ),
          ],
        ),
      );
      return;
    }
    _showAturJadwalForm(item.tanggal, editIndex: index, editItem: item);
  }

  void _showPemesanSheet(String scheduleId) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScheduledPassengersSheet(
        scheduleId: scheduleId,
        title: 'Penumpang yang sudah pesan',
        travelOnly: true,
      ),
    );
  }

  void _showBarangSheet(String scheduleId) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScheduledPassengersSheet(
        scheduleId: scheduleId,
        title: 'Pesanan kirim barang',
        kirimBarangOnly: true,
      ),
    );
  }

  Widget _buildBaris3Chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? labelColor,
    bool enabled = true,
  }) {
    const double iconSize = 16;
    const double fontSize = 11;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final iconC = !enabled ? grey : (iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant);
    final labelC = !enabled ? grey : (labelColor ?? Theme.of(context).colorScheme.onSurface);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: iconC),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: fontSize, color: labelC),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Bottom sheet daftar penumpang yang sudah pesan (nama + foto) untuk satu jadwal.
class _ScheduledPassengersSheet extends StatelessWidget {
  final String scheduleId;
  final String title;
  final bool? travelOnly;
  final bool? kirimBarangOnly;

  const _ScheduledPassengersSheet({
    required this.scheduleId,
    required this.title,
    this.travelOnly,
    this.kirimBarangOnly,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: OrderService.getScheduledOrdersWithPassengerInfo(
                scheduleId,
                travelOnly: travelOnly,
                kirimBarangOnly: kirimBarangOnly,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Belum ada yang pesan',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final name = (m['passengerName'] as String?) ?? 'Penumpang';
                    final photoUrl = m['passengerPhotoUrl'] as String?;
                    final orderType = m['orderType'] as String?;
                    final jk = (m['jumlahKerabat'] as num?)?.toInt();
                    final subtitle = orderType == 'kirim_barang'
                        ? 'Kirim Barang'
                        : (jk == null || jk <= 0)
                        ? '1 orang'
                        : '${1 + jk} orang';
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Form isi jadwal: tujuan awal (dengan icon lokasi + autocomplete), tujuan akhir (autocomplete), jam, simpan.
/// Jika [editScheduleIndex] != null, form untuk edit dan simpan akan update jadwal di index tersebut.
class _AturJadwalFormContent extends StatefulWidget {
  final DateTime date;
  final String Function(DateTime) formatDateWithDay;
  final String Function(TimeOfDay) formatTime;
  final Future<String?> Function() getCurrentLocationText;
  final String Function(Placemark) formatPlacemark;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final ValueNotifier<bool> formSaving;
  final Future<void> Function() onSaved;
  final int? editScheduleIndex;
  final String? initialOrigin;
  final String? initialDest;
  final TimeOfDay? initialJam;
  final bool isDriverVerified;
  final VoidCallback? onVerificationRequired;

  const _AturJadwalFormContent({
    required this.date,
    required this.formatDateWithDay,
    required this.formatTime,
    required this.getCurrentLocationText,
    required this.formatPlacemark,
    required this.auth,
    required this.firestore,
    required this.formSaving,
    required this.onSaved,
    this.editScheduleIndex,
    this.initialOrigin,
    this.initialDest,
    this.initialJam,
    this.isDriverVerified = true,
    this.onVerificationRequired,
  });

  @override
  State<_AturJadwalFormContent> createState() => _AturJadwalFormContentState();
}

class _AturJadwalFormContentState extends State<_AturJadwalFormContent> {
  late final TextEditingController _originController;
  late final TextEditingController _destController;
  late TimeOfDay _jam;
  List<Placemark> _originResults = [];
  List<Placemark> _destResults = [];
  bool _showOrigin = false;
  bool _showDest = false;
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(text: widget.initialOrigin ?? '');
    _destController = TextEditingController(text: widget.initialDest ?? '');
    _jam = widget.initialJam ?? TimeOfDay.now();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _fillCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final text = await widget.getCurrentLocationText();
      if (text != null && mounted) {
        _originController.text = text;
        setState(() {
          _originResults = [];
          _showOrigin = false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLocation = false);
  }

  Future<void> _searchLocation(String value, bool isOrigin) async {
    if (value.trim().isEmpty) {
      setState(() {
        if (isOrigin) {
          _originResults = [];
          _showOrigin = false;
        } else {
          _destResults = [];
          _showDest = false;
        }
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (isOrigin && _originController.text.trim() != value.trim()) return;
    if (!isOrigin && _destController.text.trim() != value.trim()) return;
    try {
      final locations = await locationFromAddress('$value, Indonesia');
      final placemarks = <Placemark>[];
      for (var i = 0; i < locations.length && i < 10; i++) {
        try {
          final list = await placemarkFromCoordinates(
            locations[i].latitude,
            locations[i].longitude,
          );
          if (list.isNotEmpty) placemarks.add(list.first);
        } catch (_) {}
      }
      if (!mounted) return;
      if (isOrigin && _originController.text.trim() != value.trim()) return;
      if (!isOrigin && _destController.text.trim() != value.trim()) return;
      setState(() {
        if (isOrigin) {
          _originResults = placemarks;
          _showOrigin = placemarks.isNotEmpty;
        } else {
          _destResults = placemarks;
          _showDest = placemarks.isNotEmpty;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isOrigin) {
            _originResults = [];
            _showOrigin = false;
          } else {
            _destResults = [];
            _showDest = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.formSaving,
      builder: (context, saving, _) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.editScheduleIndex != null
                      ? 'Edit jadwal — ${widget.formatDateWithDay(widget.date)}'
                      : 'Jadwal ${widget.formatDateWithDay(widget.date)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                // Tujuan awal + icon lokasi
                if (_showOrigin && _originResults.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 160
                          : 220,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _originResults.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                        itemBuilder: (context, i) {
                          final p = _originResults[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              widget.formatPlacemark(p),
                              style: const TextStyle(fontSize: 13, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _originController.text = widget.formatPlacemark(p);
                              setState(() {
                                _originResults = [];
                                _showOrigin = false;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                TextField(
                  controller: _originController,
                  decoration: InputDecoration(
                    labelText: 'Tujuan awal',
                    hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _loadingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.my_location,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24,
                            ),
                            tooltip: 'Gunakan lokasi saat ini',
                            onPressed: _loadingLocation
                                ? null
                                : _fillCurrentLocation,
                          ),
                  ),
                  onChanged: (value) => _searchLocation(value, true),
                ),
                const SizedBox(height: 16),
                // Tujuan akhir + autocomplete
                if (_showDest && _destResults.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 160
                          : 220,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _destResults.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                        itemBuilder: (context, i) {
                          final p = _destResults[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              widget.formatPlacemark(p),
                              style: const TextStyle(fontSize: 13, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _destController.text = widget.formatPlacemark(p);
                              setState(() {
                                _destResults = [];
                                _showDest = false;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                TextField(
                  controller: _destController,
                  decoration: const InputDecoration(
                    labelText: 'Tujuan akhir',
                    hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => _searchLocation(value, false),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _jam,
                    );
                    if (picked != null && mounted) {
                      setState(() => _jam = picked);
                    }
                  },
                  icon: const Icon(Icons.access_time, size: 20),
                  label: Text(widget.formatTime(_jam)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (widget.editScheduleIndex != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving ? null : _onHapus,
                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade700),
                      label: Text(
                        'Hapus jadwal',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: saving ? null : _onSimpan,
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                        ),
                        child: saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onHapus() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final idx = widget.editScheduleIndex;
    if (idx == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus jadwal'),
        content: const Text(
          'Yakin ingin menghapus jadwal ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.formSaving.value = true;
    try {
      final doc = await widget.firestore
          .collection('driver_schedules')
          .doc(user.uid)
          .get();
      final List<dynamic> schedules =
          (doc.data()?['schedules'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              )
              .toList() ??
          [];
      if (idx >= 0 && idx < schedules.length) {
        schedules.removeAt(idx);
        await widget.firestore.collection('driver_schedules').doc(user.uid).set({
          'schedules': schedules,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) Navigator.pop(context);
        await widget.onSaved();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Jadwal berhasil dihapus.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      widget.formSaving.value = false;
    }
  }

  Future<void> _onSimpan() async {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tujuan awal dan tujuan akhir wajib diisi.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final dt = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      _jam.hour,
      _jam.minute,
    );
    final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final scheduleDateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);
    if (scheduleDateStart == todayStart && dt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jam keberangkatan tidak boleh di masa lalu untuk tanggal hari ini.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final user = widget.auth.currentUser;
    if (user == null) return;
    widget.formSaving.value = true;
    try {
      final doc = await widget.firestore
          .collection('driver_schedules')
          .doc(user.uid)
          .get();
      final List<dynamic> schedules =
          (doc.data()?['schedules'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              )
              .toList() ??
          [];
      final newMap = <String, dynamic>{
        'origin': origin,
        'destination': dest,
        'departureTime': Timestamp.fromDate(dt),
        'date': Timestamp.fromDate(widget.date),
      };
      final idx = widget.editScheduleIndex;
      if (idx != null && idx >= 0 && idx < schedules.length) {
        // Preserve hiddenAt if ada
        final existing = schedules[idx] as Map<String, dynamic>;
        if (existing['hiddenAt'] != null) {
          newMap['hiddenAt'] = existing['hiddenAt'];
        }
        schedules[idx] = newMap;
      } else {
        schedules.add(newMap);
      }
      await widget.firestore.collection('driver_schedules').doc(user.uid).set({
        'schedules': schedules,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
      await widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              idx != null
                  ? 'Jadwal berhasil diubah.'
                  : 'Jadwal berhasil disimpan.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      widget.formSaving.value = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../theme/app_theme.dart';
import '../widgets/receiver_contact_picker.dart';
import '../utils/placemark_formatter.dart';
import '../theme/responsive.dart';
import '../services/chat_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/scheduled_drivers_service.dart';
import '../services/location_service.dart';
import '../services/order_service.dart';
import '../models/order_model.dart';
import 'chat_room_penumpang_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Format alamat singkat: hanya kecamatan dan kabupaten.
String _formatAlamatKecamatanKabupaten(String alamat) {
  if (alamat.isEmpty) return alamat;
  final parts = alamat
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return alamat;

  String? kecamatan;
  String? kabupaten;

  for (final part in parts) {
    final lower = part.toLowerCase();
    if (lower.contains('kecamatan') || lower.contains('kec.')) {
      kecamatan = part;
    } else if (lower.contains('kabupaten') ||
        lower.contains('kab.') ||
        lower.contains('kota ') ||
        (lower.contains('kota') && !lower.contains('kabupaten'))) {
      kabupaten = part;
    }
  }

  if (kecamatan == null && kabupaten == null && parts.length >= 2) {
    kecamatan = parts[0];
    kabupaten = parts[1];
  } else if (kecamatan == null && parts.isNotEmpty) {
    kecamatan = parts[0];
  }

  final result = <String>[];
  if (kecamatan != null) result.add(kecamatan);
  if (kabupaten != null && kabupaten != kecamatan) result.add(kabupaten);

  return result.isEmpty ? alamat : result.join(', ');
}

class PesanScreen extends StatefulWidget {
  final bool isVerified;
  final VoidCallback? onVerificationRequired;

  const PesanScreen({
    super.key,
    this.isVerified = false,
    this.onVerificationRequired,
  });

  @override
  State<PesanScreen> createState() => _PesanScreenState();
}

class _PesanScreenState extends State<PesanScreen> {
  late DateTime _shownMonth;

  /// true = tampilkan kalender; false = tampilkan hasil jadwal (setelah Cari Travel).
  bool _showCalendar = true;
  String _searchOrigin = '';
  String _searchDest = '';
  double? _searchOriginLat;
  double? _searchOriginLng;
  double? _searchDestLat;
  double? _searchDestLng;
  /// Provinsi asal/tujuan penumpang (dari placemark) untuk filter kecocokan provinsi.
  String? _searchOriginProvince;
  String? _searchDestProvince;
  DateTime? _resultStartDate;
  final PageController _resultPageController = PageController();
  int _resultPageIndex = 0;
  static const int _resultDaysCount = 31;

  /// Cache jadwal per tanggal. Key: "y-m-d".
  final Map<String, List<Map<String, dynamic>>> _scheduleCache = {};
  final Map<String, bool> _scheduleLoading = {};

  /// Cache driver dengan jadwal yang rutenya melewati (menggunakan logika baru).
  final Map<String, List<ScheduledDriverRoute>> _scheduledDriversCache = {};
  final Map<String, bool> _scheduledDriversLoading = {};

  @override
  void initState() {
    super.initState();
    _shownMonth = DateTime(DateTime.now().year, DateTime.now().month);
  }

  @override
  void dispose() {
    _resultPageController.dispose();
    super.dispose();
  }

  static String _dateKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadSchedulesForDate(DateTime date) async {
    final key = _dateKey(date);
    if (_scheduleCache.containsKey(key) || _scheduleLoading[key] == true)
      return;
    _scheduleLoading[key] = true;
    if (mounted) setState(() {});

    // Jika ada koordinat origin dan destination, gunakan logika baru (cek rute yang melewati)
    if (_searchOriginLat != null &&
        _searchOriginLng != null &&
        _searchDestLat != null &&
        _searchDestLng != null) {
      try {
        final scheduledDrivers =
            await ScheduledDriversService.getScheduledDriversForMap(
              date: date,
              passengerOriginLat: _searchOriginLat!,
              passengerOriginLng: _searchOriginLng!,
              passengerDestLat: _searchDestLat!,
              passengerDestLng: _searchDestLng!,
              passengerOriginProvince: _searchOriginProvince,
              passengerDestProvince: _searchDestProvince,
            );

        // Konversi ScheduledDriverRoute ke format Map untuk kompatibilitas dengan UI yang ada
        final list = scheduledDrivers.map((s) {
          return <String, dynamic>{
            'driverUid': s.driverUid,
            'origin': s.scheduleOriginText,
            'destination': s.scheduleDestText,
            'departureTime': Timestamp.fromDate(s.departureTime),
            'date': Timestamp.fromDate(s.scheduleDate),
            'driverName': s.driverName,
            'photoUrl': s.driverPhotoUrl,
            'maxPassengers': s.maxPassengers,
            'vehicleMerek': s.vehicleMerek,
            'vehicleType': s.vehicleType,
            'isVerified': s.isVerified,
          };
        }).toList();

        if (mounted) {
          var resultList = list;
          if (resultList.isEmpty) {
            resultList = await DriverScheduleService.getAllSchedulesForDate(date);
          }
          _scheduleCache[key] = resultList;
          _scheduleLoading[key] = false;
          setState(() {});
        }
      } catch (e) {
        // Jika error, fallback ke logika lama
        if (kDebugMode) debugPrint('PesanScreen._loadSchedulesForDate: Error menggunakan logika baru: $e');
        var list = await DriverScheduleService.getSchedulesByDateAndRoute(
          date,
          _searchOrigin,
          _searchDest,
        );
        if (list.isEmpty) {
          list = await DriverScheduleService.getAllSchedulesForDate(date);
        }
        if (mounted) {
          _scheduleCache[key] = list;
          _scheduleLoading[key] = false;
          setState(() {});
        }
      }
    } else {
      // Fallback: gunakan logika lama jika tidak ada koordinat
      var list = await DriverScheduleService.getSchedulesByDateAndRoute(
        date,
        _searchOrigin,
        _searchDest,
      );
      if (list.isEmpty) {
        list = await DriverScheduleService.getAllSchedulesForDate(date);
      }
      if (mounted) {
        _scheduleCache[key] = list;
        _scheduleLoading[key] = false;
        setState(() {});
      }
    }
  }

  Future<void> _onCariTravel({
    required DateTime selectedDate,
    required String origin,
    required String dest,
  }) async {
    double? originLat;
    double? originLng;
    double? destLat;
    double? destLng;
    String? originProvince;
    String? destProvince;

    try {
      final originLocations = await locationFromAddress('$origin, Indonesia');
      final destLocations = await locationFromAddress('$dest, Indonesia');

      if (originLocations.isNotEmpty && destLocations.isNotEmpty) {
        originLat = originLocations.first.latitude;
        originLng = originLocations.first.longitude;
        destLat = destLocations.first.latitude;
        destLng = destLocations.first.longitude;
        try {
          final originPlacemarks = await placemarkFromCoordinates(originLat, originLng);
          final destPlacemarks = await placemarkFromCoordinates(destLat, destLng);
          if (originPlacemarks.isNotEmpty) {
            originProvince = (originPlacemarks.first.administrativeArea ?? '').trim();
          }
          if (destPlacemarks.isNotEmpty) {
            destProvince = (destPlacemarks.first.administrativeArea ?? '').trim();
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PesanScreen._onCariTravel: Error geocode: $e');
    }

    setState(() {
      _showCalendar = false;
      _searchOrigin = origin.trim();
      _searchDest = dest.trim();
      _searchOriginLat = originLat;
      _searchOriginLng = originLng;
      _searchDestLat = destLat;
      _searchDestLng = destLng;
      _searchOriginProvince = originProvince;
      _searchDestProvince = destProvince;
      _resultStartDate = selectedDate;
      _resultPageIndex = 0;
      _scheduleCache.clear();
      _scheduleLoading.clear();
      _scheduledDriversCache.clear();
      _scheduledDriversLoading.clear();
    });
    _resultPageController.jumpToPage(0);
    await _loadSchedulesForDate(selectedDate);
  }

  void _showCalendarAgain() {
    setState(() {
      _showCalendar = true;
      _resultStartDate = null;
      _searchOriginLat = null;
      _searchOriginLng = null;
      _searchDestLat = null;
      _searchDestLng = null;
      _searchOriginProvince = null;
      _searchDestProvince = null;
      _scheduleCache.clear();
      _scheduleLoading.clear();
      _scheduledDriversCache.clear();
      _scheduledDriversLoading.clear();
    });
  }

  void _showGantiAsalTujuan() {
    final currentDate = _resultStartDate!.add(Duration(days: _resultPageIndex));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: _FormCariTravel(
              selectedDate: currentDate,
              initialOrigin: _searchOrigin,
              initialDest: _searchDest,
              onCari: (origin, dest) async {
                Navigator.of(ctx).pop();
                await _onCariTravel(
                  selectedDate: currentDate,
                  origin: origin,
                  dest: dest,
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _onPesanJadwal(
    BuildContext context,
    Map<String, dynamic> item,
    String scheduleId,
    String scheduledDate,
    String origin,
    String dest,
  ) {
    if (!widget.isVerified) {
      _showLengkapiVerifikasiDialog();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PesanJadwalSheet(
        item: item,
        scheduleId: scheduleId,
        scheduledDate: scheduledDate,
        origin: origin,
        dest: dest,
        onCreated: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showLengkapiVerifikasiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lengkapi data verifikasi'),
        content: const Text(
          'Lengkapi data verifikasi terlebih dahulu untuk memesan travel terjadwal.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onVerificationRequired?.call();
            },
            child: const Text('Lengkapi Sekarang'),
          ),
        ],
      ),
    );
  }

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  int _firstWeekday(DateTime month) {
    return DateTime(month.year, month.month, 1).weekday;
  }

  void _onDateTapped(DateTime cellDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (cellDate.isBefore(today)) return;

    if (!widget.isVerified) {
      _showLengkapiVerifikasiDialog();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: _FormCariTravel(
              selectedDate: cellDate,
              onCari: (origin, dest) async {
                Navigator.of(ctx).pop();
                await _onCariTravel(
                  selectedDate: cellDate,
                  origin: origin,
                  dest: dest,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendar() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstWeekday = _firstWeekday(_shownMonth);
    final daysInMonth = _daysInMonth(_shownMonth);
    final leadingEmpty = firstWeekday - 1;
    final totalCells = leadingEmpty + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
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
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: colorScheme.onSurface.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: EdgeInsets.all(context.responsive.spacing(AppTheme.spacingLg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bulan/tahun + navigasi
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Material(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  onTap: () {
                    setState(() {
                      _shownMonth = DateTime(
                        _shownMonth.year,
                        _shownMonth.month - 1,
                      );
                    });
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.responsive.spacing(12),
                      vertical: context.responsive.spacing(10),
                    ),
                    child: Icon(
                      Icons.chevron_left,
                      size: 24,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              Text(
                _monthYearLabel(_shownMonth),
                style: TextStyle(
                  fontSize: context.responsive.fontSize(18),
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              Material(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  onTap: () {
                    setState(() {
                      _shownMonth = DateTime(
                        _shownMonth.year,
                        _shownMonth.month + 1,
                      );
                    });
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.responsive.spacing(12),
                      vertical: context.responsive.spacing(10),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 24,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Baris nama hari
          Row(
            children: List.generate(
              7,
              (i) => Expanded(
                child: Center(
                  child: Text(
                    _dayNames[i],
                    style: TextStyle(
                      fontSize: context.responsive.fontSize(12),
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: context.responsive.spacing(12)),
          // Grid tanggal
          ...List.generate(rows, (rowIndex) {
            final cellH = context.responsive.spacing(48).clamp(36.0, 52.0);
            return Padding(
              padding: EdgeInsets.only(
                bottom: rowIndex < rows - 1 ? context.responsive.spacing(8) : 0,
              ),
              child: Row(
                children: List.generate(7, (colIndex) {
                  final cellIndex = rowIndex * 7 + colIndex;
                  if (cellIndex < leadingEmpty) {
                    return Expanded(child: SizedBox(height: cellH));
                  }
                  final day = cellIndex - leadingEmpty + 1;
                  if (day > daysInMonth) {
                    return Expanded(child: SizedBox(height: cellH));
                  }
                  final cellDate = DateTime(
                    _shownMonth.year,
                    _shownMonth.month,
                    day,
                  );
                  final isPast = cellDate.isBefore(today);
                  final isToday = cellDate == today;
                  final isSelectable = !isPast;

                  Color bgColor = Colors.transparent;
                  Color textColor = colorScheme.onSurfaceVariant;
                  FontWeight fontWeight = FontWeight.w500;

                  if (isPast) {
                    textColor = colorScheme.onSurfaceVariant;
                  } else if (isToday) {
                    bgColor = colorScheme.primary;
                    textColor = colorScheme.onPrimary;
                    fontWeight = FontWeight.w700;
                  } else {
                    textColor = colorScheme.primary;
                  }

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.responsive.spacing(2),
                      ),
                      child: Material(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                          onTap: isSelectable
                              ? () => _onDateTapped(cellDate)
                              : null,
                          splashColor: isSelectable
                              ? colorScheme.primary.withValues(alpha: 0.2)
                              : null,
                          highlightColor: isSelectable
                              ? colorScheme.primary.withValues(alpha: 0.1)
                              : null,
                          child: Container(
                            height: cellH,
                            alignment: Alignment.center,
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: context.responsive.fontSize(16),
                                color: textColor,
                                fontWeight: fontWeight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
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

  Widget _buildResultView() {
    final start = _resultStartDate!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: context.responsive.spacing(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _formatResultDate(start.add(Duration(days: _resultPageIndex))),
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(16),
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showGantiAsalTujuan,
                icon: const Icon(Icons.edit_location_alt, size: 18),
                label: const Text('Ganti asal/tujuan'),
              ),
              TextButton.icon(
                onPressed: _showCalendarAgain,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: const Text('Ubah tanggal'),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _resultPageController,
            itemCount: _resultDaysCount,
            onPageChanged: (i) {
              setState(() => _resultPageIndex = i);
              final date = start.add(Duration(days: i));
              _loadSchedulesForDate(date);
            },
            itemBuilder: (context, index) {
              final date = start.add(Duration(days: index));
              return _BuildJadwalListPage(
                date: date,
                origin: _searchOrigin,
                dest: _searchDest,
                scheduleCache: _scheduleCache,
                scheduleLoading: _scheduleLoading,
                loadSchedules: _loadSchedulesForDate,
                dateKey: _dateKey,
                onPesan: _onPesanJadwal,
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatResultDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 8),
            Text(
              'Pesan Travel Terjadwal',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: _showCalendar
            ? Padding(
                padding: EdgeInsets.all(context.responsive.horizontalPadding),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pilih tanggal keberangkatan, lalu isi asal & tujuan untuk melihat driver yang tersedia.',
                        style: TextStyle(
                          fontSize: context.responsive.fontSize(15),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: context.responsive.spacing(24)),
                      _buildCalendar(),
                    ],
                  ),
                ),
              )
            : _buildResultView(),
      ),
    );
  }

  static const List<String> _dayNames = [
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
    'Min',
  ];
}

/// Form dalam bottom sheet: Awal tujuan (dengan icon lokasi), Tujuan travel, tombol Cari Jadwal.
class _FormCariTravel extends StatefulWidget {
  final DateTime selectedDate;
  final void Function(String origin, String dest) onCari;
  final String? initialOrigin;
  final String? initialDest;

  const _FormCariTravel({
    required this.selectedDate,
    required this.onCari,
    this.initialOrigin,
    this.initialDest,
  });

  @override
  State<_FormCariTravel> createState() => _FormCariTravelState();
}

class _FormCariTravelState extends State<_FormCariTravel> {
  late final TextEditingController _originController;
  late final TextEditingController _destController;
  bool _loadingLocation = false;
  List<Placemark> _originResults = [];
  bool _showOrigin = false;
  List<Placemark> _destResults = [];
  bool _showDest = false;

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(text: widget.initialOrigin ?? '');
    _destController = TextEditingController(text: widget.initialDest ?? '');
  }

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  static String _formatPlacemark(Placemark p) =>
      PlacemarkFormatter.formatDetail(p);

  Future<void> _searchOrigin(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _originResults = [];
        _showOrigin = false;
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (_originController.text.trim() != query) return;
    try {
      final locations = await locationFromAddress('$query, Indonesia');
      final placemarks = <Placemark>[];
      for (var i = 0; i < locations.length && i < 8; i++) {
        try {
          final list = await placemarkFromCoordinates(
            locations[i].latitude,
            locations[i].longitude,
          );
          if (list.isNotEmpty) placemarks.add(list.first);
        } catch (_) {}
      }
      if (!mounted) return;
      if (_originController.text.trim() != query) return;
      setState(() {
        _originResults = placemarks;
        _showOrigin = placemarks.isNotEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _originResults = [];
          _showOrigin = false;
        });
      }
    }
  }

  Future<void> _searchDest(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _destResults = [];
        _showDest = false;
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (_destController.text.trim() != query) return;
    try {
      final locations = await locationFromAddress('$query, Indonesia');
      final placemarks = <Placemark>[];
      for (var i = 0; i < locations.length && i < 8; i++) {
        try {
          final list = await placemarkFromCoordinates(
            locations[i].latitude,
            locations[i].longitude,
          );
          if (list.isNotEmpty) placemarks.add(list.first);
        } catch (_) {}
      }
      if (!mounted) return;
      if (_destController.text.trim() != query) return;
      setState(() {
        _destResults = placemarks;
        _showDest = placemarks.isNotEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _destResults = [];
          _showDest = false;
        });
      }
    }
  }

  Future<void> _fillCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final hasPermission = await LocationService.requestPermission();
      if (!hasPermission || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin lokasi diperlukan. Aktifkan di pengaturan.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _loadingLocation = false);
        return;
      }
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected) {
        if (mounted) FakeGpsOverlayService.showOverlay();
        setState(() => _loadingLocation = false);
        return;
      }
      final position = result.position;
      if (position == null || !mounted) {
        setState(() => _loadingLocation = false);
        return;
      }
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.name ?? '').isNotEmpty) parts.add(p.name!);
        if ((p.thoroughfare ?? '').isNotEmpty) parts.add(p.thoroughfare!);
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.administrativeArea ?? '').isNotEmpty)
          parts.add(p.administrativeArea!);
        if (parts.isNotEmpty) {
          _originController.text = parts.join(', ');
        } else {
          _originController.text =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
      } else if (mounted) {
        _originController.text =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengambil lokasi. Coba lagi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _loadingLocation = false);
  }

  void _submit() {
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi awal tujuan dan tujuan perjalanan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onCari(origin, dest);
  }

  @override
  Widget build(BuildContext context) {
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
    final d = widget.selectedDate;
    final dateLabel = '${d.day} ${months[d.month - 1]} ${d.year}';

    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxFormHeight = mediaQuery.size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxFormHeight),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            left: context.responsive.horizontalPadding,
            right: context.responsive.horizontalPadding,
            top: context.responsive.spacing(24),
            bottom: bottomInset + context.responsive.spacing(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tanggal: $dateLabel',
                style: TextStyle(
                  fontSize: context.responsive.fontSize(16),
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              if (_showOrigin && _originResults.isNotEmpty)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: bottomInset > 0 ? 160 : 220,
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
                            _formatPlacemark(p),
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _originController.text = _formatPlacemark(p);
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
                  labelText: 'Awal tujuan',
                  hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: _loadingLocation
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    onPressed: _loadingLocation ? null : _fillCurrentLocation,
                    tooltip: 'Gunakan lokasi saat ini',
                  ),
                ),
                onChanged: _searchOrigin,
              ),
              const SizedBox(height: 12),
              if (_showDest && _destResults.isNotEmpty)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: bottomInset > 0 ? 160 : 220,
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
                            _formatPlacemark(p),
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _destController.text = _formatPlacemark(p);
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
                  labelText: 'Tujuan travel',
                  hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                  border: OutlineInputBorder(),
                ),
                onChanged: _searchDest,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cari Jadwal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet pilihan: Pesan Travel Sendiri / dengan Kerabat / Kirim Barang (untuk jadwal).
class _PesanJadwalSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String scheduleId;
  final String scheduledDate;
  final String origin;
  final String dest;
  final VoidCallback onCreated;

  const _PesanJadwalSheet({
    required this.item,
    required this.scheduleId,
    required this.scheduledDate,
    required this.origin,
    required this.dest,
    required this.onCreated,
  });

  @override
  State<_PesanJadwalSheet> createState() => _PesanJadwalSheetState();
}

class _PesanJadwalSheetState extends State<_PesanJadwalSheet> {
  bool _loading = false;

  static String _formatScheduledDate(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final d = int.tryParse(parts[2]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 1;
    final y = parts[0];
    if (m < 1 || m > 12) return ymd;
    return '$d ${months[m - 1]} $y';
  }

  Future<void> _createAndOpenChat({
    required String orderType,
    int? jumlahKerabat,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_loading) return;

    setState(() => _loading = true);

    String? passengerName;
    String? passengerPhotoUrl;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        passengerName = userDoc.data()!['displayName'] as String?;
        passengerPhotoUrl = userDoc.data()!['photoUrl'] as String?;
      }
    } catch (_) {}
    passengerName ??= user.email ?? 'Penumpang';

    final driverUid = widget.item['driverUid'] as String? ?? '';
    final driverName = (widget.item['driverName'] as String?) ?? 'Driver';
    final driverPhotoUrl = widget.item['photoUrl'] as String?;
    final dateLabel = _formatScheduledDate(widget.scheduledDate);

    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: driverUid,
      routeJourneyNumber: OrderService.routeJourneyNumberScheduled,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      originText: widget.origin,
      destText: widget.dest,
      originLat: null,
      originLng: null,
      destLat: null,
      destLng: null,
      orderType: orderType,
      jumlahKerabat: jumlahKerabat,
      scheduleId: widget.scheduleId,
      scheduledDate: widget.scheduledDate,
    );

    if (!mounted) return;
    setState(() => _loading = false);
    if (orderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal membuat pesanan. Silakan coba lagi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    widget.onCreated();

    String jenisPesanan;
    if (orderType == OrderModel.typeKirimBarang) {
      jenisPesanan = 'Saya ingin mengirim barang (terjadwal).';
    } else if (jumlahKerabat == null || jumlahKerabat <= 0) {
      jenisPesanan = 'Saya ingin memesan tiket travel untuk 1 orang.';
    } else {
      jenisPesanan =
          'Saya ingin memesan tiket travel untuk ${1 + jumlahKerabat} orang (dengan kerabat).';
    }

    final message =
        'Halo Pak $driverName,\n\n'
        '$jenisPesanan\n'
        'Untuk tanggal $dateLabel\n\n'
        'Dari: ${widget.origin}\n'
        'Tujuan: ${widget.dest}\n\n'
        'Mohon informasi tarif untuk rute ini.';

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPenumpangScreen(
          orderId: orderId,
          driverUid: driverUid,
          driverName: driverName,
          driverPhotoUrl: driverPhotoUrl,
          driverVerified: widget.item['isVerified'] as bool? ?? false,
          sendJenisPesananMessage: message,
        ),
      ),
    );
  }

  void _showKirimBarangLinkReceiverSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KirimBarangLinkReceiverSheetJadwal(
        driverUid: widget.item['driverUid'] as String? ?? '',
        driverName: (widget.item['driverName'] as String?) ?? 'Driver',
        driverPhotoUrl: widget.item['photoUrl'] as String?,
        scheduleId: widget.scheduleId,
        scheduledDate: widget.scheduledDate,
        origin: widget.origin,
        dest: widget.dest,
        onOrderCreated: (orderId, message) {
          Navigator.pop(ctx);
          widget.onCreated();
          _createAndOpenChatWithOrderId(orderId, message);
        },
        onError: (msg) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _createAndOpenChatWithOrderId(String orderId, String message) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPenumpangScreen(
          orderId: orderId,
          driverUid: widget.item['driverUid'] as String? ?? '',
          driverName: (widget.item['driverName'] as String?) ?? 'Driver',
          driverPhotoUrl: widget.item['photoUrl'] as String?,
          driverVerified: widget.item['isVerified'] as bool? ?? false,
          sendJenisPesananMessage: message,
        ),
      ),
    );
  }

  void _showKerabatDialog() {
    int jumlah = 1;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateD) => AlertDialog(
          title: const Text('Jumlah orang yang ikut'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Berapa orang yang ikut bersama Anda?',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () =>
                        setStateD(() => jumlah = jumlah > 1 ? jumlah - 1 : 1),
                  ),
                  Text(
                    '$jumlah',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => setStateD(() => jumlah = jumlah + 1),
                  ),
                ],
              ),
              Text(
                'Total: ${1 + jumlah} penumpang (Anda + $jumlah orang)',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                'Contoh: Anda + 2 anak → pilih 2 (total 3 penumpang)',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _createAndOpenChat(
                  orderType: OrderModel.typeTravel,
                  jumlahKerabat: jumlah,
                );
              },
              child: const Text('Pesan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxPassengers = (widget.item['maxPassengers'] as num?)?.toInt() ?? 0;
    final dateLabel = _formatScheduledDate(widget.scheduledDate);

    return FutureBuilder<({int totalPenumpang, int kirimBarangCount})>(
      future: OrderService.getScheduledBookingCounts(widget.scheduleId),
      builder: (context, snap) {
        final counts = snap.data ?? (totalPenumpang: 0, kirimBarangCount: 0);
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.all(context.responsive.horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pesan untuk tanggal $dateLabel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Kapasitas: $maxPassengers penumpang. Sudah dipesan: ${counts.totalPenumpang} penumpang. Sudah ${counts.kirimBarangCount} pesanan kirim barang.',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 4),
                Text(
                  'Jumlah penumpang sesuai kapasitas mobil driver.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Pesan Travel Sendiri'),
                  subtitle: const Text(
                    'Pesan untuk perjalanan Anda sendiri (1 orang)',
                  ),
                  onTap: _loading
                      ? null
                      : () => _createAndOpenChat(
                          orderType: OrderModel.typeTravel,
                        ),
                ),
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text('Pesan Travel dengan Kerabat'),
                  subtitle: const Text(
                    'Pesan untuk 2+ orang — Anda + keluarga/teman yang ikut',
                  ),
                  onTap: _loading ? null : _showKerabatDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Kirim Barang'),
                  subtitle: const Text(
                    'Pesan untuk mengirim barang (tidak dihitung penumpang)',
                  ),
                  onTap: _loading ? null : _showKirimBarangLinkReceiverSheet,
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet tautkan penerima untuk Kirim Barang dari Pesan nanti (jadwal).
class _KirimBarangLinkReceiverSheetJadwal extends StatefulWidget {
  final String driverUid;
  final String driverName;
  final String? driverPhotoUrl;
  final String scheduleId;
  final String scheduledDate;
  final String origin;
  final String dest;
  final void Function(String orderId, String message) onOrderCreated;
  final void Function(String message) onError;

  const _KirimBarangLinkReceiverSheetJadwal({
    required this.driverUid,
    required this.driverName,
    this.driverPhotoUrl,
    required this.scheduleId,
    required this.scheduledDate,
    required this.origin,
    required this.dest,
    required this.onOrderCreated,
    required this.onError,
  });

  @override
  State<_KirimBarangLinkReceiverSheetJadwal> createState() =>
      _KirimBarangLinkReceiverSheetJadwalState();
}

class _KirimBarangLinkReceiverSheetJadwalState
    extends State<_KirimBarangLinkReceiverSheetJadwal> {
  final _controller = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _receiver;
  String? _notFound;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cari() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      widget.onError('Masukkan email atau no. telepon penerima.');
      return;
    }
    setState(() {
      _loading = true;
      _receiver = null;
      _notFound = null;
    });
    final result = await OrderService.findUserByEmailOrPhone(input);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _receiver = result;
      _notFound = result == null ? 'User tidak ditemukan.' : null;
    });
  }

  Future<void> _kirimKeDriver() async {
    final receiver = _receiver;
    if (receiver == null) return;
    final uid = receiver['uid'] as String?;
    if (uid == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (uid == user.uid) {
      widget.onError('Penerima tidak boleh sama dengan pengirim.');
      return;
    }
    setState(() => _loading = true);
    String? passengerName;
    String? passengerPhotoUrl;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        passengerName = userDoc.data()!['displayName'] as String?;
        passengerPhotoUrl = userDoc.data()!['photoUrl'] as String?;
      }
    } catch (_) {}
    passengerName ??= user.email ?? 'Penumpang';
    final receiverName = (receiver['displayName'] as String?) ?? 'Penerima';
    final receiverPhotoUrl = receiver['photoUrl'] as String?;
    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: widget.driverUid,
      routeJourneyNumber: OrderService.routeJourneyNumberScheduled,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      originText: widget.origin,
      destText: widget.dest,
      originLat: null,
      originLng: null,
      destLat: null,
      destLng: null,
      orderType: OrderModel.typeKirimBarang,
      receiverUid: uid,
      receiverName: receiverName,
      receiverPhotoUrl: receiverPhotoUrl,
      scheduleId: widget.scheduleId,
      scheduledDate: widget.scheduledDate,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (orderId == null) {
      widget.onError('Gagal membuat pesanan. Silakan coba lagi.');
      return;
    }
    final message =
        'Halo Pak ${widget.driverName},\n\n'
        'Saya ingin mengirim barang (terjadwal).\n\n'
        'Penerima: $receiverName\n'
        'Dari: ${widget.origin}\n'
        'Tujuan: ${widget.dest}\n\n'
        'Mohon informasi biaya pengiriman untuk rute ini.';
    widget.onOrderCreated(orderId, message);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        mediaQuery.viewPadding.bottom + mediaQuery.viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'Kirim Barang – Tautkan Penerima',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan email atau no. telepon penerima (harus terdaftar di Traka). Penerima harus setuju agar pesanan masuk ke driver.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Email atau no. telepon',
                border: const OutlineInputBorder(),
                hintText: 'contoh@email.com atau 08123456789',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.contacts_outlined),
                  tooltip: 'Pilih dari kontak',
                  onPressed: () {
                    showReceiverContactPicker(
                      context: context,
                      onSelect: (phone, receiverData) {
                        _controller.text = phone;
                        setState(() {
                          _receiver = receiverData;
                          _notFound = receiverData == null
                              ? 'Kontak belum terdaftar di Traka.'
                              : null;
                        });
                      },
                    );
                  },
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _cari(),
            ),
            if (_notFound != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _notFound!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (_receiver != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (_receiver!['photoUrl'] as String?) != null &&
                                (_receiver!['photoUrl'] as String).isNotEmpty
                            ? CachedNetworkImageProvider(
                                _receiver!['photoUrl'] as String,
                              )
                            : null,
                    child:
                        (_receiver!['photoUrl'] as String?) == null ||
                                (_receiver!['photoUrl'] as String).isEmpty
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (_receiver!['displayName'] as String?) ?? 'Penerima',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading
                  ? null
                  : () async {
                      if (_receiver != null) {
                        await _kirimKeDriver();
                      } else {
                        await _cari();
                      }
                    },
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_receiver != null ? 'Iya, kirim ke driver' : 'Cari'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Satu halaman daftar jadwal untuk satu tanggal (digunakan di PageView).
class _BuildJadwalListPage extends StatelessWidget {
  final DateTime date;
  final String origin;
  final String dest;
  final Map<String, List<Map<String, dynamic>>> scheduleCache;
  final Map<String, bool> scheduleLoading;
  final Future<void> Function(DateTime) loadSchedules;
  final String Function(DateTime) dateKey;
  final void Function(
    BuildContext,
    Map<String, dynamic>,
    String,
    String,
    String,
    String,
  )
  onPesan;

  const _BuildJadwalListPage({
    required this.date,
    required this.origin,
    required this.dest,
    required this.scheduleCache,
    required this.scheduleLoading,
    required this.loadSchedules,
    required this.dateKey,
    required this.onPesan,
  });

  @override
  Widget build(BuildContext context) {
    final key = dateKey(date);
    final loading = scheduleLoading[key] == true;
    final list = scheduleCache[key];

    if (list == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => loadSchedules(date));
      return const Center(child: CircularProgressIndicator());
    }
    if (loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Tidak ada jadwal untuk tanggal ini',
              style: TextStyle(
                fontSize: context.responsive.fontSize(14),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Coba tanggal lain atau ubah asal/tujuan.',
              style: TextStyle(
                fontSize: context.responsive.fontSize(13),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: context.responsive.horizontalPadding,
        vertical: context.responsive.spacing(8),
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final driverUid = item['driverUid'] as String? ?? '';
        final originText = (item['origin'] as String?) ?? '';
        final destText = (item['destination'] as String?) ?? '';
        final depStamp = item['departureTime'] as Timestamp?;
        final keyStr = dateKey(date);
        final scheduleId =
            '${driverUid}_${keyStr}_${depStamp?.millisecondsSinceEpoch ?? 0}';
        final scheduledDate = keyStr;

        // Gunakan data yang sudah tersedia dari ScheduledDriverRoute jika ada
        final driverNameFromData = item['driverName'] as String?;
        final photoUrlFromData = item['photoUrl'] as String?;

        String timeStr = '–';
        if (depStamp != null) {
          final dt = depStamp.toDate();
          timeStr =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        final maxPassengers = (item['maxPassengers'] as num?)?.toInt() ?? 0;

        Widget buildCard(String driverName, String? photoUrl, {bool? verified}) {
          return FutureBuilder<({int totalPenumpang, int kirimBarangCount})>(
            future: OrderService.getScheduledBookingCounts(scheduleId),
            builder: (context, snapCounts) {
              final counts =
                  snapCounts.data ?? (totalPenumpang: 0, kirimBarangCount: 0);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
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
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              driverName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (verified ?? item['isVerified'] == true) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: Colors.green.shade700,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Dari: ${_formatAlamatKecamatanKabupaten(originText)}',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Tujuan: ${_formatAlamatKecamatanKabupaten(destText)}',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Jam: $timeStr',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.responsive.spacing(16),
                        0,
                        context.responsive.spacing(16),
                        context.responsive.spacing(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kapasitas: $maxPassengers penumpang. Sudah dipesan: ${counts.totalPenumpang} penumpang. Sudah ${counts.kirimBarangCount} pesanan kirim barang.',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(12),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: context.responsive.spacing(4)),
                          Text(
                            'Jumlah penumpang sesuai kapasitas mobil driver.',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(11),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.responsive.spacing(16),
                        0,
                        context.responsive.spacing(16),
                        context.responsive.spacing(12),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => onPesan(
                            context,
                            item,
                            scheduleId,
                            scheduledDate,
                            origin,
                            dest,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text('Pesan'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        if (driverNameFromData != null && driverNameFromData.isNotEmpty) {
          return buildCard(
            driverNameFromData,
            photoUrlFromData,
            verified: item['isVerified'] == true,
          );
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: ChatService.getUserInfo(driverUid),
          builder: (context, snap) {
            final info = snap.data;
            final driverName =
                (info?['displayName'] as String?)?.isNotEmpty == true
                ? (info!['displayName'] as String)
                : 'Driver';
            final photoUrl = info?['photoUrl'] as String?;
            final verified = info?['verified'] == true;
            return buildCard(driverName, photoUrl, verified: verified);
          },
        );
      },
    );
  }
}

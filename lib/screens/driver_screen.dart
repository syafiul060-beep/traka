import 'dart:async';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../models/order_model.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/province_island.dart';
import '../theme/responsive.dart';
import '../utils/placemark_formatter.dart';
import '../services/directions_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/driver_status_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../services/order_service.dart';
import '../services/route_background_handler.dart';
import '../services/route_journey_number_service.dart';
import '../services/route_persistence_service.dart';
import '../services/route_utils.dart';
import '../services/route_session_service.dart';
import '../services/driver_contribution_service.dart';
import '../services/driver_transfer_service.dart';
import '../services/verification_service.dart';
import '../services/trip_service.dart';
import '../widgets/driver_contact_picker.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/promotion_banner_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_list_driver_screen.dart';
import 'contribution_driver_screen.dart';
import 'data_order_driver_screen.dart';
import 'driver_jadwal_rute_screen.dart';
import 'profile_driver_screen.dart';

/// Tipe rute: dalam provinsi, antar provinsi, dalam negara.
enum RouteType { dalamProvinsi, antarProvinsi, dalamNegara }

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  int _currentIndex = 0;
  GoogleMapController? _mapController;
  MapType _mapType = MapType.hybrid; // Default: satelit dengan label
  Position? _currentPosition;
  Timer? _locationRefreshTimer;

  // Lokasi driver (reverse geocode) untuk form asal
  String _originLocationText = 'Mengambil lokasi...';
  String? _currentProvinsi;

  // Status kerja: true = sedang kerja (tombol merah), false = siap kerja (tombol hijau)
  bool _isDriverWorking = false;
  // Rute saat ini
  LatLng? _routeOriginLatLng;
  String _routeOriginText = '';
  LatLng? _routeDestLatLng;
  String _routeDestText = '';
  List<LatLng>? _routePolyline;
  String _routeDistanceText = '';
  String _routeDurationText = '';
  // Jarak dan estimasi waktu dinamis berdasarkan posisi driver saat ini
  String _currentDistanceText = '';
  String _currentDurationText = '';
  // Alternatif rute untuk dipilih driver
  List<DirectionsResult> _alternativeRoutes = [];
  int _selectedRouteIndex = -1; // Index rute yang dipilih (-1 = belum dipilih)
  bool _routeSelected =
      false; // Apakah driver sudah memilih rute dari alternatif
  bool _activeRouteFromJadwal =
      false; // True jika rute aktif berasal dari halaman Jadwal & Rute
  /// ID jadwal yang dijalankan (untuk sinkron pesanan terjadwal dengan Data Order).
  String? _currentScheduleId;
  // Tracking untuk auto-switch rute
  DateTime? _lastRouteSwitchTime; // Waktu terakhir switch rute
  int _originalRouteIndex = -1; // Index rute awal sebelum auto-switch
  DateTime? _destinationReachedAt;
  static const Duration _autoEndDuration = Duration(hours: 1, minutes: 30);
  static const double _atDestinationMeters = 500;
  // Nomor rute perjalanan (unik), waktu mulai rute, estimasi durasi untuk auto-end
  String? _routeJourneyNumber;
  DateTime? _routeStartedAt;
  int? _routeEstimatedDurationSeconds;
  static const int _minMinutesBeforeEndWork =
      15; // driver boleh selesai bekerja setelah 15 menit (jika belum dapat penumpang)
  // Rute terakhir (untuk opsi "Putar Arah" saat tombol hijau dan driver masih di tujuan)
  LatLng? _lastRouteOriginLatLng;
  LatLng? _lastRouteDestLatLng;
  String _lastRouteOriginText = '';
  String _lastRouteDestText = '';

  // Tracking update lokasi ke Firestore (efisien: jika pindah 1.5 km atau per 12 menit)
  Position? _lastUpdatedPosition;
  DateTime? _lastUpdatedTime;

  // Icon mobil untuk marker lokasi driver
  BitmapDescriptor? _carIconBitmap;
  double? _lastCarIconBearing; // Bearing terakhir untuk icon mobil
  Position?
  _positionWhenStarted; // Posisi saat mulai bekerja (untuk deteksi pergerakan)
  bool _hasMovedAfterStart =
      false; // Apakah lokasi sudah bergerak setelah mulai bekerja
  Position?
  _lastPositionForMovement; // Posisi terakhir untuk deteksi pergerakan real-time

  // Long press detection untuk pilih rute alternatif
  // Badge chat: jumlah order dengan pesan belum dibaca driver
  StreamSubscription<List<OrderModel>>? _driverOrdersSub;
  List<OrderModel> _driverOrders = [];
  final Map<String, BitmapDescriptor> _passengerMarkerIcons = {};
  int _chatUnreadCount = 0;
  int _jumlahPenumpang = 0;
  int _jumlahBarang = 0;
  /// Jumlah penumpang yang sudah dijemput (picked_up) - untuk enable tombol Oper Driver.
  int _jumlahPenumpangPickedUp = 0;

  /// Informasi rute (jarak, jumlah penumpang/barang): true = tampil, false = sembunyi (bisa diklik untuk toggle).
  bool _routeInfoPanelExpanded = true;

  // State untuk tracking active order (agreed/picked_up) - travel atau kirim_barang
  bool _hasActiveOrder = false;

  // Koordinasi form tujuan dengan peta utama (seperti penumpang: map utama bergerak ke lokasi pilihan)
  final ValueNotifier<bool> _formDestMapModeNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<LatLng?> _formDestMapTapNotifier = ValueNotifier<LatLng?>(
    null,
  );
  final ValueNotifier<LatLng?> _formDestPreviewNotifier =
      ValueNotifier<LatLng?>(null);

  /// Mode navigasi ke penumpang: driver klik "Ya, arahkan" → tetap di Beranda, rute ke penumpang di peta.
  /// Setelah scan/konfirmasi otomatis, kembali ke rute utama.
  String? _navigatingToOrderId;
  List<LatLng>? _polylineToPassenger;
  String _routeToPassengerDistanceText = '';
  String _routeToPassengerDurationText = '';
  double? _lastPassengerLat;
  double? _lastPassengerLng;

  @override
  void initState() {
    super.initState();
    _loadCarIcon(); // Load icon mobil saat init
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _driverOrdersSub = OrderService.streamOrdersForDriver(uid).listen((
        orders,
      ) {
        if (!mounted) return;
        int count = 0;
        bool hasActive = false;
        int penumpang = 0;
        int barang = 0;
        int penumpangPickedUp = 0;
        for (final o in orders) {
          // Hitung unread chat
          if (o.lastMessageAt != null &&
              o.lastMessageSenderUid != uid &&
              (o.driverLastReadAt == null ||
                  o.lastMessageAt!.isAfter(o.driverLastReadAt!))) {
            count++;
          }
          // Hanya order agreed atau picked_up (belum selesai)
          final isActive =
              o.status == OrderService.statusAgreed ||
              o.status == OrderService.statusPickedUp;
          if (isActive &&
              (o.orderType == OrderModel.typeTravel ||
                  o.orderType == OrderModel.typeKirimBarang)) {
            hasActive = true;
            if (o.orderType == OrderModel.typeTravel) {
              penumpang++;
              if (o.status == OrderService.statusPickedUp) penumpangPickedUp++;
            } else {
              barang++;
            }
          }
        }
        // Mode navigasi ke penumpang: cek jika order sudah dijemput atau lokasi penumpang berubah
        final navId = _navigatingToOrderId;
        if (navId != null) {
          OrderModel? navOrder;
          for (final o in orders) {
            if (o.id == navId) {
              navOrder = o;
              break;
            }
          }
          if (navOrder != null) {
            if (navOrder.hasDriverScannedPassenger) {
              // Penumpang sudah dijemput → kembali ke rute utama
              if (mounted) {
                setState(() {
                  _navigatingToOrderId = null;
                  _polylineToPassenger = null;
                  _routeToPassengerDistanceText = '';
                  _routeToPassengerDurationText = '';
                  _lastPassengerLat = null;
                  _lastPassengerLng = null;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Penumpang sudah dijemput. Kembali ke rute.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } else if (navOrder.passengerLat != null &&
                navOrder.passengerLng != null &&
                (_lastPassengerLat != navOrder.passengerLat ||
                    _lastPassengerLng != navOrder.passengerLng)) {
              // Lokasi penumpang berubah → refetch rute
              _lastPassengerLat = navOrder.passengerLat;
              _lastPassengerLng = navOrder.passengerLng;
              _fetchAndShowRouteToPassenger(navOrder);
            }
          }
        }
        setState(() {
          _driverOrders = orders;
          _chatUnreadCount = count;
          _hasActiveOrder = hasActive;
          _jumlahPenumpang = penumpang;
          _jumlahBarang = barang;
          _jumlahPenumpangPickedUp = penumpangPickedUp;
        });
        _loadPassengerMarkerIconsIfNeeded();
      });
    }
    // Tampilkan lokasi cache dulu (cepat), lalu lokasi akurat di background
    Future.microtask(() async {
      if (!mounted) return;
      final cached = await LocationService.getCachedPosition();
      if (cached != null && mounted) {
        setState(() => _currentPosition = cached);
        _updateLocationText(cached);
        if (_mapController != null && mounted) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(cached.latitude, cached.longitude),
              14.0,
            ),
          );
        }
      }
      if (!mounted) return;
      // Lokasi akurat (bisa lama di HP tertentu) – delay singkat agar UI sempat tampil
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _getCurrentLocation();
      });
    });
    _tryRestoreActiveRoute();
    _formDestPreviewNotifier.addListener(_onFormDestPreviewChanged);
    _formDestMapModeNotifier.addListener(_onFormDestPreviewChanged);
    // Refresh lokasi setiap 30 detik (hemat baterai & data; Firestore tetap update via shouldUpdateLocation)
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) async {
      _getCurrentLocation(forTracking: true);
      if (_isDriverWorking &&
          _routeDestLatLng != null &&
          _currentPosition != null) {
        _checkDestinationAndAutoEnd();
      }
      if (_isDriverWorking &&
          _routeJourneyNumber != null &&
          _routeStartedAt != null &&
          _routeEstimatedDurationSeconds != null) {
        await _checkAutoEndByEstimatedTime();
      }
    });
  }

  void _onFormDestPreviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _formDestPreviewNotifier.removeListener(_onFormDestPreviewChanged);
    _formDestMapModeNotifier.removeListener(_onFormDestPreviewChanged);
    _driverOrdersSub?.cancel();
    _locationRefreshTimer?.cancel();
    _mapController?.dispose();
    RouteBackgroundHandler.unregister();
    // Hapus status driver dari Firestore saat screen dispose (agar driver tidak tampil siap kerja).
    DriverStatusService.removeDriverStatus();
    // Jangan clear RoutePersistenceService di dispose - agar rute bisa direstore
    // saat app dibuka kembali. Origin/dest dari jadwal tetap dipakai (tidak ikut lokasi driver).
    super.dispose();
  }

  void _registerRouteBackgroundHandler() {
    RouteBackgroundHandler.register(
      onEndRoute: _endWork,
      onShowSnackBar: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      onPersistRequest: _updateBackgroundSince,
    );
  }

  /// Simpan rute ke disk (dipanggil saat rute aktif, agar tetap ada jika app ditutup paksa)
  Future<void> _persistCurrentRoute() async {
    if (_routeOriginLatLng == null || _routeDestLatLng == null) return;
    await RoutePersistenceService.save(
      originLat: _routeOriginLatLng!.latitude,
      originLng: _routeOriginLatLng!.longitude,
      destLat: _routeDestLatLng!.latitude,
      destLng: _routeDestLatLng!.longitude,
      originText: _routeOriginText,
      destText: _routeDestText,
      fromJadwal: _activeRouteFromJadwal,
      selectedRouteIndex: _selectedRouteIndex >= 0 ? _selectedRouteIndex : 0,
      backgroundSince: null,
    );
  }

  /// Update timestamp background (dipanggil saat app ke background)
  Future<void> _updateBackgroundSince() async {
    await RoutePersistenceService.updateBackgroundSince(DateTime.now());
  }

  /// Restore rute kerja aktif: prioritas Firestore (sumber utama), fallback SharedPreferences.
  Future<void> _tryRestoreActiveRoute() async {
    double? originLat;
    double? originLng;
    double? destLat;
    double? destLng;
    String originText = '';
    String destText = '';
    bool? fromJadwal;
    int savedRouteIndex = 0;

    // 1. Cek Firestore dulu (rute aktif tersimpan saat driver set rute; tetap ada meski app ditutup)
    final firestoreRoute =
        await DriverStatusService.getActiveRouteFromFirestore();
    if (firestoreRoute != null) {
      originLat = firestoreRoute.originLat;
      originLng = firestoreRoute.originLng;
      destLat = firestoreRoute.destLat;
      destLng = firestoreRoute.destLng;
      originText = firestoreRoute.originText;
      destText = firestoreRoute.destText;
      fromJadwal = firestoreRoute.routeFromJadwal;
      savedRouteIndex = firestoreRoute.routeSelectedIndex;
    }

    // 2. Fallback: SharedPreferences (jika Firestore belum sempat ter-update)
    PersistedRoute? persisted;
    if (originLat == null ||
        originLng == null ||
        destLat == null ||
        destLng == null) {
      persisted = await RoutePersistenceService.load();
      if (persisted == null || !mounted) return;
      originLat = persisted.originLat;
      originLng = persisted.originLng;
      destLat = persisted.destLat;
      destLng = persisted.destLng;
      originText = persisted.originText;
      destText = persisted.destText;
      fromJadwal = persisted.fromJadwal;
      savedRouteIndex = persisted.selectedRouteIndex;
    }

    if (!mounted) return;
    final oLat = originLat;
    final oLng = originLng;
    final dLat = destLat;
    final dLng = destLng;

    // Ambil semua alternatif rute
    final alternatives = await DirectionsService.getAlternativeRoutes(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
    );
    if (!mounted || alternatives.isEmpty) return;

    // Restore rute yang dulu dipilih (bukan selalu index 0)
    final selectedIndex = savedRouteIndex.clamp(0, alternatives.length - 1);
    final selectedRoute = alternatives[selectedIndex];
    String? journeyNumber;
    if (firestoreRoute != null) {
      journeyNumber = firestoreRoute.routeJourneyNumber;
    }
    if (journeyNumber == null || journeyNumber.isEmpty) {
      journeyNumber =
          await RouteJourneyNumberService.generateRouteJourneyNumber();
    }
    if (!mounted) return;
    final startedAt = DateTime.now();

    setState(() {
      _routeOriginLatLng = LatLng(oLat, oLng);
      _routeDestLatLng = LatLng(dLat, dLng);
      _routeOriginText = originText;
      _routeDestText = destText;
      _routePolyline = selectedRoute.points;
      _routeDistanceText = selectedRoute.distanceText;
      _routeDurationText = selectedRoute.durationText;
      _alternativeRoutes = alternatives;
      _selectedRouteIndex = selectedIndex;
      _routeSelected = true; // Restore berarti sudah dipilih sebelumnya
      _originalRouteIndex = selectedIndex; // Set rute awal saat restore
      _lastRouteSwitchTime = null; // Reset waktu switch
      _isDriverWorking = true;
      _destinationReachedAt = null;
      _routeJourneyNumber = journeyNumber;
      _routeStartedAt = firestoreRoute?.routeStartedAt ?? startedAt;
      _routeEstimatedDurationSeconds =
          firestoreRoute?.estimatedDurationSeconds ??
          selectedRoute.durationSeconds;
      _activeRouteFromJadwal = fromJadwal ?? false;
      // Saat restore, asumsikan sudah bergerak (pakai icon hijau)
      _hasMovedAfterStart = true;
      _positionWhenStarted = _currentPosition;
    });

    // Load icon hijau karena restore berarti sudah bekerja sebelumnya
    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      await _loadCarIcon(
        bearing: _currentPosition!.heading,
        iconColor: 'hijau',
      );
      _lastCarIconBearing = _currentPosition!.heading;
    } else {
      await _loadCarIcon(iconColor: 'hijau');
    }

    _registerRouteBackgroundHandler();
    _persistCurrentRoute();
    // Tulis driver_status ke Firestore agar penumpang bisa menemukan driver (penting setelah ganti project id.traka.app).
    if (_currentPosition != null) {
      _updateDriverStatusToFirestore(_currentPosition!);
    } else {
      // Lokasi belum siap; update nanti saat _getCurrentLocation selesai (shouldUpdateLocation true saat lastUpdated null).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final pos = _currentPosition;
        if (pos != null && _isDriverWorking) {
          await _updateDriverStatusToFirestore(pos);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRouteBounds();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rute tujuan anda masih aktif. Waktu diperpanjang 1 jam.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _getCurrentLocation({bool forTracking = false}) async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) return;

    // Pastikan GPS aktif - retry beberapa kali jika belum aktif
    // Retry lebih banyak untuk kompatibilitas HP China yang mungkin memerlukan waktu lebih lama
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Retry 4 kali dengan delay progresif untuk memastikan GPS aktif di berbagai HP Android
      for (int retry = 0; retry < 4; retry++) {
        await Future.delayed(Duration(milliseconds: 600 * (retry + 1)));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) break;
      }
      if (!serviceEnabled) return;
    }

    try {
      // Retry maksimal 3 kali untuk kompatibilitas HP China yang mungkin memerlukan waktu lebih lama
      Position? position;
      for (int retry = 0; retry < 3; retry++) {
        final result = await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: retry == 0,
          forTracking: forTracking,
        );
        // Fake GPS terdeteksi: tampilkan overlay full-screen, blokir penggunaan
        if (result.isFakeGpsDetected) {
          if (mounted) FakeGpsOverlayService.showOverlay();
          return;
        }
        position = result.position;
        if (position != null) break;
        if (retry < 2) {
          // Tunggu lebih lama sebelum retry untuk HP yang lebih lambat
          await Future.delayed(Duration(milliseconds: 1500 * (retry + 1)));
        }
      }

      if (position == null) {
        // Jika semua retry gagal, coba sekali lagi dengan forceRefresh dan delay lebih lama
        await Future.delayed(const Duration(milliseconds: 2000));
        final result = await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: true,
          forTracking: forTracking,
        );
        if (result.isFakeGpsDetected) {
          if (mounted) FakeGpsOverlayService.showOverlay();
          return;
        }
        position = result.position;
      }

      if (position != null && mounted) {
        final previousPosition = _currentPosition;
        setState(() => _currentPosition = position);

        await _updateLocationText(position);

        // Deteksi pergerakan real-time: merah = diam, hijau = bergerak
        bool isMoving = false;
        if (_isDriverWorking) {
          if (_lastPositionForMovement != null) {
            // Hitung jarak dari posisi sebelumnya
            final distance = Geolocator.distanceBetween(
              _lastPositionForMovement!.latitude,
              _lastPositionForMovement!.longitude,
              position.latitude,
              position.longitude,
            );
            // Jika bergerak lebih dari 5 meter, dianggap sedang bergerak
            isMoving = distance > 5;
          } else {
            // Jika belum ada posisi sebelumnya, cek dari posisi saat mulai bekerja
            if (_positionWhenStarted != null) {
              final distance = Geolocator.distanceBetween(
                _positionWhenStarted!.latitude,
                _positionWhenStarted!.longitude,
                position.latitude,
                position.longitude,
              );
              isMoving =
                  distance > 10; // Threshold lebih besar untuk deteksi awal
            }
          }

          // Update icon berdasarkan status pergerakan
          final targetIconColor = isMoving ? 'hijau' : 'merah';
          final currentIconColor = _hasMovedAfterStart ? 'hijau' : 'merah';

          // Update icon jika status pergerakan berubah atau bearing berubah
          if (targetIconColor != currentIconColor ||
              (isMoving &&
                  position.heading.isFinite &&
                  (_lastCarIconBearing == null ||
                      (position.heading - _lastCarIconBearing!).abs() > 5))) {
            setState(() {
              _hasMovedAfterStart = isMoving;
            });

            if (isMoving && position.heading.isFinite) {
              await _loadCarIcon(bearing: position.heading, iconColor: 'hijau');
              _lastCarIconBearing = position.heading;
            } else {
              await _loadCarIcon(iconColor: targetIconColor);
            }
          }

          // Update posisi terakhir untuk deteksi pergerakan berikutnya
          _lastPositionForMovement = position;
        }

        // Update jarak dan estimasi waktu dinamis dari posisi driver saat ini ke tujuan
        if (_isDriverWorking && _routeDestLatLng != null) {
          await _updateCurrentDistanceAndDuration(position);
        }

        // Cek auto-switch rute jika driver sedang bekerja dan ada alternatif rute
        if (_isDriverWorking &&
            _alternativeRoutes.isNotEmpty &&
            _routeSelected &&
            _selectedRouteIndex >= 0) {
          await _checkAndAutoSwitchRoute(position);
        }

        // Update status & lokasi ke Firestore agar penumpang bisa menemukan driver (penting setelah ganti project).
        // Update jika: belum pernah tulis this session (_lastUpdatedTime null) atau sudah waktunya (jarak/waktu).
        if (_isDriverWorking &&
            (_lastUpdatedTime == null || _shouldUpdateFirestore(position))) {
          await _updateDriverStatusToFirestore(position);
        }

        // Fokus kamera ke icon mobil saat bergerak
        if (_mapController != null && mounted) {
          if (_isDriverWorking && isMoving) {
            // Saat driver bekerja dan mobil bergerak, selalu fokus kamera ke posisi mobil
            if (position.heading.isFinite) {
              // Gunakan bearing untuk rotasi kamera mengikuti arah mobil
              _mapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(position.latitude, position.longitude),
                    bearing: position.heading,
                    tilt: 0,
                    zoom: 16.0, // Zoom level yang nyaman untuk tracking mobil
                  ),
                ),
              );
            } else {
              // Jika tidak ada bearing, cukup update posisi
              _mapController!.animateCamera(
                CameraUpdate.newLatLng(
                  LatLng(position.latitude, position.longitude),
                ),
              );
            }
          } else if (previousPosition == null) {
            // Inisialisasi pertama kali: zoom ke posisi driver
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(position.latitude, position.longitude),
                15.0,
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  /// Update jarak dan estimasi waktu dari posisi driver saat ini ke tujuan
  Future<void> _updateCurrentDistanceAndDuration(Position position) async {
    if (_routeDestLatLng == null) return;

    try {
      final result = await DirectionsService.getRoute(
        originLat: position.latitude,
        originLng: position.longitude,
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
      );

      if (result != null && mounted) {
        setState(() {
          _currentDistanceText = result.distanceText;
          _currentDurationText = result.durationText;
        });
      }
    } catch (_) {
      // Jika gagal, gunakan jarak langsung (straight line distance)
      if (mounted) {
        final distanceMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _routeDestLatLng!.latitude,
          _routeDestLatLng!.longitude,
        );
        final distanceKm = distanceMeters / 1000;
        setState(() {
          _currentDistanceText = '${distanceKm.toStringAsFixed(1)} km';
          // Estimasi waktu kasar: asumsi kecepatan rata-rata 60 km/jam
          final estimatedHours = distanceKm / 60;
          if (estimatedHours < 1) {
            final minutes = (estimatedHours * 60).round();
            _currentDurationText = '$minutes mins';
          } else {
            final hours = estimatedHours.floor();
            final minutes = ((estimatedHours - hours) * 60).round();
            _currentDurationText = hours > 0 && minutes > 0
                ? '$hours hours $minutes mins'
                : hours > 0
                ? '$hours hours'
                : '$minutes mins';
          }
        });
      }
    }
  }

  /// Cek dan auto-switch rute jika driver berada di rute alternatif lain.
  /// Syarat: driver berada dalam 10 km dan 15 menit dari rute alternatif lain.
  /// Jika driver kembali ke rute awal dalam 10 km dan 15 menit, switch kembali.
  Future<void> _checkAndAutoSwitchRoute(Position position) async {
    if (_alternativeRoutes.isEmpty || _selectedRouteIndex < 0) return;

    try {
      final driverPos = LatLng(position.latitude, position.longitude);
      final now = DateTime.now();

      // Konversi alternatif rute ke List<List<LatLng>> untuk RouteUtils
      final alternativePolylines = _alternativeRoutes
          .map((r) => r.points)
          .toList();

      // Cari rute terdekat dari posisi driver saat ini
      final nearestRouteIndex = RouteUtils.findNearestRouteIndex(
        driverPos,
        alternativePolylines,
        toleranceMeters: 10000, // 10 km
      );

      // Jika tidak ada rute dalam toleransi, tidak perlu switch
      if (nearestRouteIndex < 0) return;

      // Jika rute terdekat berbeda dengan rute yang dipilih saat ini
      if (nearestRouteIndex != _selectedRouteIndex) {
        // Cek apakah sudah lebih dari 15 menit sejak switch terakhir
        final canSwitch =
            _lastRouteSwitchTime == null ||
            now.difference(_lastRouteSwitchTime!) >=
                const Duration(minutes: 15);

        if (canSwitch) {
          // Simpan index rute awal jika belum pernah switch
          if (_originalRouteIndex < 0) {
            _originalRouteIndex = _selectedRouteIndex;
          }

          // Switch ke rute terdekat
          if (mounted) {
            setState(() {
              _selectedRouteIndex = nearestRouteIndex;
              _routePolyline = _alternativeRoutes[nearestRouteIndex].points;
              _lastRouteSwitchTime = now;
            });

            // Update Firestore dengan rute baru
            await DriverStatusService.updateDriverStatus(
              status: DriverStatusService.statusSiapKerja,
              position: position,
              routeOrigin: _routeOriginLatLng,
              routeDestination: _routeDestLatLng,
              routeOriginText: _routeOriginText,
              routeDestinationText: _routeDestText,
              routeJourneyNumber: _routeJourneyNumber,
              routeStartedAt: _routeStartedAt,
              estimatedDurationSeconds: _routeEstimatedDurationSeconds,
              routeFromJadwal: _activeRouteFromJadwal,
              routeSelectedIndex: _selectedRouteIndex,
            );

            if (kDebugMode) debugPrint('DriverScreen: Auto-switch ke rute index $nearestRouteIndex');
          }
        }
      } else if (_originalRouteIndex >= 0 &&
          nearestRouteIndex == _originalRouteIndex &&
          _selectedRouteIndex != _originalRouteIndex) {
        // Jika driver kembali ke rute awal, cek apakah sudah 15 menit
        final canSwitchBack =
            _lastRouteSwitchTime == null ||
            now.difference(_lastRouteSwitchTime!) >=
                const Duration(minutes: 15);

        if (canSwitchBack) {
          // Switch kembali ke rute awal
          if (mounted) {
            setState(() {
              _selectedRouteIndex = _originalRouteIndex;
              _routePolyline = _alternativeRoutes[_originalRouteIndex].points;
              _lastRouteSwitchTime = now;
              _originalRouteIndex =
                  -1; // Reset karena sudah kembali ke rute awal
            });

            // Update Firestore dengan rute awal
            await DriverStatusService.updateDriverStatus(
              status: DriverStatusService.statusSiapKerja,
              position: position,
              routeOrigin: _routeOriginLatLng,
              routeDestination: _routeDestLatLng,
              routeOriginText: _routeOriginText,
              routeDestinationText: _routeDestText,
              routeJourneyNumber: _routeJourneyNumber,
              routeStartedAt: _routeStartedAt,
              estimatedDurationSeconds: _routeEstimatedDurationSeconds,
              routeFromJadwal: _activeRouteFromJadwal,
              routeSelectedIndex: _selectedRouteIndex,
            );

            if (kDebugMode) debugPrint('DriverScreen: Auto-switch kembali ke rute awal index $_originalRouteIndex');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DriverScreen._checkAndAutoSwitchRoute error: $e');
    }
  }

  Future<void> _updateLocationText(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final prov = place.administrativeArea ?? '';
        setState(() {
          _currentProvinsi = prov.isNotEmpty ? prov : null;
          _originLocationText = _formatPlacemarkShort(place);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _originLocationText =
              '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
        );
      }
    }
  }

  String _formatPlacemarkShort(Placemark place) =>
      PlacemarkFormatter.formatShort(place);

  /// Cek apakah perlu update lokasi ke Firestore (jika pindah 1.5 km atau sudah 12 menit).
  bool _shouldUpdateFirestore(Position currentPosition) {
    return DriverStatusService.shouldUpdateLocation(
      currentPosition: currentPosition,
      lastUpdatedPosition: _lastUpdatedPosition,
      lastUpdatedTime: _lastUpdatedTime,
    );
  }

  /// Auto-end pekerjaan jika waktu estimasi sudah lewat dan driver belum dapat penumpang.
  Future<void> _checkAutoEndByEstimatedTime() async {
    if (_routeStartedAt == null || _routeEstimatedDurationSeconds == null) {
      return;
    }
    final elapsed = DateTime.now().difference(_routeStartedAt!).inSeconds;
    if (elapsed < _routeEstimatedDurationSeconds!) return;
    final count = await OrderService.countActiveOrdersForRoute(
      _routeJourneyNumber!,
    );
    if (count > 0) return;
    if (!mounted) return;
    _endWork();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Waktu estimasi perjalanan telah habis. Pekerjaan diakhiri otomatis.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  /// Update status dan lokasi driver ke Firestore.
  Future<void> _updateDriverStatusToFirestore(Position position) async {
    try {
      int? passengerCount;
      if (_isDriverWorking &&
          _routeJourneyNumber != null &&
          _routeJourneyNumber!.isNotEmpty) {
        if (_routeJourneyNumber == OrderService.routeJourneyNumberScheduled &&
            _currentScheduleId != null &&
            _currentScheduleId!.isNotEmpty) {
          final counts = await OrderService.getScheduledBookingCounts(
            _currentScheduleId!,
          );
          passengerCount = counts.totalPenumpang;
        } else {
          passengerCount = await OrderService.countActiveOrdersForRoute(
            _routeJourneyNumber!,
          );
        }
      }
      await DriverStatusService.updateDriverStatus(
        status: _isDriverWorking
            ? DriverStatusService.statusSiapKerja
            : DriverStatusService.statusTidakAktif,
        position: position,
        routeOrigin: _routeOriginLatLng,
        routeDestination: _routeDestLatLng,
        routeOriginText: _routeOriginText,
        routeDestinationText: _routeDestText,
        routeJourneyNumber: _routeJourneyNumber,
        routeStartedAt: _routeStartedAt,
        estimatedDurationSeconds: _routeEstimatedDurationSeconds,
        currentPassengerCount: passengerCount,
        routeFromJadwal: _activeRouteFromJadwal,
        routeSelectedIndex: _selectedRouteIndex >= 0 ? _selectedRouteIndex : 0,
        scheduleId: _activeRouteFromJadwal ? _currentScheduleId : null,
      );
      // Update tracking untuk pengecekan berikutnya
      setState(() {
        _lastUpdatedPosition = position;
        _lastUpdatedTime = DateTime.now();
      });
    } catch (_) {
      // Gagal update ke Firestore - tidak perlu tampilkan error, coba lagi nanti
    }
  }

  void _checkDestinationAndAutoEnd() {
    if (_routeDestLatLng == null || _currentPosition == null) return;
    final dist = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _routeDestLatLng!.latitude,
      _routeDestLatLng!.longitude,
    );
    if (dist <= _atDestinationMeters) {
      final now = DateTime.now();
      _destinationReachedAt ??= now;
      if (now.difference(_destinationReachedAt!) >= _autoEndDuration) {
        _endWork();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pekerjaan diakhiri otomatis. Anda sudah sampai tujuan lebih dari 1,5 jam.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {});
      }
    } else {
      setState(() => _destinationReachedAt = null);
    }
  }

  Future<void> _endWork() async {
    // Simpan nilai untuk dipakai setelah setState (sebelum di-clear)
    final journeyNumber = _routeJourneyNumber;
    final scheduleId = _currentScheduleId;
    final originText = _routeOriginText;
    final destText = _routeDestText;
    final originLatLng = _routeOriginLatLng;
    final destLatLng = _routeDestLatLng;
    final startedAt = _routeStartedAt;
    final currentPos = _currentPosition;

    // Update UI dulu agar tombol langsung jadi "Siap Kerja" (jangan tunggu async)
    if (!mounted) return;
    RouteBackgroundHandler.unregister();
    RoutePersistenceService.clear();
    setState(() {
      if (_routeOriginLatLng != null && _routeDestLatLng != null) {
        _lastRouteOriginLatLng = _routeOriginLatLng;
        _lastRouteDestLatLng = _routeDestLatLng;
        _lastRouteOriginText = _routeOriginText;
        _lastRouteDestText = _routeDestText;
      }
      _isDriverWorking = false;
      _routePolyline = null;
      _routeOriginLatLng = null;
      _routeDestLatLng = null;
      _routeOriginText = '';
      _routeDestText = '';
      _routeDistanceText = '';
      _currentScheduleId = null;
      _routeDurationText = '';
      _destinationReachedAt = null;
      _routeJourneyNumber = null;
      _routeStartedAt = null;
      _routeEstimatedDurationSeconds = null;
      _alternativeRoutes = [];
      _selectedRouteIndex = -1;
      _routeSelected = false;
      _originalRouteIndex = -1;
      _lastRouteSwitchTime = null;
      _carIconBitmap = null;
      _lastCarIconBearing = null;
      _positionWhenStarted = null;
      _hasMovedAfterStart = false;
      _lastPositionForMovement = null;
      _activeRouteFromJadwal = false;
    });

    // Update status ke Firestore: tidak aktif (supaya penumpang tidak lihat driver aktif)
    if (currentPos != null) {
      _updateDriverStatusToFirestore(currentPos);
    }

    // Simpan sesi & riwayat (Riwayat Rute) setiap kali driver Selesai Bekerja.
    // Disimpan bahkan tanpa koordinat agar riwayat tetap muncul (rute awal–akhir + tanggal).
    try {
      final effectiveOrigin =
          (originText != null && originText.trim().isNotEmpty)
              ? originText.trim()
              : 'Lokasi awal';
      final effectiveDest =
          (destText != null && destText.trim().isNotEmpty)
              ? destText.trim()
              : 'Tujuan';
      await RouteSessionService.saveCurrentRouteSession(
        routeJourneyNumber: journeyNumber ?? '',
        scheduleId: scheduleId,
        routeOriginText: effectiveOrigin,
        routeDestText: effectiveDest,
        routeOriginLat: originLatLng?.latitude,
        routeOriginLng: originLatLng?.longitude,
        routeDestLat: destLatLng?.latitude,
        routeDestLng: destLatLng?.longitude,
        routeStartedAt: startedAt,
      );
      if (originLatLng != null && destLatLng != null) {
        await TripService.saveCompletedTrip(
          routeOriginLat: originLatLng.latitude,
          routeOriginLng: originLatLng.longitude,
          routeDestLat: destLatLng.latitude,
          routeDestLng: destLatLng.longitude,
          routeOriginText: effectiveOrigin,
          routeDestText: effectiveDest,
          routeJourneyNumber: journeyNumber,
          routeStartedAt: startedAt,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Riwayat rute disimpan sebagian. ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onToggleButtonTap({bool isDriverVerified = true}) async {
    HapticFeedback.mediumImpact();
    // Jika ada alternatif rute tapi belum dipilih, tidak bisa mulai bekerja
    if (_alternativeRoutes.isNotEmpty && !_routeSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih rute yang diinginkan di map terlebih dahulu dengan tap pada polyline rute.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Tombol "Mulai" akan menangani mulai bekerja (lihat method _onStartButtonTap)

    if (_isDriverWorking) {
      // Jika masih ada penumpang/barang (agreed atau picked_up), tidak boleh berhenti bekerja
      if (_hasActiveOrder) {
        String msg;
        if (_jumlahPenumpang > 0 && _jumlahBarang > 0) {
          msg =
              'Tidak bisa berhenti bekerja. Masih ada $_jumlahPenumpang penumpang dan $_jumlahBarang kirim barang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.';
        } else if (_jumlahPenumpang > 0) {
          msg =
              'Tidak bisa berhenti bekerja. Masih ada $_jumlahPenumpang penumpang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.';
        } else {
          msg =
              'Tidak bisa berhenti bekerja. Masih ada $_jumlahBarang kirim barang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      // Konfirmasi: Apakah pekerjaan telah selesai? Ya -> selesai, tombol kembali ke Siap Kerja
      final confirm = await showDialog<bool>(
        context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selesai Bekerja'),
        content: const Text('Apakah pekerjaan telah selesai?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ya'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await _endWork();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pekerjaan selesai. Tombol kembali ke Siap Kerja.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // Tombol hijau: cek pesanan terjadwal dulu, lalu pilih rute atau gunakan rute jadwal
      _checkScheduledOrdersThenShowRouteSheet(isDriverVerified: isDriverVerified);
    }
  }

  /// Jika driver punya pesanan terjadwal (agreed/picked_up), tawarkan gunakan rute jadwal; else tampilkan sheet pilih jenis rute.
  Future<void> _checkScheduledOrdersThenShowRouteSheet({required bool isDriverVerified}) async {
    if (!isDriverVerified) {
      _showDriverLengkapiVerifikasiDialog();
      return;
    }
    final orders = await OrderService.getDriverScheduledOrdersWithAgreed();
    if (!mounted) return;
    if (orders.isEmpty) {
      _showRouteTypeSheet(isDriverVerified: isDriverVerified);
      return;
    }
    final first = orders.first;
    final scheduleId = first.scheduleId;
    final originText = first.originText;
    final destText = first.destText;
    final dateLabel = _formatScheduledDateForDialog(first.scheduledDate ?? '');

    final useJadwal = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pesanan terjadwal'),
        content: Text(
          'Anda punya pesanan terjadwal di tanggal $dateLabel dan sudah ada pemesan yang setuju. '
          'Tinggal klik icon Rute di Jadwal & Rute, rute akan berjalan otomatis tanpa atur ulang.\n\n'
          'Gunakan rute sesuai jadwal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sesuai rute'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (useJadwal == true &&
        scheduleId != null &&
        originText.isNotEmpty &&
        destText.isNotEmpty) {
      setState(() => _currentIndex = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isDriverVerified) _loadRouteFromJadwal(originText, destText, scheduleId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih rute di map (tap garis), lalu tap Mulai Rute ini untuk mulai bekerja.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      _showRouteTypeSheet(isDriverVerified: isDriverVerified);
    }
  }

  static String _formatScheduledDateForDialog(String ymd) {
    if (ymd.length != 10 || ymd[4] != '-' || ymd[7] != '-') return ymd;
    final y = ymd.substring(0, 4);
    final m = int.tryParse(ymd.substring(5, 7)) ?? 0;
    final d = ymd.substring(8, 10);
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
    if (m < 1 || m > 12) return ymd;
    return '$d ${months[m - 1]} $y';
  }

  /// Handler untuk tombol "Mulai" - mulai bekerja setelah rute dipilih
  Future<void> _onStartButtonTap() async {
    HapticFeedback.mediumImpact();
    if (!_routeSelected || _selectedRouteIndex < 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mulai bekerja'),
        content: const Text('Mulai bekerja dengan rute ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isDriverWorking = true;
      _destinationReachedAt = null;
      // Simpan posisi saat mulai bekerja untuk deteksi pergerakan
      _positionWhenStarted = _currentPosition;
      _hasMovedAfterStart = false; // Reset flag pergerakan
      _lastPositionForMovement =
          null; // Reset posisi untuk deteksi pergerakan real-time
    });

    // Load icon mobil MERAH saat mulai bekerja (belum bergerak)
    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      await _loadCarIcon(
        bearing: _currentPosition!.heading,
        iconColor: 'merah',
      );
      _lastCarIconBearing = _currentPosition!.heading;
    } else {
      // Load icon mobil merah tanpa rotasi (menghadap ke bawah/default)
      await _loadCarIcon(iconColor: 'merah');
    }

    // Hitung jarak dan estimasi waktu awal dari posisi driver ke tujuan
    if (_currentPosition != null && _routeDestLatLng != null) {
      await _updateCurrentDistanceAndDuration(_currentPosition!);
    }

    _registerRouteBackgroundHandler();
    _persistCurrentRoute();
    if (_currentPosition != null) {
      _updateDriverStatusToFirestore(_currentPosition!);
    }
    // Sembunyikan jadwal hari ini agar tidak tampil ke penumpang saat mencari travel
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      DriverScheduleService.markTodaySchedulesHidden(uid);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pekerjaan dimulai. Status: Berhenti Kerja.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showOperDriverSheet() {
    final pickedUpOrders = _driverOrders
        .where((o) =>
            o.status == OrderService.statusPickedUp &&
            o.orderType == OrderModel.typeTravel)
        .toList();
    if (pickedUpOrders.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _OperDriverSheet(
        orders: pickedUpOrders,
        onTransfersCreated: (transfers) {
          Navigator.pop(ctx);
          _showOperDriverBarcodeDialog(transfers);
        },
      ),
    );
  }

  void _showOperDriverBarcodeDialog(List<(String, String)> transfers) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OperDriverBarcodeDialog(transfers: transfers),
    );
  }

  void _showRouteTypeSheet({required bool isDriverVerified}) {
    if (!isDriverVerified) {
      _showDriverLengkapiVerifikasiDialog();
      return;
    }
    final hasPreviousRoute =
        _routeOriginLatLng != null && _routeDestLatLng != null;
    final atDestination =
        _routeDestLatLng != null &&
        _currentPosition != null &&
        Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              _routeDestLatLng!.latitude,
              _routeDestLatLng!.longitude,
            ) <=
            _atDestinationMeters;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih jenis rute',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih area tujuan perjalanan Anda',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.location_city, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('Dalam provinsi'),
              subtitle: const Text('Tujuan hanya di provinsi Anda'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(RouteType.dalamProvinsi, isDriverVerified: isDriverVerified);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.landscape,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Antar provinsi (satu pulau)'),
              subtitle: const Text('Ke provinsi lain di pulau yang sama'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(RouteType.antarProvinsi, isDriverVerified: isDriverVerified);
              },
            ),
            ListTile(
              leading: Icon(Icons.public, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('Seluruh Indonesia'),
              subtitle: const Text('Ke mana saja di Indonesia (lintas pulau)'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(RouteType.dalamNegara, isDriverVerified: isDriverVerified);
              },
            ),
            if (hasPreviousRoute && atDestination) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.green),
                title: const Text('Putar Arah Rute sebelumnya'),
                subtitle: const Text(
                  'Arah perjalanan dibalik (tujuan jadi awal, awal jadi tujuan)',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _reversePreviousRoute();
                },
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Dari Jadwal & Rute (icon rute): muat rute langsung dari tujuan awal/akhir jadwal,
  /// tampilkan garis kuning di map, tanpa pilih jenis rute atau isi form. Lokasi awal = jadwal.
  Future<void> _loadRouteFromJadwal(
    String originText,
    String destText, [
    String? scheduleId,
  ]) async {
    try {
      final originLocations = await locationFromAddress(
        '$originText, Indonesia',
      );
      final destLocations = await locationFromAddress('$destText, Indonesia');
      if (originLocations.isEmpty || destLocations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lokasi awal atau tujuan tidak ditemukan.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final originLat = originLocations.first.latitude;
      final originLng = originLocations.first.longitude;
      final destLat = destLocations.first.latitude;
      final destLng = destLocations.first.longitude;

      final alternatives = await DirectionsService.getAlternativeRoutes(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
      );

      if (!mounted) return;
      if (alternatives.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal memuat rute. Coba lagi.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _routeOriginLatLng = LatLng(originLat, originLng);
        _routeDestLatLng = LatLng(destLat, destLng);
        _routeOriginText = originText;
        _routeDestText = destText;
        _alternativeRoutes = alternatives;
        _selectedRouteIndex = -1;
        _routeSelected = false;
        _isDriverWorking = false;
        _routePolyline = null;
        _routeDistanceText = '';
        _routeDurationText = '';
        _activeRouteFromJadwal = true;
        _currentScheduleId = scheduleId;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAlternativeRoutesBounds();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih rute di map (tap garis kuning), lalu tap Mulai rute ini.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat rute: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _reversePreviousRoute() async {
    final origin = _routeOriginLatLng ?? _lastRouteOriginLatLng;
    final dest = _routeDestLatLng ?? _lastRouteDestLatLng;
    if (origin == null || dest == null) return;
    final newOrigin = dest;
    final newDest = origin;
    final prevOriginText = _routeOriginText.isNotEmpty
        ? _routeOriginText
        : _lastRouteOriginText;
    final prevDestText = _routeDestText.isNotEmpty
        ? _routeDestText
        : _lastRouteDestText;
    setState(() {
      _routeOriginLatLng = newOrigin;
      _routeDestLatLng = newDest;
      _routeOriginText = prevDestText;
      _routeDestText = prevOriginText;
      _activeRouteFromJadwal = false;
      _currentScheduleId = null;
    });
    // Ambil semua alternatif rute
    final alternatives = await DirectionsService.getAlternativeRoutes(
      originLat: newOrigin.latitude,
      originLng: newOrigin.longitude,
      destLat: newDest.latitude,
      destLng: newDest.longitude,
    );
    if (mounted && alternatives.isNotEmpty) {
      // Tampilkan alternatif rute di map, tunggu driver pilih
      setState(() {
        _routeOriginLatLng = newOrigin;
        _routeDestLatLng = newDest;
        _routeOriginText = prevDestText;
        _routeDestText = prevOriginText;
        _alternativeRoutes = alternatives;
        _selectedRouteIndex = -1; // Belum dipilih
        _routeSelected = false; // Belum dipilih
        _isDriverWorking =
            false; // Tombol tetap "Siap Kerja" sampai rute dipilih
        _routePolyline = null; // Belum ada rute yang dipilih
        _routeDistanceText = '';
        _routeDurationText = '';
        _activeRouteFromJadwal = false;
        _currentScheduleId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih rute yang diinginkan di map dengan tap pada polyline rute. Setelah dipilih, tombol "Selesai Bekerja" akan aktif.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );

      // Fit map untuk menampilkan semua alternatif rute
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAlternativeRoutesBounds();
      });
    }
  }

  void _openRouteForm(
    RouteType routeType, {
    String? initialDest,
    String? initialOrigin,
    bool isDriverVerified = true,
  }) {
    if (!isDriverVerified) {
      _showDriverLengkapiVerifikasiDialog();
      return;
    }
    setState(() {
      _activeRouteFromJadwal = false;
      _currentScheduleId = null;
    });
    final sameProvinceOnly = routeType == RouteType.dalamProvinsi;
    final sameIslandOnly = routeType == RouteType.antarProvinsi;
    final provincesInIsland =
        sameIslandOnly && (_currentProvinsi ?? '').isNotEmpty
        ? ProvinceIsland.getProvincesInSameIsland(_currentProvinsi!)
        : null;
    final currentContext = context; // Capture context for use in callback
    showModalBottomSheet<void>(
      context: currentContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DriverRouteFormSheet(
        originText: _originLocationText,
        currentProvinsi: _currentProvinsi,
        sameProvinceOnly: sameProvinceOnly,
        sameIslandOnly: sameIslandOnly,
        provincesInIsland: provincesInIsland ?? [],
        driverLat: _currentPosition?.latitude,
        driverLng: _currentPosition?.longitude,
        initialDest: initialDest,
        initialOrigin: initialOrigin,
        mapController: _mapController,
        formDestMapModeNotifier: _formDestMapModeNotifier,
        formDestMapTapNotifier: _formDestMapTapNotifier,
        formDestPreviewNotifier: _formDestPreviewNotifier,
        onRouteRequest:
            (
              originLat,
              originLng,
              originText,
              destLat,
              destLng,
              destText,
            ) async {
              Navigator.pop(ctx);
              // Ambil semua alternatif rute
              final alternatives = await DirectionsService.getAlternativeRoutes(
                originLat: originLat,
                originLng: originLng,
                destLat: destLat,
                destLng: destLng,
              );
              if (!mounted) return;
              if (alternatives.isNotEmpty) {
                // Tampilkan alternatif rute di map, tunggu driver pilih
                setState(() {
                  _routeOriginLatLng = LatLng(originLat, originLng);
                  _routeDestLatLng = LatLng(destLat, destLng);
                  _routeOriginText = originText;
                  _routeDestText = destText;
                  _alternativeRoutes = alternatives;
                  _selectedRouteIndex = -1; // Belum dipilih
                  _routeSelected = false; // Belum dipilih
                  _isDriverWorking =
                      false; // Tombol tetap "Siap Kerja" sampai rute dipilih
                  _routePolyline = null; // Belum ada rute yang dipilih
                  _routeDistanceText = '';
                  _routeDurationText = '';
                });

                if (mounted) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Pilih rute yang diinginkan di map dengan tap pada polyline rute. Setelah dipilih, tombol "Selesai Bekerja" akan aktif.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 4),
                    ),
                  );

                  // Fit map untuk menampilkan semua alternatif rute
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fitAlternativeRoutesBounds();
                  });
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Gagal memuat rute. Pastikan Directions API aktif di Google Cloud Console.',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
      ),
    );
  }

  /// Tampilkan dialog untuk memilih alternatif rute.
  /// Driver bisa melihat jarak dan waktu setiap alternatif, lalu pilih dengan tap.
  Future<int?> _showRouteSelectionDialog(
    List<DirectionsResult> alternatives,
  ) async {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Rute'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: alternatives.length,
            itemBuilder: (context, index) {
              final route = alternatives[index];
              final isSelected = index == _selectedRouteIndex;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
                child: InkWell(
                  onTap: () => Navigator.of(ctx).pop(index),
                  onLongPress: () {
                    // Long press (2-3 detik) untuk memilih rute
                    Navigator.of(ctx).pop(index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rute ${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${route.distanceText} • ${route.durationText}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_selectedRouteIndex),
            child: const Text('Gunakan Rute Terpilih'),
          ),
        ],
      ),
    );
  }

  void _fitRouteBounds() {
    if (_mapController == null ||
        _routePolyline == null ||
        _routePolyline!.isEmpty ||
        !mounted) {
      return;
    }
    double minLat = _routePolyline!.first.latitude;
    double maxLat = minLat;
    double minLng = _routePolyline!.first.longitude;
    double maxLng = minLng;
    for (final p in _routePolyline!) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  /// Fit map untuk menampilkan semua alternatif rute.
  void _fitAlternativeRoutesBounds() {
    if (_mapController == null || _alternativeRoutes.isEmpty || !mounted) return;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final route in _alternativeRoutes) {
      for (final p in route.points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }

    // Include origin dan destination jika ada
    if (_routeOriginLatLng != null) {
      if (_routeOriginLatLng!.latitude < minLat) {
        minLat = _routeOriginLatLng!.latitude;
      }
      if (_routeOriginLatLng!.latitude > maxLat) {
        maxLat = _routeOriginLatLng!.latitude;
      }
      if (_routeOriginLatLng!.longitude < minLng) {
        minLng = _routeOriginLatLng!.longitude;
      }
      if (_routeOriginLatLng!.longitude > maxLng) {
        maxLng = _routeOriginLatLng!.longitude;
      }
    }
    if (_routeDestLatLng != null) {
      if (_routeDestLatLng!.latitude < minLat) {
        minLat = _routeDestLatLng!.latitude;
      }
      if (_routeDestLatLng!.latitude > maxLat) {
        maxLat = _routeDestLatLng!.latitude;
      }
      if (_routeDestLatLng!.longitude < minLng) {
        minLng = _routeDestLatLng!.longitude;
      }
      if (_routeDestLatLng!.longitude > maxLng) {
        maxLng = _routeDestLatLng!.longitude;
      }
    }

    if (minLat != double.infinity && maxLat != -double.infinity && mounted) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          100,
        ),
      );
    }
  }

  void _toggleMapType() {
    setState(() {
      // Toggle antara normal dan hybrid (satelit dengan label)
      _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentPosition != null && mounted) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          15.0,
        ),
      );
    }
  }

  /// Load icon mobil dari assets dan simpan sebagai BitmapDescriptor
  /// [iconColor] menentukan warna icon: 'merah' atau 'hijau'
  Future<void> _loadCarIcon({
    double? bearing,
    String iconColor = 'hijau',
  }) async {
    try {
      final iconPath = iconColor == 'merah'
          ? 'assets/images/car_merah.png'
          : 'assets/images/car_hijau.png';

      final ByteData data = await rootBundle.load(iconPath);
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth:
            50, // Ukuran icon mobil dikurangi untuk menghemat RAM (dari 60 ke 50)
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image originalImage = frameInfo.image;

      // Buat canvas dengan padding untuk menghindari icon terpotong saat dirotasi
      const padding = 15.0; // Padding di semua sisi (diperbesar untuk rotasi)
      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();
      // Untuk rotasi, perlu canvas yang lebih besar (diagonal dari image)
      final maxDimension = (imageWidth > imageHeight
          ? imageWidth
          : imageHeight);
      final canvasSize = (maxDimension * 1.5 + padding * 2)
          .toInt(); // Extra space untuk rotasi

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Rotate image berdasarkan bearing jika ada
      // Icon mobil default menghadap ke bawah (selatan = 180 derajat)
      // Bearing dari GPS: 0 = utara, 90 = timur, 180 = selatan, 270 = barat
      // Untuk rotate icon agar depan mobil mengikuti arah perjalanan:
      // Jika bearing 0 (utara), icon perlu rotate 180° dari default (bawah) = menghadap utara
      // Jika bearing 90 (timur), icon perlu rotate 270° dari default = menghadap timur
      // Formula: rotation = (bearing - 180) karena default adalah 180° (menghadap ke bawah)
      if (bearing != null && bearing >= 0) {
        // Rotate image dengan padding di tengah canvas
        canvas.translate(canvasSize / 2, canvasSize / 2);
        final rotationRadians = (bearing - 180) * (3.14159265359 / 180);
        canvas.rotate(rotationRadians);
        canvas.translate(-imageWidth / 2, -imageHeight / 2);
        canvas.drawImage(originalImage, Offset.zero, Paint());
      } else {
        // Tanpa rotasi, gambar di tengah dengan padding
        canvas.drawImage(
          originalImage,
          Offset((canvasSize - imageWidth) / 2, (canvasSize - imageHeight) / 2),
          Paint(),
        );
      }

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(canvasSize, canvasSize);
      final byteData = await finalImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        _carIconBitmap = BitmapDescriptor.fromBytes(
          byteData.buffer.asUint8List(),
        );
      }

      if (mounted) {
        setState(() {}); // Trigger rebuild untuk update marker
      }
    } catch (e) {
      // Fallback ke default marker jika gagal load icon
      _carIconBitmap = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueBlue,
      );
    }
  }

  /// Rotate image berdasarkan bearing (dalam derajat)
  /// Bearing 0 = utara, 90 = timur, 180 = selatan, 270 = barat
  /// Icon mobil default menghadap ke bawah (180 derajat/selatan), jadi perlu adjust
  /// User menyebutkan: "posisi depannya di gambar arah kebawah" = default menghadap selatan (180°)
  Future<ui.Image> _rotateImage(ui.Image image, double bearing) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());

    // Icon mobil default menghadap ke bawah (selatan = 180 derajat)
    // Bearing dari GPS: 0 = utara, 90 = timur, 180 = selatan, 270 = barat
    // Untuk rotate icon agar depan mobil mengikuti arah perjalanan:
    // Jika bearing 0 (utara), icon perlu rotate 180° dari default (bawah) = menghadap utara
    // Jika bearing 90 (timur), icon perlu rotate 270° dari default = menghadap timur
    // Formula: rotation = (bearing - 180) karena default adalah 180°
    final rotationRadians = (bearing - 180) * (3.14159265359 / 180);

    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotationRadians);
    canvas.translate(-size.width / 2, -size.height / 2);

    canvas.drawImage(image, Offset.zero, Paint());

    final picture = recorder.endRecording();
    return await picture.toImage(image.width, image.height);
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};
    if (_currentPosition != null) {
      // Gunakan icon mobil jika rute sudah dipilih atau sudah mulai bekerja
      // Icon merah: setelah rute dipilih (tombol "Mulai Rute ini" muncul) sampai bergerak
      // Icon hijau: setelah bergerak
      // Icon biru: sebelum rute dipilih
      final icon =
          (_routeSelected || _isDriverWorking) && _carIconBitmap != null
          ? _carIconBitmap!
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);

      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: icon,
          anchor: const Offset(
            0.5,
            0.5,
          ), // Anchor di tengah icon untuk positioning yang tepat
          // Rotation sudah di-handle di _loadCarIcon dengan rotate image
        ),
      );
    }
    if (_routeOriginLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _routeOriginLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }
    if (_routeDestLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _routeDestLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    // Preview tujuan dari form (saat isi form rute, sebelum submit)
    final formPreview = _formDestPreviewNotifier.value;
    if (formPreview != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('form_dest_preview'),
          position: formPreview,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    // Pin pemesan (penumpang/barang) yang sudah kesepakatan, belum dijemput.
    // Pesanan terjadwal: hanya tampilkan jika driver sudah memulai rute dari jadwal itu (scheduleId cocok) dan tanggal jadwal = hari ini.
    final todayYmd = _todayYmd();
    final visibleOrders = <OrderModel>[];
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger ||
          order.passengerLat == null ||
          order.passengerLng == null) {
        continue;
      }
      if (order.isScheduledOrder) {
        if (_currentScheduleId == null ||
            _currentScheduleId != order.scheduleId ||
            (order.scheduledDate ?? '') != todayYmd) {
          continue;
        }
      }
      visibleOrders.add(order);
    }
    // Urutan jemput untuk pesanan terjadwal: sort by posisi sepanjang rute
    final routePolyline = _routePolyline ?? (_alternativeRoutes.isNotEmpty && _selectedRouteIndex >= 0 && _selectedRouteIndex < _alternativeRoutes.length
        ? _alternativeRoutes[_selectedRouteIndex].points
        : null);
    if (visibleOrders.length > 1 && routePolyline != null && routePolyline.isNotEmpty) {
      visibleOrders.sort((a, b) {
        final posA = LatLng(a.passengerLat!, a.passengerLng!);
        final posB = LatLng(b.passengerLat!, b.passengerLng!);
        final idxA = RouteUtils.getIndexAlongPolyline(posA, routePolyline, toleranceMeters: 50000);
        final idxB = RouteUtils.getIndexAlongPolyline(posB, routePolyline, toleranceMeters: 50000);
        if (idxA < 0 && idxB < 0) return 0;
        if (idxA < 0) return 1;
        if (idxB < 0) return -1;
        return idxA.compareTo(idxB);
      });
    }
    final visiblePassengerOrderIds = visibleOrders.map((o) => o.id).toSet();
    for (int i = 0; i < visibleOrders.length; i++) {
      final order = visibleOrders[i];
      final pos = LatLng(order.passengerLat!, order.passengerLng!);
      final defaultIcon = order.isKirimBarang
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      final icon = _passengerMarkerIcons[order.id] ?? defaultIcon;
      final pickupOrder = (visibleOrders.length > 1 && routePolyline != null && routePolyline.isNotEmpty)
          ? (i + 1)
          : null;
      final snippet = order.isKirimBarang ? 'Kirim barang' : 'Penumpang';
      final snippetWithOrder = pickupOrder != null
          ? '$snippet • Jemput ke-$pickupOrder'
          : snippet;
      markers.add(
        Marker(
          markerId: MarkerId('passenger_${order.id}'),
          position: pos,
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: order.passengerName,
            snippet: snippetWithOrder,
          ),
          onTap: () => _onPassengerMarkerTap(order),
        ),
      );
    }
    // Hapus cache icon untuk order yang tidak lagi ditampilkan
    _passengerMarkerIcons.removeWhere(
      (id, _) => !visiblePassengerOrderIds.contains(id),
    );
    return markers;
  }

  static String _todayYmd() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Jumlah penumpang/barang yang menunggu (agreed, belum dijemput) - untuk badge.
  int get _waitingPassengerCount {
    final todayYmd = _todayYmd();
    int count = 0;
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger ||
          order.passengerLat == null ||
          order.passengerLng == null) {
        continue;
      }
      if (order.isScheduledOrder) {
        if (_currentScheduleId == null ||
            _currentScheduleId != order.scheduleId ||
            (order.scheduledDate ?? '') != todayYmd) {
          continue;
        }
      }
      count++;
    }
    return count;
  }

  /// Jumlah pesanan terjadwal untuk hari ini yang sudah kesepakatan dan belum dijemput (untuk banner pengingat).
  int get _scheduledAgreedCountForToday {
    final todayYmd = _todayYmd();
    return _driverOrders.where((o) {
      if (!o.isScheduledOrder || (o.scheduledDate ?? '') != todayYmd) return false;
      if (o.status != OrderService.statusAgreed && o.status != OrderService.statusPickedUp) return false;
      return !o.hasDriverScannedPassenger;
    }).length;
  }

  Future<void> _loadPassengerMarkerIconsIfNeeded() async {
    final todayYmd = _todayYmd();
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger ||
          order.passengerLat == null ||
          order.passengerLng == null) {
        continue;
      }
      if (order.isScheduledOrder) {
        if (_currentScheduleId == null ||
            _currentScheduleId != order.scheduleId ||
            (order.scheduledDate ?? '') != todayYmd) {
          continue;
        }
      }
      if (_passengerMarkerIcons.containsKey(order.id)) continue;
      try {
        final icon = await _createPassengerMarkerIcon(order);
        if (!mounted) return;
        _passengerMarkerIcons[order.id] = icon;
        setState(() {});
      } catch (_) {
        // Tetap pakai pin oranye default
      }
    }
  }

  Future<BitmapDescriptor> _createPassengerMarkerIcon(OrderModel order) async {
    const double w = 80.0;
    const double h = 100.0;
    const double nameHeight = 26.0;
    const double borderWidth = 2.0;
    const double circleRadius = 34.0;
    final double circleCenterY = nameHeight + circleRadius;

    ui.Image? photoImage;
    if (order.passengerPhotoUrl != null &&
        order.passengerPhotoUrl!.trim().isNotEmpty) {
      try {
        photoImage = await _decodeImageFromUrl(order.passengerPhotoUrl!);
      } catch (_) {}
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Lingkaran foto (border putih + isi)
    final circleCenter = Offset(w / 2, circleCenterY);
    final circleRect = Rect.fromCircle(
      center: circleCenter,
      radius: circleRadius,
    );
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);
    if (photoImage != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(circleRect));
      paintImage(
        canvas: canvas,
        rect: circleRect,
        image: photoImage,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(
        circleCenter,
        circleRadius,
        Paint()..color = order.isKirimBarang ? Colors.blue.shade300 : Colors.orange.shade300,
      );
    }

    // Pita nama di atas (rounded rect) - biru untuk kirim barang, oranye untuk travel
    final nameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, nameHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(nameRect, Paint()..color = order.isKirimBarang ? Colors.blue : Colors.orange);
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;
    final textPainter = TextPainter(
      text: TextSpan(
        text: name.length > 12 ? '${name.substring(0, 11)}…' : name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    textPainter.layout(maxWidth: w - 8);
    textPainter.paint(canvas, Offset(4, (nameHeight - textPainter.height) / 2));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }

  Future<ui.Image> _decodeImageFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('Failed to load image');
    final bytes = Uint8List.view(response.bodyBytes.buffer);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  Future<void> _onPassengerMarkerTap(OrderModel order) async {
    if (order.passengerLat == null || order.passengerLng == null) return;
    final label = order.isKirimBarang ? 'barang' : 'penumpang';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ambil pemesan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (order.passengerPhotoUrl != null &&
                          order.passengerPhotoUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                      : null,
                  child:
                      (order.passengerPhotoUrl == null ||
                          order.passengerPhotoUrl!.isEmpty)
                      ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    order.passengerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Apakah anda akan mengambil $label ini? Jika ya, anda akan diarahkan ke lokasi pemesan.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, arahkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Tetap di Beranda: mode navigasi ke penumpang di dalam app (tidak buka Google Maps)
    setState(() {
      _navigatingToOrderId = order.id;
      _lastPassengerLat = order.passengerLat;
      _lastPassengerLng = order.passengerLng;
    });
    await _fetchAndShowRouteToPassenger(order);
  }

  /// Ambil rute driver → penumpang dan tampilkan di peta. Dipanggil saat "Ya, arahkan" dan saat lokasi penumpang berubah.
  Future<void> _fetchAndShowRouteToPassenger(OrderModel order) async {
    if (order.passengerLat == null || order.passengerLng == null) return;
    if (_currentPosition == null) return;
    final result = await DirectionsService.getRoute(
      originLat: _currentPosition!.latitude,
      originLng: _currentPosition!.longitude,
      destLat: order.passengerLat!,
      destLng: order.passengerLng!,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _polylineToPassenger = result.points;
        _routeToPassengerDistanceText = result.distanceText;
        _routeToPassengerDurationText = result.durationText;
      });
      _fitRouteToPassengerBounds();
    } else {
      // Fallback: garis lurus jika API gagal
      setState(() {
        _polylineToPassenger = [
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          LatLng(order.passengerLat!, order.passengerLng!),
        ];
        _routeToPassengerDistanceText = '';
        _routeToPassengerDurationText = '';
      });
      _fitRouteToPassengerBounds();
    }
  }

  void _fitRouteToPassengerBounds() {
    if (_mapController == null || _polylineToPassenger == null || !mounted) return;
    double minLat = _polylineToPassenger!.first.latitude;
    double maxLat = minLat;
    double minLng = _polylineToPassenger!.first.longitude;
    double maxLng = minLng;
    for (final p in _polylineToPassenger!) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    if (mounted) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    }
  }

  void _exitNavigatingToPassenger() {
    setState(() {
      _navigatingToOrderId = null;
      _polylineToPassenger = null;
      _routeToPassengerDistanceText = '';
      _routeToPassengerDurationText = '';
      _lastPassengerLat = null;
      _lastPassengerLng = null;
    });
  }

  Widget _buildRouteInfoPanel() {
    final isNavigatingToPassenger = _navigatingToOrderId != null;
    // Gunakan jarak dan waktu dinamis jika sudah dihitung, jika belum gunakan yang awal
    final displayDistance = _currentDistanceText.isNotEmpty
        ? _currentDistanceText
        : _routeDistanceText;
    final displayDuration = _currentDurationText.isNotEmpty
        ? _currentDurationText
        : _routeDurationText;

    return GestureDetector(
      onTap: () {
        if (!isNavigatingToPassenger) {
          setState(() {
            _routeInfoPanelExpanded = !_routeInfoPanelExpanded;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode navigasi ke penumpang: tampilan khusus
            if (isNavigatingToPassenger) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_pin_circle,
                        size: 20,
                        color: const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Menuju penumpang',
                        style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _exitNavigatingToPassenger,
                    child: const Text('Kembali ke rute'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _routeInfoRow(
                Icons.route,
                'Jarak ke penumpang',
                (_routeToPassengerDistanceText.isNotEmpty &&
                        _routeToPassengerDurationText.isNotEmpty)
                    ? '$_routeToPassengerDistanceText • Est. $_routeToPassengerDurationText'
                    : 'Memuat...',
              ),
              const SizedBox(height: 6),
              Text(
                'Setelah scan barcode/konfirmasi otomatis, Anda akan kembali ke rute utama.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_waitingPassengerCount > 1) ...[
                const SizedBox(height: 6),
                _routeInfoRow(
                  Icons.people_outline,
                  'Penumpang lainnya',
                  '$_waitingPassengerCount menunggu',
                ),
              ],
            ] else ...[
            // Baris judul: "Informasi rute" + chevron (klik untuk turun/naik)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Informasi rute',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Icon(
                  _routeInfoPanelExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            if (_routeInfoPanelExpanded) ...[
              const SizedBox(height: 12),
              if (_waitingPassengerCount > 0) ...[
                _routeInfoRow(
                  Icons.person_pin_circle_outlined,
                  'Penumpang menunggu',
                  '$_waitingPassengerCount pemesan',
                ),
                const SizedBox(height: 6),
              ],
              // Rute awal: sesuai lokasi driver (tidak diubah)
              _routeInfoRow(
                Icons.location_on,
                'Rute awal',
                _originLocationText.isNotEmpty
                    ? _originLocationText
                    : (_currentPosition != null
                          ? '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}'
                          : 'Lokasi driver'),
              ),
              const SizedBox(height: 6),
              // Tujuan Rute: sesuai rute yang dipilih
              _routeInfoRow(
                Icons.place,
                'Tujuan Rute',
                _routeDestText.isNotEmpty ? _routeDestText : '-',
              ),
              const SizedBox(height: 6),
              // Jarak: dari posisi driver saat ini ke tujuan (berubah sesuai pergerakan)
              _routeInfoRow(
                Icons.route,
                'Jarak',
                (displayDistance.isNotEmpty && displayDuration.isNotEmpty)
                    ? '$displayDistance • Est. $displayDuration'
                    : '-',
              ),
              const SizedBox(height: 6),
              // Baris Jumlah Penumpang dan Barang dengan tombol Oper Driver di sebelah kanan
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _routeInfoRow(
                          Icons.people,
                          'Jumlah Penumpang',
                          '$_jumlahPenumpang',
                        ),
                        const SizedBox(height: 6),
                        _routeInfoRow(
                          Icons.luggage,
                          'Jumlah Barang',
                          '$_jumlahBarang',
                        ),
                      ],
                    ),
                  ),
                  // Tombol "Oper Driver" di kanan (hanya aktif jika ada penumpang sudah dijemput)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: ElevatedButton.icon(
                      onPressed: _jumlahPenumpangPickedUp > 0
                          ? () => _showOperDriverSheet()
                          : null,
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon mobil pertama
                          const Icon(Icons.directions_car, size: 16),
                          const SizedBox(width: 2),
                          // Icon beberapa orang
                          Stack(
                            children: [
                              const Icon(Icons.person, size: 14),
                              Positioned(
                                left: 8,
                                child: const Icon(Icons.person, size: 14),
                              ),
                              Positioned(
                                left: 4,
                                top: -2,
                                child: const Icon(Icons.person, size: 12),
                              ),
                            ],
                          ),
                          const SizedBox(width: 2),
                          // Icon mobil kedua
                          const Icon(Icons.directions_car, size: 16),
                        ],
                      ),
                      label: const Text('Oper Driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ], // Row (Oper Driver) children
              ), // Row
            ], // if (_routeInfoPanelExpanded)
            ], // else (informasi rute normal)
          ], // Column children
        ),
      ),
    );
  }

  Widget _routeInfoRow(IconData icon, String label, String value) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 18, color: primary),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(color: primary, fontSize: 13),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Set<Polyline> _buildPolylines() {
    final Set<Polyline> polylines = {};

    // Mode navigasi ke penumpang: tampilkan rute ke penumpang (hijau) + rute utama (abu-abu) bersamaan
    if (_navigatingToOrderId != null &&
        _polylineToPassenger != null &&
        _polylineToPassenger!.isNotEmpty) {
      // Rute utama (origin→dest) tetap tampil dengan warna abu-abu agar driver tetap punya konteks
      List<LatLng>? mainRoute = _routePolyline;
      if ((mainRoute == null || mainRoute.isEmpty) &&
          _alternativeRoutes.isNotEmpty &&
          _selectedRouteIndex >= 0 &&
          _selectedRouteIndex < _alternativeRoutes.length) {
        mainRoute = _alternativeRoutes[_selectedRouteIndex].points;
      }
      if (mainRoute != null && mainRoute.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route_main_faded'),
            points: mainRoute,
            color: Colors.grey.shade400,
            width: 4,
          ),
        );
      }
      // Rute ke penumpang (hijau, menonjol)
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route_to_passenger'),
          points: _polylineToPassenger!,
          color: const Color(0xFF2E7D32), // Hijau untuk rute ke penumpang
          width: 6,
        ),
      );
      return polylines;
    }

    // Tampilkan semua alternatif rute jika ada (bahkan jika belum dipilih)
    if (_alternativeRoutes.isNotEmpty) {
      for (int i = 0; i < _alternativeRoutes.length; i++) {
        final route = _alternativeRoutes[i];
        final isSelected = i == _selectedRouteIndex && _routeSelected;
        polylines.add(
          Polyline(
            polylineId: PolylineId('route_$i'),
            points: route.points,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.amber.shade700, // Kuning untuk rute alternatif
            width: isSelected ? 6 : 4,
            patterns:
                [], // Garis solid untuk semua rute (baik yang dipilih maupun alternatif)
          ),
        );
      }
    } else if (_routePolyline != null && _routePolyline!.isNotEmpty) {
      // Fallback: tampilkan rute yang dipilih jika tidak ada alternatif
        polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePolyline!,
          color: Theme.of(context).colorScheme.primary,
          width: 5,
        ),
      );
    }

    return polylines;
  }

  /// Hitung jarak terdekat dari titik ke polyline.
  /// Mengembalikan jarak dalam meter.
  double _distanceToPolyline(LatLng point, List<LatLng> polyline) {
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final segmentStart = polyline[i];
      final segmentEnd = polyline[i + 1];
      final distance = _distanceToSegment(point, segmentStart, segmentEnd);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  /// Hitung jarak dari titik ke segmen garis (dalam meter).
  double _distanceToSegment(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    // Hitung jarak menggunakan formula haversine untuk segmen pendek
    final distToStart = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      segmentStart.latitude,
      segmentStart.longitude,
    );
    final distToEnd = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      segmentEnd.latitude,
      segmentEnd.longitude,
    );
    final distSegment = Geolocator.distanceBetween(
      segmentStart.latitude,
      segmentStart.longitude,
      segmentEnd.latitude,
      segmentEnd.longitude,
    );

    // Jika segmen sangat pendek, return jarak terdekat ke titik ujung
    if (distSegment < 1) {
      return distToStart < distToEnd ? distToStart : distToEnd;
    }

    // Hitung jarak ke segmen menggunakan proyeksi
    // Untuk segmen pendek, gunakan pendekatan sederhana
    final ratio = distToStart / (distToStart + distToEnd);
    final projectedLat =
        segmentStart.latitude +
        (segmentEnd.latitude - segmentStart.latitude) * ratio;
    final projectedLng =
        segmentStart.longitude +
        (segmentEnd.longitude - segmentStart.longitude) * ratio;

    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      projectedLat,
      projectedLng,
    );
  }

  /// Handle tap pada map untuk memilih rute alternatif.
  /// Driver tap pada polyline rute untuk memilih.
  /// Bisa memilih rute lain sebelum klik "Mulai", setelah "Mulai" tidak bisa lagi.
  void _onMapTap(LatLng position) {
    if (_alternativeRoutes.isEmpty || _isDriverWorking) {
      return; // Tidak bisa pilih jika sudah mulai bekerja
    }

    // Hitung jarak dari titik tap ke setiap alternatif rute dengan optimasi
    double minDistance = double.infinity;
    int closestRouteIndex = -1;

    for (int i = 0; i < _alternativeRoutes.length; i++) {
      final route = _alternativeRoutes[i];
      // Optimasi: gunakan sampling setiap beberapa titik untuk performa lebih baik
      final distance = _distanceToPolylineOptimized(position, route.points);
      if (distance < minDistance) {
        minDistance = distance;
        closestRouteIndex = i;
      }
    }

    // Threshold lebih besar (20000 meter) untuk responsivitas lebih baik
    // Atau langsung pilih rute terdekat jika hanya ada beberapa alternatif
    final threshold = _alternativeRoutes.length <= 3 ? 50000 : 20000;

    if (closestRouteIndex >= 0 && minDistance < threshold) {
      final selectedRoute = _alternativeRoutes[closestRouteIndex];

      // Generate journey number dan mulai rute
      _selectRouteAndStart(closestRouteIndex);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rute ${closestRouteIndex + 1} dipilih: ${selectedRoute.distanceText} • ${selectedRoute.durationText}. Klik tombol "Mulai Rute ini" untuk mulai bekerja.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (_alternativeRoutes.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tap pada area garis kuning untuk memilih. Jarak terdekat: ${(minDistance / 1000).toStringAsFixed(1)}km',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Versi optimasi dari _distanceToPolyline dengan sampling untuk performa lebih baik.
  double _distanceToPolylineOptimized(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        polyline[0].latitude,
        polyline[0].longitude,
      );
    }

    double minDistance = double.infinity;

    // Optimasi: sample setiap beberapa titik untuk performa lebih baik
    // Untuk polyline panjang, sample setiap beberapa titik
    final step = polyline.length > 200 ? 5 : 1;

    for (int i = 0; i < polyline.length - 1; i += step) {
      final nextIndex = (i + step < polyline.length)
          ? i + step
          : polyline.length - 1;
      final segmentStart = polyline[i];
      final segmentEnd = polyline[nextIndex];
      final distance = _distanceToSegment(point, segmentStart, segmentEnd);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    // Pastikan cek segmen terakhir jika step > 1
    if (step > 1 && polyline.length > 1) {
      final lastIndex = polyline.length - 1;
      if (lastIndex - step >= 0) {
        final distance = _distanceToSegment(
          point,
          polyline[lastIndex - step],
          polyline[lastIndex],
        );
        if (distance < minDistance) {
          minDistance = distance;
        }
      }
      // Cek segmen terakhir langsung
      final distance = _distanceToSegment(
        point,
        polyline[lastIndex - 1],
        polyline[lastIndex],
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    return minDistance;
  }

  /// Pilih rute dan siapkan untuk mulai bekerja (tapi belum aktif sampai tombol diklik).
  Future<void> _selectRouteAndStart(int routeIndex) async {
    if (routeIndex < 0 || routeIndex >= _alternativeRoutes.length) return;

    final selectedRoute = _alternativeRoutes[routeIndex];
    final String journeyNumber;
    if (_activeRouteFromJadwal &&
        _currentScheduleId != null &&
        _currentScheduleId!.isNotEmpty) {
      journeyNumber = OrderService.routeJourneyNumberScheduled;
    } else {
      journeyNumber =
          await RouteJourneyNumberService.generateRouteJourneyNumber();
    }
    if (!mounted) return;
    final startedAt = DateTime.now();

    setState(() {
      _selectedRouteIndex = routeIndex;
      _routePolyline = selectedRoute.points;
      _routeDistanceText = selectedRoute.distanceText;
      _routeDurationText = selectedRoute.durationText;
      _routeEstimatedDurationSeconds = selectedRoute.durationSeconds;
      _routeSelected =
          true; // Rute sudah dipilih, tombol "Mulai Rute ini" muncul
      _routeJourneyNumber = journeyNumber;
      _routeStartedAt = startedAt;
      // _isDriverWorking tetap false sampai tombol "Mulai Rute ini" diklik
    });

    // Load icon merah ketika rute dipilih (sebelum klik "Mulai Rute ini")
    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      await _loadCarIcon(
        bearing: _currentPosition!.heading,
        iconColor: 'merah',
      );
      _lastCarIconBearing = _currentPosition!.heading;
    } else {
      await _loadCarIcon(iconColor: 'merah');
    }

    // Fit map ke rute yang dipilih
    _fitRouteBounds();
  }

  void _showDriverLengkapiVerifikasiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lengkapi data verifikasi'),
        content: const Text(
          'Lengkapi data verifikasi terlebih dahulu untuk memilih rute, mulai kerja, atau menambah jadwal travel.',
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
              setState(() => _currentIndex = 4); // Tab Saya (Profil)
            },
            child: const Text('Lengkapi Sekarang'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverMapScreen({required bool isDriverVerified}) {
    return Stack(
      children: [
        RepaintBoundary(
          child: GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(
            target: _currentPosition != null
                ? LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  )
                : const LatLng(-3.3194, 114.5907),
            zoom: 15.0,
          ),
          mapType: _mapType,
          myLocationEnabled:
              false, // Disable untuk menghilangkan pin hijau default
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          zoomGesturesEnabled: true, // Enable zoom dengan gesture 2 jari
          scrollGesturesEnabled: true, // Enable scroll/pan
          tiltGesturesEnabled: true,
          rotateGesturesEnabled: true,
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          onTap: (LatLng position) {
            if (_formDestMapModeNotifier.value) {
              _formDestMapTapNotifier.value = position;
            } else if (_alternativeRoutes.isNotEmpty && !_isDriverWorking) {
              _onMapTap(position);
            }
          },
        ),
        ),
        const PromotionBannerWidget(role: 'driver'),
        // Petunjuk untuk tap (tampil jika ada alternatif rute dan belum mulai bekerja)
        if (_alternativeRoutes.isNotEmpty && !_isDriverWorking)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _routeSelected
                    ? 'Tap garis untuk pilih rute lain. Lalu tap Mulai Rute ini.'
                    : 'Tap garis untuk pilih rute, lalu tap Mulai Rute ini.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        // Pengingat: ada penumpang terjadwal hari ini tapi driver belum mulai rute dari jadwal
        if (_currentScheduleId == null && _scheduledAgreedCountForToday > 0)
          Positioned(
            top: 108,
            left: 16,
            right: 16,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, color: Colors.amber.shade800, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Anda punya $_scheduledAgreedCountForToday penumpang terjadwal hari ini. Pilih rute di Jadwal, lalu Mulai Rute.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _currentIndex = 1),
                        child: const Text('Buka Jadwal'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Toggle Button: Siap Kerja / Selesai Bekerja - pill gradient
        Positioned(
          top: 56,
          left: 16,
          child: Tooltip(
            message: _isDriverWorking && _hasActiveOrder
                ? 'Masih ada penumpang/barang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.'
                : '',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (_isDriverWorking || !_routeSelected)
                    ? () => _onToggleButtonTap(isDriverVerified: isDriverVerified)
                    : null,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: _isDriverWorking
                        ? (_hasActiveOrder
                            ? LinearGradient(
                                colors: [
                                  Colors.grey.shade600,
                                  Colors.grey.shade700,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Color(0xFFE53935), Color(0xFFEF5350)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ))
                        : (_routeSelected
                            ? LinearGradient(
                                colors: [
                                  Colors.grey.shade500,
                                  Colors.grey.shade600,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isDriverWorking
                            ? Icons.stop_circle
                            : Icons.play_circle_filled,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isDriverWorking
                            ? 'Selesai Bekerja'
                            : (_routeSelected ? 'Rute dipilih' : 'Siap Kerja'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Tombol "Mulai Rute ini" - pill gradient, muncul setelah rute dipilih
        if (_routeSelected && !_isDriverWorking)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _onStartButtonTap,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.navigation,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Mulai Rute ini',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        MapTypeZoomControls(
          mapType: _mapType,
          onToggleMapType: _toggleMapType,
          onZoomIn: () {
            if (mounted) _mapController?.animateCamera(CameraUpdate.zoomIn());
          },
          onZoomOut: () {
            if (mounted) _mapController?.animateCamera(CameraUpdate.zoomOut());
          },
        ),
      ],
    );
  }

  /// Cek apakah ada active order (agreed/picked_up) - travel atau kirim_barang.
  void _checkActiveOrder() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    OrderService.getOrdersForDriver(uid)
        .then((orders) {
          if (!mounted) return;
          final hasActive = orders.any(
            (o) =>
                (o.orderType == OrderModel.typeTravel ||
                    o.orderType == OrderModel.typeKirimBarang) &&
                (o.status == OrderService.statusAgreed ||
                    o.status == OrderService.statusPickedUp),
          );

          if (mounted) {
            setState(() {
              _hasActiveOrder = hasActive;
            });
          }
        })
        .catchError((e) {
          if (kDebugMode) debugPrint('DriverScreen._checkActiveOrder error: $e');
        });
  }

  Widget _buildOtherScreens({required bool isDriverVerified}) {
    switch (_currentIndex) {
      case 1:
        return DriverJadwalRuteScreen(
          isDriverVerified: isDriverVerified,
          onVerificationRequired: _showDriverLengkapiVerifikasiDialog,
          onOpenRuteFromJadwal: (origin, dest, scheduleId) {
            if (!isDriverVerified) {
              _showDriverLengkapiVerifikasiDialog();
              return;
            }
            setState(() => _currentIndex = 0);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadRouteFromJadwal(origin, dest, scheduleId);
            });
          },
          disableRouteIconForToday: _isDriverWorking && !_activeRouteFromJadwal,
        );
      case 2:
        return const ChatListDriverScreen();
      case 3:
        return DataOrderDriverScreen(
          onNavigateToPassenger: (order) {
            setState(() {
              _currentIndex = 0;
              _navigatingToOrderId = order.id;
              _lastPassengerLat = order.passengerLat;
              _lastPassengerLng = order.passengerLng;
            });
            _fetchAndShowRouteToPassenger(order);
          },
        );
      case 4:
        return const ProfileDriverScreen();
      default:
        return _buildDriverMapScreen(isDriverVerified: isDriverVerified);
    }
  }

  /// Driver profil lengkap & terverifikasi: Data Kendaraan + Verifikasi Driver (SIM) + Email & No.Telp.
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, profileSnap) {
        if (!profileSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data =
            profileSnap.data!.data() as Map<String, dynamic>? ?? <String, dynamic>{};
        final isDriverVerified = VerificationService.isDriverVerified(data);

        return Scaffold(
          // Pembatasan "Pesanan Aktif" hanya untuk penumpang; driver tetap bisa akses Beranda/rute.
          body: _currentIndex == 0
          ? StreamBuilder<DriverContributionStatus>(
              stream: DriverContributionService.streamContributionStatus(),
              builder: (context, contribSnap) {
                final mustPay = contribSnap.data?.mustPayContribution ?? false;
                return Column(
                  children: [
                    if (mustPay)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: context.responsive.spacing(16),
                          vertical: context.responsive.spacing(12),
                        ),
                        color: Colors.orange.shade50,
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Bayar kontribusi untuk menerima order dan balas chat.',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final ok = await Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ContributionDriverScreen(),
                                      ),
                                    );
                                if (ok == true && mounted) setState(() {});
                              },
                              child: const Text('Bayar kontribusi'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: _buildDriverMapScreen(isDriverVerified: isDriverVerified)),
                    if ((_isDriverWorking &&
                            _routePolyline != null &&
                            _routePolyline!.isNotEmpty) ||
                        _navigatingToOrderId != null)
                      _buildRouteInfoPanel(),
                  ],
                );
              },
            )
          : _buildOtherScreens(isDriverVerified: isDriverVerified),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
          // Jika kembali ke halaman beranda, cek ulang active order
          if (index == 0) {
            _checkActiveOrder();
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        items: [
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 0 ? Icons.home : Icons.home_outlined,
              color: _currentIndex == 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 1 ? Icons.schedule : Icons.schedule_outlined,
              color: _currentIndex == 1
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: 'Jadwal',
          ),
          BottomNavigationBarItem(
            icon: _chatUnreadCount > 0
                ? Badge(
                    label: Text('$_chatUnreadCount'),
                    child: Icon(
                      _currentIndex == 2
                          ? Icons.chat_bubble
                          : Icons.chat_bubble_outline,
                      color: _currentIndex == 2
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    _currentIndex == 2
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                    color: _currentIndex == 2
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 3
                  ? Icons.receipt_long
                  : Icons.receipt_long_outlined,
              color: _currentIndex == 3
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: 'Pesanan',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 4 ? Icons.person : Icons.person_outline,
              color: _currentIndex == 4
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: 'Profil',
          ),
        ],
      ),
        );
      },
    );
  }
}

/// Bottom sheet form: asal (auto), tujuan (autocomplete + Pilih di Map), tombol Rute Perjalanan.
/// Menggunakan peta utama beranda (bukan maps kecil) seperti form penumpang.
class _DriverRouteFormSheet extends StatefulWidget {
  final String originText;
  final String? currentProvinsi;
  final bool sameProvinceOnly;
  final bool sameIslandOnly;
  final List<String> provincesInIsland;
  final double? driverLat;
  final double? driverLng;
  final String? initialDest;
  final String? initialOrigin;
  final GoogleMapController? mapController;
  final ValueNotifier<bool> formDestMapModeNotifier;
  final ValueNotifier<LatLng?> formDestMapTapNotifier;
  final ValueNotifier<LatLng?> formDestPreviewNotifier;
  final void Function(
    double originLat,
    double originLng,
    String originText,
    double destLat,
    double destLng,
    String destText,
  )
  onRouteRequest;

  const _DriverRouteFormSheet({
    required this.originText,
    required this.currentProvinsi,
    required this.sameProvinceOnly,
    required this.sameIslandOnly,
    required this.provincesInIsland,
    required this.driverLat,
    required this.driverLng,
    this.initialDest,
    this.initialOrigin,
    this.mapController,
    required this.formDestMapModeNotifier,
    required this.formDestMapTapNotifier,
    required this.formDestPreviewNotifier,
    required this.onRouteRequest,
  });

  @override
  State<_DriverRouteFormSheet> createState() => _DriverRouteFormSheetState();
}

class _DriverRouteFormSheetState extends State<_DriverRouteFormSheet> {
  late final TextEditingController _destController = TextEditingController(
    text: widget.initialDest ?? '',
  );
  final GlobalKey _autocompleteKey = GlobalKey();
  List<Placemark> _autocompleteResults = [];
  List<Location> _autocompleteLocations = [];
  bool _showAutocomplete = false;
  bool _loadingRoute = false;
  double? _selectedDestLat;
  double? _selectedDestLng;
  bool _isMapSelectionMode = false;

  @override
  void initState() {
    super.initState();
    widget.formDestMapTapNotifier.addListener(_onMainMapTapped);
  }

  @override
  void dispose() {
    widget.formDestMapTapNotifier.removeListener(_onMainMapTapped);
    widget.formDestMapModeNotifier.value = false;
    widget.formDestPreviewNotifier.value = null;
    _destController.dispose();
    super.dispose();
  }

  void _onMainMapTapped() {
    final pos = widget.formDestMapTapNotifier.value;
    if (pos != null && mounted) {
      widget.formDestMapTapNotifier.value = null;
      _onSheetMapTapped(pos);
    }
  }

  String _formatPlacemarkDetail(Placemark p) =>
      PlacemarkFormatter.formatDetail(p);

  /// Tap di peta utama untuk pilih lokasi tujuan
  Future<void> _onSheetMapTapped(LatLng position) async {
    setState(() {
      _selectedDestLat = position.latitude;
      _selectedDestLng = position.longitude;
      _destController.text = 'Memuat alamat...';
    });
    widget.formDestPreviewNotifier.value = position;
    if (mounted) {
      widget.mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(position, 15),
      );
    }
    await _reverseGeocodeDest(position);
  }

  Future<void> _reverseGeocodeDest(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final displayText = _formatPlacemarkDetail(placemarks.first);
        if (mounted) {
          setState(() {
            _destController.text = displayText;
            _showAutocomplete = false;
            _autocompleteResults = [];
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _destController.text =
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _destController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  Future<void> _onDestinationChanged(String value) async {
    if (value.isEmpty) {
      setState(() {
        _autocompleteResults = [];
        _autocompleteLocations = [];
        _showAutocomplete = false;
        _selectedDestLat = null;
        _selectedDestLng = null;
      });
      widget.formDestPreviewNotifier.value = null;
      return;
    }
    if (widget.driverLat == null || widget.driverLng == null) return;
    await Future.delayed(const Duration(milliseconds: 150));
    if (_destController.text != value) return;

    try {
      final List<Location> allLocations = [];
      final Set<String> seen = {};
      final queries = <String>[];
      if (widget.sameProvinceOnly &&
          (widget.currentProvinsi ?? '').isNotEmpty) {
        // Rute dalam provinsi: hanya tujuan di provinsi driver
        queries.add('$value, ${widget.currentProvinsi}, Indonesia');
      } else if (widget.sameIslandOnly && widget.provincesInIsland.isNotEmpty) {
        // Rute antar provinsi: cari di Indonesia lalu filter sesama pulau
        queries.add('$value, Indonesia');
      } else {
        // Rute dalam negara: provinsi driver + seluruh Indonesia
        if ((widget.currentProvinsi ?? '').isNotEmpty) {
          queries.add('$value, ${widget.currentProvinsi}, Indonesia');
        }
        queries.add('$value, Indonesia');
      }
      for (final query in queries) {
        if (_destController.text != value) break;
        try {
          final results = await locationFromAddress(query);
          for (final loc in results) {
            final key =
                '${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';
            if (!seen.contains(key)) {
              seen.add(key);
              allLocations.add(loc);
            }
            if (allLocations.length >= 20) break;
          }
          if (allLocations.length >= 20) break;
        } catch (_) {}
      }
      if (!widget.sameProvinceOnly &&
          allLocations.length > 1 &&
          widget.driverLat != null &&
          widget.driverLng != null) {
        allLocations.sort((a, b) {
          final da = Geolocator.distanceBetween(
            widget.driverLat!,
            widget.driverLng!,
            a.latitude,
            a.longitude,
          );
          final db = Geolocator.distanceBetween(
            widget.driverLat!,
            widget.driverLng!,
            b.latitude,
            b.longitude,
          );
          return da.compareTo(db);
        });
      }
      if (_destController.text != value) return;
      // Untuk rute antar provinsi: dapatkan placemark dulu, filter sesama pulau, baru batasi 10
      final placemarks = <Placemark>[];
      final locationsForPlacemarks = <Location>[];
      final maxCandidates = widget.sameIslandOnly ? 25 : 10;
      for (var i = 0; i < allLocations.length && i < maxCandidates; i++) {
        final loc = allLocations[i];
        try {
          final list = await placemarkFromCoordinates(
            loc.latitude,
            loc.longitude,
          );
          if (list.isNotEmpty) {
            final p = list.first;
            if (widget.sameIslandOnly && widget.provincesInIsland.isNotEmpty) {
              final prov = p.administrativeArea ?? '';
              if (!ProvinceIsland.isProvinceInList(
                prov,
                widget.provincesInIsland,
              )) {
                continue;
              }
            }
            placemarks.add(p);
            locationsForPlacemarks.add(loc);
            if (placemarks.length >= 10) break;
          }
        } catch (_) {}
      }
      final limited = locationsForPlacemarks;
      if (mounted && _destController.text == value) {
        setState(() {
          _autocompleteResults = placemarks;
          _autocompleteLocations = limited;
          _showAutocomplete = true;
        });
        // Peta utama bergerak ke hasil pertama (preview) seperti form penumpang
        if (limited.isNotEmpty && widget.mapController != null && mounted) {
          widget.mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(limited.first.latitude, limited.first.longitude),
              14.0,
            ),
          );
        }
        // Scroll agar pilihan autocomplete terlihat (tidak tertutup keyboard)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autocompleteKey.currentContext != null) {
            Scrollable.ensureVisible(
              _autocompleteKey.currentContext!,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted && _destController.text == value) {
        setState(() {
          _autocompleteResults = [];
          _showAutocomplete = false;
        });
      }
    }
  }

  String _formatPlacemark(Placemark p) => PlacemarkFormatter.formatDetail(p);

  void _selectDestination(Placemark placemark, int index) {
    final displayText = _formatPlacemarkDetail(placemark);
    double? lat;
    double? lng;
    if (index >= 0 && index < _autocompleteLocations.length) {
      lat = _autocompleteLocations[index].latitude;
      lng = _autocompleteLocations[index].longitude;
    }
    setState(() {
      _destController.text = displayText;
      _showAutocomplete = false;
      _autocompleteResults = [];
      _autocompleteLocations = [];
      _selectedDestLat = lat;
      _selectedDestLng = lng;
    });
    if (lat != null && lng != null) {
      final pos = LatLng(lat, lng);
      widget.formDestPreviewNotifier.value = pos;
      if (mounted) {
        widget.mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
      }
    }
  }

  void _requestRoute() async {
    if (widget.driverLat == null || widget.driverLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi driver belum tersedia.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_destController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi tujuan perjalanan terlebih dahulu.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    double? destLat = _selectedDestLat;
    double? destLng = _selectedDestLng;
    if (destLat == null || destLng == null) {
      setState(() => _loadingRoute = true);
      try {
        final destLocations = await locationFromAddress(
          '${_destController.text.trim()}, Indonesia',
        );
        if (destLocations.isEmpty) {
          if (mounted) {
            setState(() => _loadingRoute = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tujuan tidak ditemukan.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        final dest = destLocations.first;
        destLat = dest.latitude;
        destLng = dest.longitude;
      } catch (_) {
        if (mounted) {
          setState(() => _loadingRoute = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal memuat rute.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    final lat = widget.driverLat!;
    final lng = widget.driverLng!;
    setState(() => _loadingRoute = true);
    widget.onRouteRequest(
      lat,
      lng,
      widget.originText,
      destLat,
      destLng,
      _destController.text.trim(),
    );
    if (mounted) setState(() => _loadingRoute = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(bottom: context.responsive.spacing(24)),
          child: Padding(
            padding: EdgeInsets.all(context.responsive.spacing(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Rute Perjalanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // Form 1: Asal (auto)
                Text(
                  'Dari (lokasi driver)',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.originText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Form 2: Tujuan (ketik + autocomplete + Pilih di Map, seperti penumpang)
                Text(
                  'Tujuan',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                if (!_isMapSelectionMode &&
                    _showAutocomplete &&
                    _autocompleteResults.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      key: _autocompleteKey,
                      margin: const EdgeInsets.only(bottom: 8),
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 180
                          : 260,
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
                        itemCount: _autocompleteResults.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                        itemBuilder: (context, index) {
                          final p = _autocompleteResults[index];
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
                                fontSize: 13,
                                height: 1.3,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectDestination(p, index),
                          );
                        },
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _destController,
                        decoration: InputDecoration(
                          hintText: _isMapSelectionMode
                              ? 'Tap di map untuk pilih lokasi'
                              : 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                          hintStyle: TextStyle(
                            color: _isMapSelectionMode
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: _isMapSelectionMode
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: _destController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    _destController.clear();
                                    setState(() {
                                      _autocompleteResults = [];
                                      _autocompleteLocations = [];
                                      _showAutocomplete = false;
                                      _selectedDestLat = null;
                                      _selectedDestLng = null;
                                      _isMapSelectionMode = false;
                                    });
                                    widget.formDestMapModeNotifier.value =
                                        false;
                                    widget.formDestPreviewNotifier.value = null;
                                  },
                                )
                              : null,
                        ),
                        enabled: !_isMapSelectionMode,
                        onChanged: (value) {
                          setState(() {});
                          _onDestinationChanged(value);
                        },
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _isMapSelectionMode
                            ? Icons.check_circle
                            : Icons.location_on,
                      ),
                      color: _isMapSelectionMode
                          ? Colors.blue.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      tooltip: _isMapSelectionMode
                          ? 'Selesai pilih lokasi'
                          : 'Pilih di Map',
                      onPressed: () {
                        setState(() {
                          _isMapSelectionMode = !_isMapSelectionMode;
                        });
                        widget.formDestMapModeNotifier.value =
                            _isMapSelectionMode;
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: _isMapSelectionMode
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                            : null,
                      ),
                    ),
                  ],
                ),
                if (_isMapSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap di peta utama (bagian atas) untuk memilih lokasi tujuan',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadingRoute ? null : _requestRoute,
                  icon: const Icon(Icons.directions_car, size: 20),
                  label: const Text('Rute Perjalanan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (_loadingRoute)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet untuk Oper Driver: pilih order (multi), input driver kedua, validasi kapasitas.
/// Kirim barang tidak bisa dioper.
class _OperDriverSheet extends StatefulWidget {
  final List<OrderModel> orders;
  final void Function(List<(String, String)> transfers) onTransfersCreated;

  const _OperDriverSheet({
    required this.orders,
    required this.onTransfersCreated,
  });

  @override
  State<_OperDriverSheet> createState() => _OperDriverSheetState();
}

class _OperDriverSheetState extends State<_OperDriverSheet> {
  final Set<OrderModel> _selectedOrders = {};
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  Map<String, dynamic>? _selectedDriverData;
  bool _loading = false;

  int get _totalPenumpang => _selectedOrders.fold(0, (s, o) => s + o.totalPenumpang);
  int get _driverCapacity => (_selectedDriverData?['vehicleJumlahPenumpang'] as int?) ?? 0;
  bool get _capacityOk => _driverCapacity > 0 && _totalPenumpang <= _driverCapacity;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDriverFromContacts() async {
    showDriverContactPicker(
      context: context,
      onSelect: (phone, data) {
        if (data != null) {
          setState(() {
            _phoneController.text = phone;
            _emailController.text = (data['email'] as String?) ?? '';
            _selectedDriverData = data;
          });
        }
      },
    );
  }

  Future<void> _submit() async {
    if (_selectedOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih pesanan yang akan dioper')),
      );
      return;
    }
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    if (email.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email dan nomor HP driver kedua wajib')),
      );
      return;
    }
    final driverData = _selectedDriverData;
    if (driverData == null || driverData['uid'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih driver kedua dari kontak yang terdaftar sebagai driver'),
        ),
      );
      return;
    }
    if (!_capacityOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kapasitas mobil driver kedua ($_driverCapacity orang) tidak cukup untuk $_totalPenumpang penumpang.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    final transfers = <(String, String)>[];
    for (final order in _selectedOrders) {
      final (transferId, barcodePayload, error) =
          await DriverTransferService.createTransfer(
        orderId: order.id,
        toDriverUid: driverData['uid'] as String,
        toDriverEmail: email,
        toDriverPhone: phone,
      );
      if (!mounted) return;
      if (error != null) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        return;
      }
      if (transferId != null && barcodePayload != null) {
        transfers.add((transferId, barcodePayload));
      }
    }
    setState(() => _loading = false);
    if (transfers.isNotEmpty) {
      widget.onTransfersCreated(transfers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(context.responsive.spacing(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Oper Driver',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Pilih penumpang yang sudah dijemput (sesuai kapasitas mobil driver kedua). Kirim barang tidak bisa dioper.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ...widget.orders.map((o) => CheckboxListTile(
                    title: Text(
                      '${o.passengerName} - ${o.destText}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${o.orderNumber ?? o.id} • ${o.totalPenumpang} orang'),
                    value: _selectedOrders.contains(o),
                    tristate: false,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedOrders.add(o);
                        } else {
                          _selectedOrders.remove(o);
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  )),
              if (_selectedOrders.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Total: $_totalPenumpang penumpang',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Driver kedua', style: TextStyle(fontWeight: FontWeight.w600)),
              if (_selectedDriverData != null && _driverCapacity > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Kapasitas mobil: $_driverCapacity orang',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              if (_selectedOrders.isNotEmpty && _driverCapacity > 0 && !_capacityOk)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Kapasitas tidak cukup ($_totalPenumpang > $_driverCapacity)',
                    style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w500),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _pickDriverFromContacts,
                    icon: const Icon(Icons.contacts),
                    tooltip: 'Pilih dari kontak',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'No. HP',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_loading || !_capacityOk) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_selectedOrders.length > 1
                        ? 'Buat ${_selectedOrders.length} Oper & Tampilkan Barcode'
                        : 'Buat Oper & Tampilkan Barcode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog menampilkan barcode untuk di-scan driver kedua (bisa banyak jika multi-oper).
class _OperDriverBarcodeDialog extends StatelessWidget {
  final List<(String, String)> transfers;

  const _OperDriverBarcodeDialog({required this.transfers});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        transfers.length > 1
            ? 'Tunjukkan barcode ke driver kedua (${transfers.length} transfer)'
            : 'Tunjukkan barcode ke driver kedua',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Driver kedua scan tiap barcode, lalu masukkan password akun.',
              style: TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ...transfers.asMap().entries.map((e) {
              final i = e.key + 1;
              final (_, payload) = e.value;
              return Padding(
                padding: EdgeInsets.only(bottom: i < transfers.length ? 24 : 0),
                child: Column(
                  children: [
                    if (transfers.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Transfer $i/${transfers.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

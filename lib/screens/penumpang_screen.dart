import 'dart:async';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';

import '../utils/placemark_formatter.dart';
import '../widgets/receiver_contact_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/location_service.dart';
import '../services/active_drivers_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../services/passenger_proximity_notification_service.dart';
import '../services/receiver_proximity_notification_service.dart';
import '../services/verification_service.dart';
import '../services/violation_service.dart';
import '../services/recent_destination_service.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/promotion_banner_widget.dart';
import 'data_order_screen.dart';
import 'violation_pay_screen.dart';
import 'pesan_screen.dart';
import 'chat_penumpang_screen.dart';
import 'chat_room_penumpang_screen.dart';
import 'profile_penumpang_screen.dart';

class PenumpangScreen extends StatefulWidget {
  final String? prefillOrigin;
  final String? prefillDest;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;

  const PenumpangScreen({
    super.key,
    this.prefillOrigin,
    this.prefillDest,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
  });

  @override
  State<PenumpangScreen> createState() => _PenumpangScreenState();
}

class _PenumpangScreenState extends State<PenumpangScreen> {
  int _currentIndex = 0;
  GoogleMapController? _mapController;
  MapType _mapType = MapType.hybrid; // Default: satelit dengan label
  Position? _currentPosition;
  String _currentLocationText = 'Mengambil lokasi...';
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();
  final GlobalKey _autocompleteKey = GlobalKey();
  final GlobalKey _formSectionKey = GlobalKey();
  List<Placemark> _autocompleteResults = [];
  bool _showAutocomplete = false;
  String? _currentKabupaten; // subAdministrativeArea (kabupaten/kota)
  String? _currentProvinsi; // administrativeArea (provinsi)
  String? _currentPulau; // pulau (diturunkan dari provinsi)
  Timer? _locationRefreshTimer;

  // State untuk driver aktif yang ditemukan
  List<ActiveDriverRoute> _foundDrivers = [];
  bool _isSearchingDrivers = false;
  double? _passengerDestLat;
  double? _passengerDestLng;

  // Cache untuk icon mobil (untuk menghindari load berulang)
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;
  // Gambar mobil untuk komposit dengan nama driver (nama di atas icon)
  ui.Image? _carImageRed;
  ui.Image? _carImageGreen;
  // Cache marker driver dengan nama di atas icon
  final Map<String, BitmapDescriptor> _driverMarkerIcons = {};

  // State untuk visibilitas form (disembunyikan setelah klik Cari)
  bool _isFormVisible = true;

  // State untuk tracking active travel order
  bool _hasActiveTravelOrder = false;

  // State untuk mode "Pilih di Map"
  bool _isMapSelectionMode = false;
  LatLng? _selectedDestinationPosition; // Posisi tujuan yang dipilih di map
  String? _selectedDestinationAddress; // Alamat dari reverse geocoding

  // Notifier untuk koordinasi form sheet dengan map (seperti driver)
  final ValueNotifier<bool> _formDestMapModeNotifier = ValueNotifier(false);
  final ValueNotifier<LatLng?> _formDestMapTapNotifier = ValueNotifier(null);

  // Badge unread chat penumpang
  StreamSubscription<List<OrderModel>>? _passengerOrdersSub;
  int _chatUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _destinationFocusNode.addListener(_onDestinationFocusChange);
    // Notifikasi: kesepakatan sudah terjadi + driver mendekati (5 km, 1 km, 500 m)
    PassengerProximityNotificationService.start();
    // Notifikasi penerima Lacak Barang: driver mendekati (5 km, 1 km, 500 m)
    ReceiverProximityNotificationService.start();
    // Cek apakah ada active travel order
    _checkActiveTravelOrder();
    _loadCarIcons();
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
              15.0,
            ),
          );
        }
      }
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _getCurrentLocation();
      });
    });
    // Refresh lokasi setiap 30 detik (hemat baterai & data)
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      _getCurrentLocation();
    });

    // Jika ada prefill origin dan dest, langsung cari driver aktif
    if (widget.prefillOrigin != null &&
        widget.prefillDest != null &&
        widget.originLat != null &&
        widget.originLng != null &&
        widget.destLat != null &&
        widget.destLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchDriversWithPrefill();
        }
      });
    }

    // Stream pesanan penumpang untuk badge unread chat
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _passengerOrdersSub =
          OrderService.streamOrdersForPassenger(includeHidden: false).listen(
        (orders) {
          if (!mounted) return;
          int count = 0;
          for (final o in orders) {
            if (o.lastMessageAt != null &&
                o.lastMessageSenderUid != uid &&
                (o.passengerLastReadAt == null ||
                    o.lastMessageAt!.isAfter(o.passengerLastReadAt!))) {
              count++;
            }
          }
          setState(() => _chatUnreadCount = count);
        },
      );
    }
  }

  /// Cari driver aktif dengan origin dan destination yang sudah diisi dari pesan_screen.
  Future<void> _searchDriversWithPrefill() async {
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    if (widget.originLat == null ||
        widget.originLng == null ||
        widget.destLat == null ||
        widget.destLng == null) {
      return;
    }

    // Set destination controller dengan prefill dest
    if (widget.prefillDest != null) {
      _destinationController.text = widget.prefillDest!;
      _passengerDestLat = widget.destLat;
      _passengerDestLng = widget.destLng;
    }

    // Set current position dengan origin yang sudah diisi
    if (widget.originLat != null && widget.originLng != null) {
      setState(() {
        _currentPosition = Position(
          latitude: widget.originLat!,
          longitude: widget.originLng!,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
        _currentLocationText = widget.prefillOrigin ?? 'Lokasi awal';
      });
    }

    // Langsung cari driver aktif menggunakan logika yang sama
    setState(() {
      _isSearchingDrivers = true;
      _foundDrivers = [];
    });

    try {
      final drivers = await ActiveDriversService.getActiveDriversForMap(
        passengerOriginLat: widget.originLat,
        passengerOriginLng: widget.originLng,
        passengerDestLat: widget.destLat,
        passengerDestLng: widget.destLng,
      );

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _isFormVisible = false; // Sembunyikan form setelah pencarian berhasil
        });

        if (_foundDrivers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tidak ada driver aktif yang sesuai dengan rute tujuan. Coba Pesan nanti untuk jadwal terjadwal.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          await _buildDriverMarkerIconsWithNames();
          if (mounted) _updateMapCameraForDrivers();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mencari driver: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Cek apakah penumpang memiliki active travel order (agreed atau picked_up).
  /// Hanya untuk order type travel (bukan kirim barang).
  Future<void> _checkActiveTravelOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = false;
        });
      }
      return;
    }

    try {
      final orders = await OrderService.getOrdersForPassenger(user.uid);
      final activeTravelOrder = orders.where((order) {
        // Hanya order type travel (bukan kirim barang)
        if (order.orderType != OrderModel.typeTravel) return false;
        // Status harus agreed atau picked_up
        return order.status == OrderService.statusAgreed ||
            order.status == OrderService.statusPickedUp;
      }).isNotEmpty;

      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = activeTravelOrder;
        });
        // Overlay sudah ditampilkan di _buildHomeScreen() saat _hasActiveTravelOrder true
      }
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) debugPrint('PenumpangScreen._checkActiveTravelOrder error: $e');
      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = false;
        });
      }
    }
  }

  void _onDestinationFocusChange() {
    if (_destinationFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _formSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _passengerOrdersSub?.cancel();
    _destinationFocusNode.removeListener(_onDestinationFocusChange);
    _destinationFocusNode.dispose();
    _locationRefreshTimer?.cancel();
    _destinationController.dispose();
    _formDestMapModeNotifier.dispose();
    _formDestMapTapNotifier.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Cek pelanggaran belum bayar; jika ada, redirect ke layar bayar dan return true.
  Future<bool> _checkAndRedirectIfOutstandingViolation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final hasOutstanding = await ViolationService.hasOutstandingViolation(user.uid);
    if (hasOutstanding && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ViolationPayScreen(),
        ),
      );
      return true;
    }
    return false;
  }

  /// Fungsi tombol Cari: tetap di halaman beranda dan tampilkan driver aktif sesuai kriteria
  Future<void> _onSearch() async {
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    // Validasi: form tujuan harus diisi
    final tujuanText = _destinationController.text.trim();
    if (tujuanText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan isi tujuan perjalanan terlebih dahulu'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validasi: lokasi penumpang harus tersedia
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menunggu lokasi penumpang...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Keluar dari mode map selection saat mulai mencari
    setState(() {
      _isMapSelectionMode = false;
      _isSearchingDrivers = true;
      _foundDrivers = [];
    });

    try {
      // Geocode tujuan penumpang untuk mendapatkan koordinat
      // Prioritas: gunakan koordinat dari map selection jika ada, jika tidak geocode dari text
      double? destLat = _passengerDestLat;
      double? destLng = _passengerDestLng;

      if (destLat == null || destLng == null) {
        try {
          final locations = await locationFromAddress(tujuanText);
          if (locations.isNotEmpty) {
            destLat = locations.first.latitude;
            destLng = locations.first.longitude;
            _passengerDestLat = destLat;
            _passengerDestLng = destLng;
            // Update marker tujuan jika belum ada
            if (_selectedDestinationPosition == null) {
              _selectedDestinationPosition = LatLng(destLat, destLng);
              _selectedDestinationAddress = tujuanText;
            }
          } else {
            throw Exception('Tujuan tidak ditemukan');
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isSearchingDrivers = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gagal menemukan tujuan: $e'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      // Cari driver aktif sesuai kriteria:
      // - Rute driver harus melewati lokasi awal dan tujuan penumpang (berdasarkan polyline)
      // - Sebelum driver melewati titik awal penumpang: jarak <= 50 km dari titik awal penumpang, maksimal 20 driver
      // - Setelah driver melewati titik awal penumpang: jarak <= 10 km dari titik awal penumpang, maksimal 10 driver
      final drivers = await ActiveDriversService.getActiveDriversForMap(
        passengerOriginLat: _currentPosition!.latitude,
        passengerOriginLng: _currentPosition!.longitude,
        passengerDestLat: destLat,
        passengerDestLng: destLng,
      );

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _isFormVisible = false; // Sembunyikan form setelah pencarian berhasil
        });

        if (_foundDrivers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tidak ada driver aktif yang sesuai dengan rute tujuan. Coba Pesan nanti untuk jadwal terjadwal.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          await _buildDriverMarkerIconsWithNames();
          if (mounted) _updateMapCameraForDrivers();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mencari driver: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _currentLocationText = 'Izin lokasi tidak diberikan';
        });
      }
      return;
    }

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

      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _currentLocationText = 'GPS tidak aktif. Silakan aktifkan GPS.';
          });
        }
        return;
      }
    }

    try {
      // Force refresh untuk mendapatkan lokasi terbaru (tidak cache)
      // Retry maksimal 2 kali jika gagal mendapatkan lokasi
      Position? position;
      for (int retry = 0; retry < 3; retry++) {
        final result =
            await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: true,
        );
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
        final result =
            await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: true,
        );
        if (result.isFakeGpsDetected) {
          if (mounted) FakeGpsOverlayService.showOverlay();
          return;
        }
        position = result.position;
      }

      if (position != null && mounted) {
        final previousPosition = _currentPosition;
        setState(() {
          _currentPosition = position;
        });
        await _updateLocationText(position);

        // Update marker di maps jika lokasi berubah signifikan (lebih dari 10 meter)
        if (previousPosition != null) {
          final distance = Geolocator.distanceBetween(
            previousPosition.latitude,
            previousPosition.longitude,
            position.latitude,
            position.longitude,
          );

          // Jika perpindahan lebih dari 10 meter, update camera
          if (distance > 10 && _mapController != null && mounted) {
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(
                LatLng(position.latitude, position.longitude),
              ),
            );
          }
        } else if (_mapController != null && mounted) {
          // Jika ini pertama kali dapat lokasi, animate ke lokasi tersebut
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude),
              15.0,
            ),
          );
        }
      } else if (mounted) {
        setState(() {
          _currentLocationText = 'Tidak dapat memperoleh lokasi';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocationText = 'Error: $e';
        });
      }
    }
  }

  Future<void> _updateLocationText(Position position) async {
    try {
      // Pastikan menggunakan koordinat terbaru, bukan cache
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final provinsi = place.administrativeArea ?? '';
        final kabupaten = place.subAdministrativeArea ?? '';

        // Pastikan state masih mounted sebelum update
        if (!mounted) return;

        setState(() {
          _currentProvinsi = provinsi.isNotEmpty ? provinsi : null;
          _currentKabupaten = kabupaten.isNotEmpty ? kabupaten : null;
          _currentPulau = _derivePulauFromProvinsi(provinsi);
          // Format untuk lokasi asal: hanya kecamatan, kabupaten, provinsi
          _currentLocationText = _formatPlacemarkForOrigin(place);
        });
      } else if (mounted) {
        // Jika tidak ada placemark, tampilkan koordinat
        setState(() {
          _currentLocationText =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocationText =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  /// Mengembalikan nama pulau dari nama provinsi (Indonesia).
  String? _derivePulauFromProvinsi(String provinsi) {
    if (provinsi.isEmpty) return null;
    final p = provinsi.toLowerCase();
    if (p.contains('kalimantan')) return 'Kalimantan';
    if (p.contains('jawa')) return 'Jawa';
    if (p.contains('sumatra') || p.contains('sumatera')) return 'Sumatra';
    if (p.contains('sulawesi')) return 'Sulawesi';
    if (p.contains('bali')) return 'Bali';
    if (p.contains('nusa tenggara')) return 'Nusa Tenggara';
    if (p.contains('maluku')) return 'Maluku';
    if (p.contains('papua')) return 'Papua';
    return null;
  }

  Future<void> _onDestinationChanged(String value) async {
    if (value.isEmpty || value.trim().isEmpty) {
      setState(() {
        _autocompleteResults = [];
        _showAutocomplete = false;
      });
      return;
    }

    // Debounce singkat agar pilihan muncul saat ketik (termasuk 1 huruf)
    await Future.delayed(const Duration(milliseconds: 100));

    // Pastikan value masih sama setelah debounce
    if (_destinationController.text != value || value.trim().isEmpty) {
      return;
    }

    try {
      // Pencarian bertingkat: kabupaten -> provinsi -> pulau/Indonesia
      // Mendukung nama tempat (rumah sakit, bandara, mall, dll.) dan alamat (jalan, desa, kecamatan, kabupaten, provinsi)
      final List<Location> allLocations = [];
      final Set<String> seenKeys = {}; // deduplikasi (lat,lng bulat)

      final queries = <String>[];
      final trimmedValue = value.trim();

      // Prioritas pencarian: mulai dari scope terkecil ke terbesar
      if ((_currentKabupaten ?? '').isNotEmpty) {
        queries.add('$trimmedValue, $_currentKabupaten, Indonesia');
      }
      if ((_currentProvinsi ?? '').isNotEmpty &&
          _currentProvinsi != _currentKabupaten) {
        queries.add('$trimmedValue, $_currentProvinsi, Indonesia');
      }
      if ((_currentPulau ?? '').isNotEmpty) {
        queries.add('$trimmedValue, $_currentPulau, Indonesia');
      }
      queries.add('$trimmedValue, Indonesia');

      // Cari untuk setiap query
      for (final query in queries) {
        if (_destinationController.text != value) break;
        try {
          final results = await locationFromAddress(query);
          for (final loc in results) {
            final key =
                '${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              allLocations.add(loc);
            }
            // Tingkatkan maksimal hasil dari 8 ke 10 untuk lebih banyak pilihan
            if (allLocations.length >= 10) break;
          }
          if (allLocations.length >= 10) break;
        } catch (_) {
          continue;
        }
      }

      // Pastikan value masih sama sebelum update UI
      if (_destinationController.text != value || value.trim().isEmpty) {
        return;
      }

      if (allLocations.isNotEmpty) {
        // Tingkatkan maksimal hasil yang ditampilkan dari 5 ke 8 untuk lebih banyak pilihan
        final limited = allLocations.take(8).toList();
        final placemarks = <Placemark>[];
        final firstLocation =
            limited.first; // Simpan lokasi pertama untuk preview

        for (final location in limited) {
          if (_destinationController.text != value) break;
          try {
            final list = await placemarkFromCoordinates(
              location.latitude,
              location.longitude,
            );
            if (list.isNotEmpty) {
              placemarks.add(list.first);
            }
          } catch (_) {}
        }

        // Pastikan value masih sama sebelum update UI
        if (_destinationController.text == value && value.trim().isNotEmpty) {
          setState(() {
            _autocompleteResults = placemarks;
            _showAutocomplete = placemarks.isNotEmpty;
          });

          // Scroll agar dropdown terlihat di atas keyboard
          if (placemarks.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autocompleteKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _autocompleteKey.currentContext!,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          }

          // Move camera ke hasil pertama untuk preview (jika ada hasil)
          // Jangan tampilkan pin di preview, hanya saat user memilih
          if (placemarks.isNotEmpty && _mapController != null && mounted) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(firstLocation.latitude, firstLocation.longitude),
                14.0, // Zoom level untuk preview (sedikit lebih jauh dari saat dipilih)
              ),
            );
          }
        }
      } else {
        // Tidak ada hasil ditemukan
        if (_destinationController.text == value) {
          setState(() {
            _autocompleteResults = [];
            _showAutocomplete = false;
          });
        }
      }
    } catch (e) {
      // Jika error, sembunyikan autocomplete
      if (_destinationController.text == value) {
        setState(() {
          _autocompleteResults = [];
          _showAutocomplete = false;
        });
      }
    }
  }

  String _formatPlacemarkForOrigin(Placemark placemark) =>
      PlacemarkFormatter.formatShort(placemark);

  String _formatPlacemarkDetail(Placemark placemark) =>
      PlacemarkFormatter.formatDetail(placemark);

  void _selectAutocompleteResult(Placemark placemark) async {
    final displayText = _formatPlacemarkDetail(placemark);

    setState(() {
      _destinationController.text = displayText;
      _showAutocomplete = false;
      _autocompleteResults = [];
      // Tetap aktifkan mode map selection agar pin bisa dipindahkan
      _isMapSelectionMode = true;
    });

    // Simpan koordinat tujuan untuk pencarian driver
    try {
      final locations = await locationFromAddress(displayText);
      if (locations.isNotEmpty) {
        _passengerDestLat = locations.first.latitude;
        _passengerDestLng = locations.first.longitude;
        // Tampilkan pin otomatis di posisi yang disarankan
        _selectedDestinationPosition = LatLng(
          _passengerDestLat!,
          _passengerDestLng!,
        );
        _selectedDestinationAddress = displayText;

        // Move camera ke lokasi tujuan agar mudah untuk tap/pin
        if (_mapController != null && mounted) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(_passengerDestLat!, _passengerDestLng!),
              15.0, // Zoom level yang cukup dekat untuk melihat detail
            ),
          );
        }

        // Update state untuk menampilkan pin
        if (mounted) {
          setState(() {});
        }
      }
    } catch (_) {
      _passengerDestLat = null;
      _passengerDestLng = null;
    }
  }

  /// Handler saat user tap di map untuk memilih lokasi tujuan
  void _onMapTapped(LatLng position) async {
    if (!_isMapSelectionMode) return;

    setState(() {
      _selectedDestinationPosition = position;
      _passengerDestLat = position.latitude;
      _passengerDestLng = position.longitude;
      _selectedDestinationAddress = 'Memuat alamat...';
    });

    // Reverse geocode untuk mendapatkan alamat
    await _reverseGeocodeDestination(position);
  }

  /// Handler saat marker tujuan di-drag
  void _onDestinationMarkerDragged(LatLng newPosition) async {
    setState(() {
      _selectedDestinationPosition = newPosition;
      _passengerDestLat = newPosition.latitude;
      _passengerDestLng = newPosition.longitude;
      _selectedDestinationAddress = 'Memuat alamat...';
    });

    // Reverse geocode untuk mendapatkan alamat baru
    await _reverseGeocodeDestination(newPosition);
  }

  /// Reverse geocode koordinat menjadi alamat dan update form
  Future<void> _reverseGeocodeDestination(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final displayText = _formatPlacemarkDetail(placemark);

        if (mounted) {
          setState(() {
            _selectedDestinationAddress = displayText;
            _destinationController.text = displayText;
            // Tutup autocomplete jika terbuka
            _showAutocomplete = false;
            _autocompleteResults = [];
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _selectedDestinationAddress = 'Lokasi tidak ditemukan';
            _destinationController.text =
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          });
        }
      }
    } catch (e) {
      // Jika error, gunakan koordinat sebagai fallback
      if (mounted) {
        setState(() {
          _selectedDestinationAddress =
              'Koordinat: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          _destinationController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  void _toggleMapType() {
    setState(() {
      // Toggle antara normal dan hybrid (satelit dengan label)
      _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  /// Buka form pencarian dalam modal bottom sheet (seperti form driver)
  void _showSearchFormSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PenumpangRouteFormSheet(
        originText: _currentLocationText,
        currentKabupaten: _currentKabupaten,
        currentProvinsi: _currentProvinsi,
        currentPulau: _currentPulau,
        originLat: _currentPosition?.latitude,
        originLng: _currentPosition?.longitude,
        initialDest: _destinationController.text.trim().isEmpty
            ? null
            : _destinationController.text,
        mapController: _mapController,
        formDestMapModeNotifier: _formDestMapModeNotifier,
        formDestMapTapNotifier: _formDestMapTapNotifier,
        onSearch: (
          String destText,
          double destLat,
          double destLng,
        ) async {
          Navigator.pop(ctx);
          await _onSearchFromSheet(destText, destLat, destLng);
        },
      ),
    );
  }

  /// Handler Cari dari form sheet
  Future<void> _onSearchFromSheet(
    String destText,
    double destLat,
    double destLng,
  ) async {
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    RecentDestinationService.add(destText, lat: destLat, lng: destLng);
    setState(() {
      _destinationController.text = destText;
      _passengerDestLat = destLat;
      _passengerDestLng = destLng;
      _selectedDestinationPosition = LatLng(destLat, destLng);
      _selectedDestinationAddress = destText;
      _isMapSelectionMode = false;
      _formDestMapModeNotifier.value = false;
      _isSearchingDrivers = true;
      _foundDrivers = [];
    });

    if (_currentPosition == null) {
      setState(() => _isSearchingDrivers = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Menunggu lokasi penumpang...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      final drivers = await ActiveDriversService.getActiveDriversForMap(
        passengerOriginLat: _currentPosition!.latitude,
        passengerOriginLng: _currentPosition!.longitude,
        passengerDestLat: destLat,
        passengerDestLng: destLng,
      );

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _isFormVisible = false;
        });

        if (_foundDrivers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tidak ada driver aktif yang sesuai dengan rute tujuan. Coba Pesan nanti untuk jadwal terjadwal.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          await _buildDriverMarkerIconsWithNames();
          if (mounted) _updateMapCameraForDrivers();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingDrivers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mencari driver: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Build markers untuk map: lokasi penumpang + driver aktif
  Set<Marker> _buildMarkers({bool isVerified = false}) {
    final markers = <Marker>{};

    // Marker lokasi penumpang
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Lokasi Anda'),
        ),
      );
    }

    // Marker tujuan yang dipilih di map (bisa di-drag)
    if (_selectedDestinationPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_destination'),
          position: _selectedDestinationPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Tujuan',
            snippet: _selectedDestinationAddress ?? 'Memuat alamat...',
          ),
          draggable: true,
          onDragEnd: (newPosition) {
            _onDestinationMarkerDragged(newPosition);
          },
        ),
      );
    }

    // Marker driver aktif: icon dengan nama driver di atas icon mobil
    for (final driver in _foundDrivers) {
      final icon =
          _driverMarkerIcons[driver.driverUid] ??
          (driver.isMoving ? _carIconGreen : _carIconRed) ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

      final distanceText = _currentPosition != null
          ? _formatDistanceMeters(
              Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                driver.driverLat,
                driver.driverLng,
              ),
            )
          : null;

      markers.add(
        Marker(
          markerId: MarkerId(driver.driverUid),
          position: LatLng(driver.driverLat, driver.driverLng),
          icon: icon,
          infoWindow: InfoWindow(
            title: driver.driverName ?? 'Driver',
            snippet: distanceText,
          ),
          onTap: () => _showDriverDetailSheet(driver, isVerified),
        ),
      );
    }

    return markers;
  }

  /// Load icon mobil dari assets (car_merah.png dan car_hijau.png)
  /// Icon mobil default menghadap ke bawah (posisi depan mobil di gambar menghadap ke bawah)
  Future<void> _loadCarIcons() async {
    try {
      // Load car_merah.png (untuk driver tidak bergerak)
      final redIconPath = 'assets/images/car_merah.png';
      final redData = await rootBundle.load(redIconPath);
      final redCodec = await ui.instantiateImageCodec(
        redData.buffer.asUint8List(),
        targetWidth: 50, // Ukuran icon mobil
      );
      final redFrameInfo = await redCodec.getNextFrame();
      final redImage = redFrameInfo.image;
      _carImageRed = redImage;

      // Buat canvas dengan padding untuk menghindari icon terpotong
      const padding = 15.0;
      final imageWidth = redImage.width.toDouble();
      final imageHeight = redImage.height.toDouble();
      final maxDimension = imageWidth > imageHeight ? imageWidth : imageHeight;
      final canvasSize = (maxDimension + padding * 2).toInt();

      final redRecorder = ui.PictureRecorder();
      final redCanvas = Canvas(redRecorder);
      redCanvas.drawImage(
        redImage,
        Offset((canvasSize - imageWidth) / 2, (canvasSize - imageHeight) / 2),
        Paint(),
      );
      final redPicture = redRecorder.endRecording();
      final redFinalImage = await redPicture.toImage(canvasSize, canvasSize);
      final redByteData = await redFinalImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (redByteData != null) {
        _carIconRed = BitmapDescriptor.fromBytes(
          redByteData.buffer.asUint8List(),
        );
      }

      // Load car_hijau.png (untuk driver bergerak)
      final greenIconPath = 'assets/images/car_hijau.png';
      final greenData = await rootBundle.load(greenIconPath);
      final greenCodec = await ui.instantiateImageCodec(
        greenData.buffer.asUint8List(),
        targetWidth: 50, // Ukuran icon mobil
      );
      final greenFrameInfo = await greenCodec.getNextFrame();
      final greenImage = greenFrameInfo.image;
      _carImageGreen = greenImage;

      final greenRecorder = ui.PictureRecorder();
      final greenCanvas = Canvas(greenRecorder);
      greenCanvas.drawImage(
        greenImage,
        Offset((canvasSize - imageWidth) / 2, (canvasSize - imageHeight) / 2),
        Paint(),
      );
      final greenPicture = greenRecorder.endRecording();
      final greenFinalImage = await greenPicture.toImage(
        canvasSize,
        canvasSize,
      );
      final greenByteData = await greenFinalImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (greenByteData != null) {
        _carIconGreen = BitmapDescriptor.fromBytes(
          greenByteData.buffer.asUint8List(),
        );
      }

      if (mounted) {
        setState(() {}); // Trigger rebuild untuk update marker
      }
    } catch (e) {
      // Fallback ke default marker jika gagal load icon
      _carIconRed = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      );
      _carIconGreen = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
    }
  }

  /// Buat icon marker driver dengan nama di atas icon mobil
  Future<void> _buildDriverMarkerIconsWithNames() async {
    _driverMarkerIcons.clear();
    if (_carImageRed == null && _carImageGreen == null) return;

    for (final driver in _foundDrivers) {
      final carImage = driver.isMoving ? _carImageGreen : _carImageRed;
      if (carImage == null) continue;

      final name = driver.driverName ?? 'Driver';
      final displayName = name.length > 14 ? '${name.substring(0, 13)}…' : name;

      final textPainter = TextPainter(
        text: TextSpan(
          text: displayName,
          style: const TextStyle(
            color: AppTheme.primary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(minWidth: 0, maxWidth: 140);

      final carWidth = carImage.width.toDouble();
      final carHeight = carImage.height.toDouble();
      final textW = textPainter.width.ceilToDouble().clamp(40.0, 100.0);
      final textH = textPainter.height.ceilToDouble();
      const padding = 4.0;
      final totalW = (textW > carWidth ? textW : carWidth) + padding * 2;
      final w = totalW.ceil();
      final h = (textH + padding + carHeight + padding).ceil();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final nameRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w.toDouble(), textH + padding * 2),
        const Radius.circular(4),
      );
      canvas.drawRRect(nameRect, Paint()..color = Theme.of(context).colorScheme.surface);
      canvas.drawRRect(
        nameRect,
        Paint()
          ..color = Theme.of(context).colorScheme.onSurface.withOpacity(0.26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      textPainter.paint(canvas, Offset((w - textPainter.width) / 2, padding));

      canvas.drawImage(
        carImage,
        Offset((w - carWidth) / 2, textH + padding * 2),
        Paint(),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        _driverMarkerIcons[driver.driverUid] = BitmapDescriptor.fromBytes(
          byteData.buffer.asUint8List(),
        );
      }
    }

    if (mounted) setState(() {});
  }

  /// Format jarak dalam meter ke teks singkat (m atau km).
  String _formatDistanceMeters(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// Format tujuan hanya kecamatan dan kabupaten (dari teks alamat lengkap).
  String _formatTujuanKecamatanKabupaten(String? fullAddress) {
    if (fullAddress == null || fullAddress.trim().isEmpty) return '-';
    final parts = fullAddress
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}, ${parts[parts.length - 1]}';
    }
    return fullAddress;
  }

  /// Satu baris isi data mobil dari driver: merek + type (tanpa label).
  String _formatDataMobilDriver(ActiveDriverRoute driver) {
    final merek = (driver.vehicleMerek ?? '').trim();
    final type = (driver.vehicleType ?? '').trim();
    if (merek.isEmpty && type.isEmpty) return '-';
    if (merek.isEmpty) return type;
    if (type.isEmpty) return merek;
    return '$merek $type';
  }

  /// Tampilkan profil driver dan opsi pesan travel (nama di atas, profil di bawah, tujuan kecamatan+kabupaten).
  void _showDriverDetailSheet(ActiveDriverRoute driver, bool isVerified) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(ctx.responsive.horizontalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nama driver di atas + ikon terverifikasi (centang) jika sudah verifikasi
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    driver.driverName ?? 'Driver',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (driver.isVerified) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.verified,
                    size: 24,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ],
              ],
            ),
            if (driver.averageRating != null && driver.reviewCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star, size: 18, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '${driver.averageRating!.toStringAsFixed(1)} (${driver.reviewCount} ulasan)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(ctx).colorScheme.outline,
                  backgroundImage:
                      (driver.driverPhotoUrl != null &&
                          driver.driverPhotoUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(driver.driverPhotoUrl!)
                      : null,
                  child:
                      (driver.driverPhotoUrl == null ||
                          driver.driverPhotoUrl!.isEmpty)
                      ? Icon(
                          Icons.person,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          size: 28,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tujuan: ${_formatTujuanKecamatanKabupaten(driver.routeDestText)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDataMobilDriver(driver),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.people, size: 18, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            driver.remainingPassengerCapacity != null
                                ? (driver.hasPassengerCapacity
                                      ? 'Sisa ${driver.remainingPassengerCapacity} kursi'
                                      : 'Penuh')
                                : (driver.maxPassengers != null
                                      ? '${driver.maxPassengers} kursi'
                                      : '-'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: driver.hasPassengerCapacity
                                  ? AppTheme.primary
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: driver.hasPassengerCapacity
                        ? () => _onPesanTravelOrCheck(driver, isVerified)
                        : null,
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    label: Text(
                      driver.hasPassengerCapacity ? 'Pesan Travel' : 'Penuh',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _onKirimBarangOrCheck(driver, isVerified),
                    icon: const Icon(Icons.inventory_2, size: 20),
                    label: const Text('Kirim Barang'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cek verifikasi sebelum pesan travel; jika belum lengkap tampilkan dialog.
  void _onPesanTravelOrCheck(ActiveDriverRoute driver, bool isVerified) {
    if (!isVerified) {
      _showLengkapiVerifikasiDialog();
      return;
    }
    _showPilihanPesanTravel(driver);
  }

  /// Cek verifikasi sebelum kirim barang; jika belum lengkap tampilkan dialog.
  void _onKirimBarangOrCheck(ActiveDriverRoute driver, bool isVerified) {
    if (!isVerified) {
      _showLengkapiVerifikasiDialog();
      return;
    }
    _onKirimBarang(driver);
  }

  void _showLengkapiVerifikasiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lengkapi data verifikasi'),
        content: const Text(
          'Lengkapi data verifikasi terlebih dahulu untuk memesan travel atau kirim barang.',
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

  /// Tampilkan pilihan: pesan travel sendiri atau dengan kerabat
  void _showPilihanPesanTravel(ActiveDriverRoute driver) {
    Navigator.pop(context); // Tutup bottom sheet profil driver
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(ctx.responsive.horizontalPadding),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pesan Travel',
                style: TextStyle(
                  fontSize: ctx.responsive.fontSize(18),
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: ctx.responsive.spacing(8)),
              Text(
                'Pilih jenis pemesanan',
                style: TextStyle(
                  fontSize: ctx.responsive.fontSize(14),
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                  child: const Icon(Icons.person, color: AppTheme.primary),
                ),
                title: const Text('Pesan travel sendiri'),
                subtitle: const Text('Pesan untuk perjalanan Anda sendiri'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onPesanTravel(driver, withKerabat: false);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                  child: const Icon(Icons.group, color: AppTheme.primary),
                ),
                title: const Text('Pesan travel dengan kerabat'),
                subtitle: const Text('Pesan untuk 2+ orang — Anda + keluarga/teman yang ikut'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  _showInputJumlahKerabat(driver);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog input jumlah kerabat lalu lanjut pesan travel dengan kerabat.
  /// Validasi pakai sisa kapasitas mobil (remainingPassengerCapacity), bukan kapasitas total.
  void _showInputJumlahKerabat(ActiveDriverRoute driver) {
    // Sisa kursi = yang masih bisa diisi (sesuai kapasitas mobil dikurangi penumpang yang sudah agreed/picked_up)
    final sisaKursi =
        driver.remainingPassengerCapacity ?? driver.maxPassengers ?? 10;
    final maxKerabat = (sisaKursi - 1).clamp(
      0,
      9,
    ); // minus 1 untuk pemesan sendiri, max 9 kerabat

    if (maxKerabat < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sisa kursi hanya 1. Silakan pilih "Pesan travel sendiri".',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final controller = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jumlah orang yang ikut'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Berapa orang yang ikut bersama Anda? (Sisa kursi mobil: $sisaKursi)',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Jumlah orang yang ikut (selain Anda)',
                  hintText: '1',
                  border: const OutlineInputBorder(),
                  helperText:
                      'Contoh: Anda + 2 anak → isi 2 (total 3 penumpang). Maks. $maxKerabat (Anda + $maxKerabat orang = $sisaKursi penumpang)',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1) return 'Minimal 1 orang ikut';
                  if (n > maxKerabat)
                    return 'Maksimal $maxKerabat (sisa kursi mobil $sisaKursi)';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final n = int.tryParse(controller.text) ?? 1;
              Navigator.pop(ctx);
              _onPesanTravel(driver, withKerabat: true, jumlahKerabat: n);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }

  /// Fungsi untuk pesan travel ke driver
  Future<void> _onPesanTravel(
    ActiveDriverRoute driver, {
    bool withKerabat = false,
    int? jumlahKerabat,
  }) async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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

    final asal =
        _currentLocationText != 'Mengambil lokasi...' &&
            _currentLocationText.isNotEmpty
        ? _currentLocationText
        : 'Lokasi penjemputan';
    final tujuan = _destinationController.text.trim().isNotEmpty
        ? _destinationController.text.trim()
        : 'Tujuan';

    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: driver.driverUid,
      routeJourneyNumber: driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      originText: asal,
      destText: tujuan,
      originLat: _currentPosition?.latitude,
      originLng: _currentPosition?.longitude,
      destLat: _passengerDestLat,
      destLng: _passengerDestLng,
      orderType: OrderModel.typeTravel,
      jumlahKerabat: withKerabat ? (jumlahKerabat ?? 1) : null,
    );

    // Format pesan otomatis pertama ke driver (profesional & tegas).
    final String driverName = driver.driverName ?? 'Driver';
    final String jenisPesanan = withKerabat
        ? 'Saya ingin memesan tiket travel untuk ${1 + (jumlahKerabat ?? 1)} orang (dengan kerabat).'
        : 'Saya ingin memesan tiket travel untuk 1 orang.';
    final String jenisPesananMessage =
        'Halo Pak $driverName,\n\n'
        '$jenisPesanan\n\n'
        'Dari: $asal\n'
        'Tujuan: $tujuan\n\n'
        'Mohon informasi tarif untuk rute ini.';

    if (!mounted) return;
    if (orderId != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomPenumpangScreen(
            orderId: orderId,
            driverUid: driver.driverUid,
            driverName: driver.driverName ?? 'Driver',
            driverPhotoUrl: driver.driverPhotoUrl,
            driverVerified: driver.isVerified,
            sendJenisPesananMessage: jenisPesananMessage,
          ),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membuat pesanan. Silakan coba lagi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Kirim Barang: tautkan penerima (cari email/telp) → tampil foto+nama → Iya → buat order pending_receiver, buka chat.
  Future<void> _onKirimBarang(ActiveDriverRoute driver) async {
    Navigator.pop(context); // Tutup bottom sheet profil driver
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final asal =
        _currentLocationText != 'Mengambil lokasi...' &&
            _currentLocationText.isNotEmpty
        ? _currentLocationText
        : 'Lokasi penjemputan';
    final tujuan = _destinationController.text.trim().isNotEmpty
        ? _destinationController.text.trim()
        : 'Tujuan';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KirimBarangLinkReceiverSheet(
        driver: driver,
        asal: asal,
        tujuan: tujuan,
        originLat: _currentPosition?.latitude,
        originLng: _currentPosition?.longitude,
        destLat: _passengerDestLat,
        destLng: _passengerDestLng,
        onOrderCreated: (orderId, message) {
          Navigator.pop(ctx);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatRoomPenumpangScreen(
                orderId: orderId,
                driverUid: driver.driverUid,
                driverName: driver.driverName ?? 'Driver',
                driverPhotoUrl: driver.driverPhotoUrl,
                driverVerified: driver.isVerified,
                sendJenisPesananMessage: message,
              ),
            ),
          );
        },
        onError: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );
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

  /// Update map camera ke area driver aktif (dan lokasi penumpang) dengan bounds + padding.
  /// Dipanggil setelah "Cari driver travel" berhasil menemukan driver.
  void _updateMapCameraForDrivers() {
    if (_foundDrivers.isEmpty) return;
    if (_currentPosition == null) return;

    double minLat = _currentPosition!.latitude;
    double maxLat = _currentPosition!.latitude;
    double minLng = _currentPosition!.longitude;
    double maxLng = _currentPosition!.longitude;

    for (final driver in _foundDrivers) {
      if (driver.driverLat < minLat) minLat = driver.driverLat;
      if (driver.driverLat > maxLat) maxLat = driver.driverLat;
      if (driver.driverLng < minLng) minLng = driver.driverLng;
      if (driver.driverLng > maxLng) maxLng = driver.driverLng;
    }

    // Beri margin agar bounds tidak nol (satu titik)
    final latMargin = (maxLat - minLat).abs() < 0.0001 ? 0.002 : 0.0;
    final lngMargin = (maxLng - minLng).abs() < 0.0001 ? 0.002 : 0.0;
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - latMargin, minLng - lngMargin),
      northeast: LatLng(maxLat + latMargin, maxLng + lngMargin),
    );

    void doAnimate() {
      if (!mounted) return;
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }

    if (_mapController != null && mounted) {
      doAnimate();
    } else {
      // Map belum siap; jadwalkan setelah controller tersedia
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (_mapController != null) doAnimate();
      });
    }
  }

  void _onTabTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
    });

    // Jika kembali ke halaman beranda (index 0), cek ulang active travel order
    if (index == 0) {
      _checkActiveTravelOrder();
    }
  }

  Widget _buildHomeScreen({
    Map<String, dynamic>? userData,
    bool isVerified = false,
  }) {
    // Jika ada active travel order, tampilkan blocking overlay
    if (_hasActiveTravelOrder) {
      return Stack(
        children: [
          // Background blur
          _buildActualHomeScreen(isVerified: isVerified),
          // Blocking overlay
          Container(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            child: Center(
              child: Padding(
                padding: context.responsive.cardMargin,
                child: Card(
                  child: Padding(
                    padding: context.responsive.cardPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: context.responsive.iconSize(64),
                        ),
                        SizedBox(height: context.responsive.spacing(16)),
                        Text(
                          'Pesanan Travel Aktif',
                          style: TextStyle(
                            fontSize: context.responsive.fontSize(18),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.responsive.spacing(12)),
                        Text(
                          'Anda punya pesanan travel aktif. Selesaikan atau batalkan untuk pesan lagi.',
                          style: TextStyle(
                            fontSize: context.responsive.fontSize(14),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.responsive.spacing(24)),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const DataOrderScreen(),
                              ),
                            ).then((_) {
                              _checkActiveTravelOrder();
                            });
                          },
                          icon: Icon(
                            Icons.receipt_long,
                            size: context.responsive.iconSize(20),
                          ),
                          label: const Text('Lihat Pesanan'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return _buildActualHomeScreen(isVerified: isVerified);
  }

  Widget _buildActualHomeScreen({bool isVerified = false}) {
    return Stack(
      children: [
        // Google Maps — RepaintBoundary agar tidak rebuild saat overlay/control berubah
        RepaintBoundary(
          child: GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(
            target: _currentPosition != null
                ? LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  )
                : const LatLng(
                    -3.3194,
                    114.5907,
                  ), // Default: Kalimantan Selatan
            zoom: 15.0,
          ),
          mapType: _mapType,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: _buildMarkers(isVerified: isVerified),
          onTap: (_isMapSelectionMode || _formDestMapModeNotifier.value)
              ? (LatLng pos) {
                  if (_formDestMapModeNotifier.value) {
                    _formDestMapTapNotifier.value = pos;
                  } else {
                    _onMapTapped(pos);
                  }
                }
              : null, // Aktif saat mode pilih di map (overlay atau sheet)
        ),
        ),

        const PromotionBannerWidget(role: 'penumpang'),

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

        // Quick action: Pesan nanti (ke Jadwal)
        if (_isFormVisible)
          Positioned(
            left: context.responsive.horizontalPadding,
            right: context.responsive.horizontalPadding,
            bottom: 148,
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onTabTapped(1),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, size: 18, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Pesan nanti',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Bar pencarian (tap untuk buka form dalam bottom sheet, seperti form driver)
        if (_isFormVisible)
          Positioned(
            left: context.responsive.horizontalPadding,
            right: context.responsive.horizontalPadding,
            bottom: 80,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _showSearchFormSheet,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: EdgeInsets.all(context.responsive.spacing(16)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: AppTheme.primary,
                        size: 24,
                      ),
                      SizedBox(width: context.responsive.spacing(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentLocationText,
                              style: TextStyle(
                                fontSize: context.responsive.fontSize(12),
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _destinationController.text.trim().isEmpty
                                  ? 'Masukkan tujuan (contoh: Bandara, Terminal)'
                                  : _destinationController.text,
                              style: TextStyle(
                                fontSize: context.responsive.fontSize(14),
                                fontWeight: FontWeight.w500,
                                color: _destinationController.text
                                        .trim()
                                        .isEmpty
                                    ? Theme.of(context).colorScheme.onSurfaceVariant
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Loading indicator saat mencari driver
        if (_isSearchingDrivers)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary),
                  const SizedBox(width: 16),
                  Text(
                    'Mencari driver...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.surface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Tombol icon rute untuk menampilkan kembali form (muncul ketika form disembunyikan)
        if (!_isFormVisible)
          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton(
              onPressed: () {
                setState(() {
                  _isFormVisible = true; // Tampilkan kembali form
                });
              },
              backgroundColor: AppTheme.primary,
              tooltip: 'Ubah rute',
              child: Icon(Icons.route, color: AppTheme.onPrimary),
            ),
          ),
      ],
    );
  }

  /// Penumpang profil lengkap & terverifikasi: Verifikasi KTP + Email & No.Telp.
  bool _isPenumpangProfileVerified(Map<String, dynamic> data) {
    final hasKTP = data['passengerKTPVerifiedAt'] != null ||
        data['passengerKTPNomorHash'] != null;
    final phone = ((data['phoneNumber'] as String?) ?? '').trim();
    return hasKTP && phone.isNotEmpty;
  }

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
        final isVerified = VerificationService.isPenumpangVerified(data);

        return Scaffold(
          body: _currentIndex == 0
              ? _buildHomeScreen(userData: data, isVerified: isVerified)
              : _buildOtherScreens(isVerified: isVerified),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppTheme.primary,
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
                  ? AppTheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 1
                  ? Icons.calendar_month
                  : Icons.calendar_month_outlined,
              color: _currentIndex == 1
                  ? AppTheme.primary
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
                          ? AppTheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    _currentIndex == 2
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                    color: _currentIndex == 2
                        ? AppTheme.primary
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
                  ? AppTheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: 'Pesanan',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 4 ? Icons.person : Icons.person_outline,
              color: _currentIndex == 4
                  ? AppTheme.primary
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

  Widget _buildOtherScreens({bool isVerified = false}) {
    switch (_currentIndex) {
      case 1:
        return PesanScreen(
          isVerified: isVerified,
          onVerificationRequired: () => setState(() => _currentIndex = 4),
        );
      case 2:
        return const ChatPenumpangScreen();
      case 3:
        return const DataOrderScreen();
      case 4:
        return const ProfilePenumpangScreen();
      default:
        return _buildHomeScreen();
    }
  }
}

/// Bottom sheet form pencarian penumpang (seperti form driver: di atas keyboard, pilihan muncul saat ketik).
class _PenumpangRouteFormSheet extends StatefulWidget {
  final String originText;
  final String? currentKabupaten;
  final String? currentProvinsi;
  final String? currentPulau;
  final double? originLat;
  final double? originLng;
  final String? initialDest;
  final GoogleMapController? mapController;
  final ValueNotifier<bool> formDestMapModeNotifier;
  final ValueNotifier<LatLng?> formDestMapTapNotifier;
  final void Function(String destText, double destLat, double destLng) onSearch;

  const _PenumpangRouteFormSheet({
    required this.originText,
    required this.currentKabupaten,
    required this.currentProvinsi,
    required this.currentPulau,
    required this.originLat,
    required this.originLng,
    this.initialDest,
    this.mapController,
    required this.formDestMapModeNotifier,
    required this.formDestMapTapNotifier,
    required this.onSearch,
  });

  @override
  State<_PenumpangRouteFormSheet> createState() =>
      _PenumpangRouteFormSheetState();
}

class _PenumpangRouteFormSheetState extends State<_PenumpangRouteFormSheet> {
  late final TextEditingController _destController =
      TextEditingController(text: widget.initialDest ?? '');
  final GlobalKey _autocompleteKey = GlobalKey();
  List<Placemark> _autocompleteResults = [];
  List<Location> _autocompleteLocations = [];
  bool _showAutocomplete = false;
  bool _isMapSelectionMode = false;
  double? _selectedDestLat;
  double? _selectedDestLng;

  @override
  void initState() {
    super.initState();
    widget.formDestMapTapNotifier.addListener(_onMapTapFromMain);
  }

  @override
  void dispose() {
    widget.formDestMapTapNotifier.removeListener(_onMapTapFromMain);
    widget.formDestMapModeNotifier.value = false;
    _destController.dispose();
    super.dispose();
  }

  void _onMapTapFromMain() {
    final pos = widget.formDestMapTapNotifier.value;
    if (pos != null && mounted) {
      widget.formDestMapTapNotifier.value = null;
      _onSheetMapTapped(pos);
    }
  }

  String _formatPlacemarkDetail(Placemark p) =>
      PlacemarkFormatter.formatDetail(p);

  Future<void> _onSheetMapTapped(LatLng position) async {
    setState(() {
      _selectedDestLat = position.latitude;
      _selectedDestLng = position.longitude;
      _destController.text = 'Memuat alamat...';
    });
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        setState(() {
          _destController.text = _formatPlacemarkDetail(placemarks.first);
          _showAutocomplete = false;
          _autocompleteResults = [];
        });
      } else if (mounted) {
        setState(() {
          _destController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
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
    if (value.isEmpty || value.trim().isEmpty) {
      setState(() {
        _autocompleteResults = [];
        _autocompleteLocations = [];
        _showAutocomplete = false;
        _selectedDestLat = null;
        _selectedDestLng = null;
      });
      return;
    }

    // Debounce singkat agar pilihan muncul saat ketik (termasuk 1 huruf)
    await Future.delayed(const Duration(milliseconds: 100));
    if (_destController.text != value || value.trim().isEmpty) return;

    try {
      final List<Location> allLocations = [];
      final Set<String> seenKeys = {};
      final queries = <String>[];
      final trimmedValue = value.trim();

      if ((widget.currentKabupaten ?? '').isNotEmpty) {
        queries.add('$trimmedValue, ${widget.currentKabupaten}, Indonesia');
      }
      if ((widget.currentProvinsi ?? '').isNotEmpty &&
          widget.currentProvinsi != widget.currentKabupaten) {
        queries.add('$trimmedValue, ${widget.currentProvinsi}, Indonesia');
      }
      if ((widget.currentPulau ?? '').isNotEmpty) {
        queries.add('$trimmedValue, ${widget.currentPulau}, Indonesia');
      }
      queries.add('$trimmedValue, Indonesia');

      for (final query in queries) {
        if (_destController.text != value) break;
        try {
          final results = await locationFromAddress(query);
          for (final loc in results) {
            final key =
                '${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              allLocations.add(loc);
            }
            if (allLocations.length >= 10) break;
          }
          if (allLocations.length >= 10) break;
        } catch (_) {
          continue;
        }
      }

      if (_destController.text != value || value.trim().isEmpty) return;

      if (allLocations.isNotEmpty) {
        final limited = allLocations.take(8).toList();
        final placemarks = <Placemark>[];
        for (final location in limited) {
          if (_destController.text != value) break;
          try {
            final list = await placemarkFromCoordinates(
              location.latitude,
              location.longitude,
            );
            if (list.isNotEmpty) placemarks.add(list.first);
          } catch (_) {}
        }

        if (_destController.text == value && value.trim().isNotEmpty && mounted) {
          setState(() {
            _autocompleteResults = placemarks;
            _autocompleteLocations = limited;
            _showAutocomplete = placemarks.isNotEmpty;
          });
          if (placemarks.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autocompleteKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _autocompleteKey.currentContext!,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          }
          if (placemarks.isNotEmpty && widget.mapController != null && mounted) {
            widget.mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(limited.first.latitude, limited.first.longitude),
                14.0,
              ),
            );
          }
        }
      } else {
        if (_destController.text == value && mounted) {
          setState(() {
            _autocompleteResults = [];
            _autocompleteLocations = [];
            _showAutocomplete = false;
          });
        }
      }
    } catch (_) {
      if (_destController.text == value && mounted) {
        setState(() {
          _autocompleteResults = [];
          _autocompleteLocations = [];
          _showAutocomplete = false;
        });
      }
    }
  }

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
  }

  void _requestSearch() {
    if (_destController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan isi tujuan perjalanan terlebih dahulu'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (widget.originLat == null || widget.originLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menunggu lokasi penumpang...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    double? destLat = _selectedDestLat;
    double? destLng = _selectedDestLng;
    if (destLat == null || destLng == null) {
      // Geocode dari text
      locationFromAddress('${_destController.text.trim()}, Indonesia')
          .then((locations) {
        if (locations.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tujuan tidak ditemukan'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        final loc = locations.first;
        widget.onSearch(
          _destController.text.trim(),
          loc.latitude,
          loc.longitude,
        );
      }).catchError((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal menemukan tujuan'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
      return;
    }
    widget.onSearch(
      _destController.text.trim(),
      destLat,
      destLng,
    );
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
          padding: const EdgeInsets.only(bottom: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Cari Tujuan Perjalanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Dari (lokasi Anda)',
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
                Text(
                  'Tujuan',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                if (_destController.text.trim().isEmpty && !_isMapSelectionMode)
                  FutureBuilder<List<RecentDestination>>(
                    future: RecentDestinationService.getList(),
                    builder: (context, snap) {
                      final list = snap.data ?? [];
                      if (list.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tujuan baru-baru ini',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: list.take(5).map((r) {
                                return ActionChip(
                                  label: Text(r.text.length > 25 ? '${r.text.substring(0, 25)}...' : r.text),
                                  onPressed: () {
                                    setState(() {
                                      _destController.text = r.text;
                                      _selectedDestLat = r.lat;
                                      _selectedDestLng = r.lng;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
                              color: AppTheme.primary,
                            ),
                            title: Text(
                              _formatPlacemarkDetail(p),
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
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: _isMapSelectionMode
                              ? 'Tap di map untuk pilih lokasi'
                              : 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                          hintStyle: TextStyle(
                            color: _isMapSelectionMode
                                ? AppTheme.primary
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
                          ? AppTheme.primary
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
                            ? AppTheme.primary.withOpacity(0.1)
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
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap di peta untuk memilih lokasi tujuan',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _requestSearch();
                  },
                  icon: const Icon(Icons.search, size: 20),
                  label: const Text('Cari'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

/// Bottom sheet: tautkan penerima kirim barang (cari email/telp → tampil foto+nama → Iya → create order).
class _KirimBarangLinkReceiverSheet extends StatefulWidget {
  final ActiveDriverRoute driver;
  final String asal;
  final String tujuan;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final void Function(String orderId, String message) onOrderCreated;
  final void Function(String message) onError;

  const _KirimBarangLinkReceiverSheet({
    required this.driver,
    required this.asal,
    required this.tujuan,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    required this.onOrderCreated,
    required this.onError,
  });

  @override
  State<_KirimBarangLinkReceiverSheet> createState() =>
      _KirimBarangLinkReceiverSheetState();
}

class _KirimBarangLinkReceiverSheetState
    extends State<_KirimBarangLinkReceiverSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _receiver; // {uid, displayName, photoUrl}
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
      driverUid: widget.driver.driverUid,
      routeJourneyNumber: widget.driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      originText: widget.asal,
      destText: widget.tujuan,
      originLat: widget.originLat,
      originLng: widget.originLng,
      destLat: widget.destLat,
      destLng: widget.destLng,
      orderType: OrderModel.typeKirimBarang,
      receiverUid: uid,
      receiverName: receiverName,
      receiverPhotoUrl: receiverPhotoUrl,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (orderId == null) {
      widget.onError('Gagal membuat pesanan. Silakan coba lagi.');
      return;
    }
    final driverName = widget.driver.driverName ?? 'Driver';
    final message =
        'Halo Pak $driverName,\n\n'
        'Saya ingin mengirim barang.\n\n'
        'Penerima: $receiverName\n'
        'Dari: ${widget.asal}\n'
        'Tujuan: ${widget.tujuan}\n\n'
        'Mohon informasi biaya pengiriman untuk rute ini.';
    widget.onOrderCreated(orderId, message);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              'Masukkan email atau no. telepon penerima (harus terdaftar di Traka).',
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
            const SizedBox(height: 12),
            if (_notFound != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _notFound!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (_receiver != null) ...[
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
              Text(
                'Penerima akan dapat notifikasi dan harus setuju. Setelah setuju, pesanan masuk ke driver.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
            ],
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

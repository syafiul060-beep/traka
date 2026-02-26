import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../services/sos_service.dart';

/// Halaman Lacak Driver: full-screen map hybrid, posisi driver dengan icon mobil
/// (car_hijau = bergerak, car_merah = tidak bergerak). Posisi depan mobil di bawah gambar.
class CekLokasiDriverScreen extends StatefulWidget {
  const CekLokasiDriverScreen({
    super.key,
    required this.orderId,
    this.order,
  });

  final String orderId;
  final OrderModel? order;

  @override
  State<CekLokasiDriverScreen> createState() => _CekLokasiDriverScreenState();
}

class _CekLokasiDriverScreenState extends State<CekLokasiDriverScreen> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;
  static const int _movingThresholdSeconds = 30;

  @override
  void initState() {
    super.initState();
    _loadCarIcons();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCarIcons() async {
    try {
      const size = 56.0;
      const padding = 12.0;
      final canvasSize = (size + padding * 2).toInt();

      for (final path in ['assets/images/car_merah.png', 'assets/images/car_hijau.png']) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: size.toInt(),
        );
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final w = image.width.toDouble();
        final h = image.height.toDouble();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(
          image,
          Offset((canvasSize - w) / 2, (canvasSize - h) / 2),
          Paint(),
        );
        final picture = recorder.endRecording();
        final finalImage = await picture.toImage(canvasSize, canvasSize);
        final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) continue;
        final descriptor = BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
        if (path.contains('car_merah')) {
          _carIconRed = descriptor;
        } else {
          _carIconGreen = descriptor;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      _carIconRed = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      _carIconGreen = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).get(),
        builder: (context, orderSnap) {
          if (!orderSnap.hasData || !orderSnap.data!.exists) {
            return _buildScaffold(
              child: const Center(child: Text('Pesanan tidak ditemukan.')),
            );
          }
          final order = widget.order ?? OrderModel.fromFirestore(orderSnap.data!);
          final driverUid = order.driverUid;
          if (driverUid.isEmpty) {
            return _buildScaffold(
              child: const Center(child: Text('Data driver tidak valid.')),
            );
          }
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('driver_status')
                .doc(driverUid)
                .snapshots(),
            builder: (context, statusSnap) {
              if (!statusSnap.hasData || !statusSnap.data!.exists) {
                return _buildScaffold(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Lokasi driver belum tersedia',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Driver mungkin belum mulai rute atau tidak aktif. Lokasi akan muncul setelah driver memulai perjalanan.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final d = statusSnap.data!.data();
              final lat = (d?['latitude'] as num?)?.toDouble();
              final lng = (d?['longitude'] as num?)?.toDouble();
              final lastUpdated = d?['lastUpdated'] as Timestamp?;
              if (lat == null || lng == null) {
                return _buildScaffold(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Koordinat driver tidak valid',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Driver mungkin belum mengirim lokasi. Coba refresh atau tunggu sebentar.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final driverPosition = LatLng(lat, lng);
              final isMoving = lastUpdated != null &&
                  DateTime.now().difference(lastUpdated.toDate()).inSeconds <= _movingThresholdSeconds;
              final carIcon = isMoving ? _carIconGreen : _carIconRed;
              final fallbackIcon = BitmapDescriptor.defaultMarkerWithHue(
                isMoving ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
              );

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(driverPosition),
                  );
                }
              });

              final passengerLat = order.originLat ?? order.passengerLat;
              final passengerLng = order.originLng ?? order.passengerLng;
              double? distanceMeters;
              String distanceText = '-';
              String etaText = '-';
              if (passengerLat != null && passengerLng != null) {
                distanceMeters = Geolocator.distanceBetween(
                  lat,
                  lng,
                  passengerLat,
                  passengerLng,
                );
                if (distanceMeters < 1000) {
                  distanceText = '${distanceMeters.round()} m';
                } else {
                  distanceText = '${(distanceMeters / 1000).toStringAsFixed(1)} km';
                }
                const avgSpeedKmh = 40.0;
                final durationSeconds = (distanceMeters / 1000) / avgSpeedKmh * 3600;
                final eta = DateTime.now().add(Duration(seconds: durationSeconds.round()));
                final hour = eta.hour;
                final minute = eta.minute;
                etaText = 'Jam ${hour.toString().padLeft(2, '0')}.${minute.toString().padLeft(2, '0')}';
              }

              return _buildScaffold(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: driverPosition,
                        zoom: 15,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                      },
                      mapType: MapType.hybrid,
                      markers: {
                        Marker(
                          markerId: const MarkerId('driver'),
                          position: driverPosition,
                          icon: carIcon ?? fallbackIcon,
                          anchor: const Offset(0.5, 1.0),
                          infoWindow: InfoWindow(
                            title: 'Driver',
                            snippet: isMoving ? 'Sedang bergerak' : 'Berhenti',
                          ),
                        ),
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: false,
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 12,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Kembali',
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: MediaQuery.of(context).padding.bottom + 24,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.straighten, color: Theme.of(context).colorScheme.primary, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Jarak driver ke lokasi Anda: $distanceText',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.access_time, color: Colors.green.shade700, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Estimasi tiba di lokasi Anda: $etaText',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildScaffold({required Widget child, OrderModel? order}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Kembali',
            ),
          ),
        ),
        if (order != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: Colors.red.shade50,
              child: IconButton(
                icon: Icon(Icons.emergency, color: Colors.red.shade700),
                onPressed: () => _onSOS(context, order),
                tooltip: 'SOS Darurat',
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _onSOS(BuildContext context, OrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SOS Darurat'),
        content: const Text(
          'Kirim lokasi dan info pesanan ke admin via WhatsApp? Pastikan Anda dalam keadaan darurat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kirim SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await SosService.triggerSOSWithLocation(order: order, isDriver: false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS terkirim. WhatsApp akan terbuka ke admin.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

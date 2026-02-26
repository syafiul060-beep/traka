import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/active_drivers_service.dart';
import '../services/favorite_driver_service.dart';
import '../services/order_service.dart';
import 'chat_room_penumpang_screen.dart';

/// Halaman Cari Travel: map + daftar driver dengan rute aktif.
/// Icon mobil + nama driver di map; klik icon → tombol Pesan Travel → Chat.
/// Setelah kirim permintaan → pending_agreement; driver & penumpang kesepakatan → nomor pesanan.
class CariTravelScreen extends StatefulWidget {
  const CariTravelScreen({
    super.key,
    this.prefillAsal,
    this.prefillTujuan,
    this.passengerOriginLat,
    this.passengerOriginLng,
    this.passengerDestLat,
    this.passengerDestLng,
  });

  final String? prefillAsal;
  final String? prefillTujuan;

  /// Koordinat asal/tujuan penumpang untuk filter driver di map (60 km / 10 km).
  final double? passengerOriginLat;
  final double? passengerOriginLng;
  final double? passengerDestLat;
  final double? passengerDestLng;

  @override
  State<CariTravelScreen> createState() => _CariTravelScreenState();
}

class _CariTravelScreenState extends State<CariTravelScreen> {
  List<ActiveDriverRoute> _drivers = [];
  bool _loading = true;
  String? _error;

  final _asalController = TextEditingController();
  final _tujuanController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _asalController.text = widget.prefillAsal ?? '';
    _tujuanController.text = widget.prefillTujuan ?? '';
    _loadDrivers();
  }

  @override
  void dispose() {
    _asalController.dispose();
    _tujuanController.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      double? destLat = widget.passengerDestLat;
      double? destLng = widget.passengerDestLng;
      if ((destLat == null || destLng == null) &&
          _tujuanController.text.trim().isNotEmpty) {
        try {
          final list = await locationFromAddress(_tujuanController.text.trim());
          if (list.isNotEmpty) {
            destLat = list.first.latitude;
            destLng = list.first.longitude;
          }
        } catch (_) {}
      }
      final list =
          (widget.passengerOriginLat != null &&
                  widget.passengerOriginLng != null) ||
              (destLat != null && destLng != null)
          ? await ActiveDriversService.getActiveDriversForMap(
              passengerOriginLat: widget.passengerOriginLat,
              passengerOriginLng: widget.passengerOriginLng,
              passengerDestLat: destLat,
              passengerDestLng: destLng,
            )
          : await ActiveDriversService.getActiveDriverRoutes();
      if (mounted) {
        setState(() {
          _drivers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _onPesanTravel(ActiveDriverRoute driver) async {
    if (!mounted) return;
    Navigator.pop(context);
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

    final asal = _asalController.text.trim().isEmpty
        ? 'Lokasi penjemputan'
        : _asalController.text.trim();
    final tujuan = _tujuanController.text.trim().isEmpty
        ? 'Tujuan'
        : _tujuanController.text.trim();

    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: driver.driverUid,
      routeJourneyNumber: driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      originText: asal,
      destText: tujuan,
      originLat: null,
      originLng: null,
      destLat: null,
      destLng: null,
    );

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
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal membuat pesanan. Coba lagi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onSelectDriver(ActiveDriverRoute driver) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: _RequestFormSheet(
              driver: driver,
              asalController: _asalController,
              tujuanController: _tujuanController,
              onSubmitted: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Permintaan terkirim. Menunggu kesepakatan driver.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showPesanTravelSheet(ActiveDriverRoute driver) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (driver.driverPhotoUrl != null &&
                            driver.driverPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(driver.driverPhotoUrl!)
                        : null,
                    child:
                        (driver.driverPhotoUrl == null ||
                            driver.driverPhotoUrl!.isEmpty)
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver.driverName ?? 'Driver',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (driver.averageRating != null && driver.reviewCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '${driver.averageRating!.toStringAsFixed(1)} (${driver.reviewCount} ulasan)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          'Tujuan: ${driver.routeDestText.isNotEmpty ? driver.routeDestText : "-"}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (driver.remainingPassengerCapacity != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              driver.hasPassengerCapacity
                                  ? 'Sisa ${driver.remainingPassengerCapacity} kursi'
                                  : 'Penuh',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: driver.hasPassengerCapacity
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: driver.hasPassengerCapacity
                    ? () => _onPesanTravel(driver)
                    : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  driver.hasPassengerCapacity ? 'Pesan Travel' : 'Kursi penuh',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: driver.hasPassengerCapacity
                    ? () {
                        Navigator.pop(ctx);
                        _onSelectDriver(driver);
                      }
                    : null,
                icon: const Icon(Icons.send),
                label: const Text('Kirim permintaan (form asal/tujuan)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _drivers.length,
        itemBuilder: (context, index) => _buildDriverCard(context, _drivers[index], {}),
      );
    }
    return StreamBuilder<List<String>>(
      stream: FavoriteDriverService.streamFavoriteDriverIds(user.uid),
      builder: (context, snap) {
        final favSet = (snap.data ?? []).toSet();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          cacheExtent: 200,
          itemCount: _drivers.length,
          itemBuilder: (context, index) {
            final d = _drivers[index];
            return _buildDriverCard(context, d, favSet);
          },
        );
      },
    );
  }

  Widget _buildDriverCard(BuildContext context, ActiveDriverRoute d, Set<String> favIds) {
    final user = FirebaseAuth.instance.currentUser;
    final isFav = user != null && favIds.contains(d.driverUid);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          backgroundImage: (d.driverPhotoUrl != null && d.driverPhotoUrl!.isNotEmpty)
              ? CachedNetworkImageProvider(d.driverPhotoUrl!)
              : null,
          child: (d.driverPhotoUrl == null || d.driverPhotoUrl!.isEmpty)
              ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(d.driverName ?? 'Driver', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (user != null)
              IconButton(
                icon: Icon(isFav ? Icons.star : Icons.star_border, color: Colors.amber.shade700, size: 22),
                onPressed: () async {
                  await FavoriteDriverService.toggleFavorite(user.uid, d.driverUid, isFav);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            if (d.averageRating != null && d.reviewCount > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                  const SizedBox(width: 4),
                  Text('${d.averageRating!.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text('Dari: ${d.routeOriginText.isNotEmpty ? d.routeOriginText : "-"}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('Tujuan: ${d.routeDestText.isNotEmpty ? d.routeDestText : "-"}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (d.remainingPassengerCapacity != null)
              Text(d.hasPassengerCapacity ? 'Sisa ${d.remainingPassengerCapacity} kursi' : 'Penuh', style: TextStyle(fontSize: 12, color: d.hasPassengerCapacity ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _onSelectDriver(d),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Travel'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _loadDrivers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            )
          : _drivers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_car,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada driver dengan rute aktif',
                      style: TextStyle(
                        fontSize: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Driver yang sedang "Siap Kerja" dengan rute akan muncul di sini.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 220,
                  child: ClipRect(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          _drivers.first.driverLat,
                          _drivers.first.driverLng,
                        ),
                        zoom: 11,
                      ),
                      markers: {
                        for (final d in _drivers)
                          Marker(
                            markerId: MarkerId(d.driverUid),
                            position: LatLng(d.driverLat, d.driverLng),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              d.markerHue,
                            ),
                            infoWindow: InfoWindow(
                              title: d.driverName ?? 'Driver',
                              snippet: d.routeDestText.isNotEmpty
                                  ? d.routeDestText
                                  : null,
                            ),
                            onTap: () => _showPesanTravelSheet(d),
                          ),
                      },
                      myLocationEnabled: true,
                      zoomControlsEnabled: false,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Klik icon mobil di map → Pesan Travel atau kirim permintaan',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadDrivers,
                    child: _buildDriverList(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _RequestFormSheet extends StatefulWidget {
  const _RequestFormSheet({
    required this.driver,
    required this.asalController,
    required this.tujuanController,
    required this.onSubmitted,
  });

  final ActiveDriverRoute driver;
  final TextEditingController asalController;
  final TextEditingController tujuanController;
  final VoidCallback onSubmitted;

  @override
  State<_RequestFormSheet> createState() => _RequestFormSheetState();
}

class _RequestFormSheetState extends State<_RequestFormSheet> {
  bool _sending = false;

  Future<void> _submit() async {
    final asal = widget.asalController.text.trim();
    final tujuan = widget.tujuanController.text.trim();
    if (asal.isEmpty || tujuan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi asal dan tujuan perjalanan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!widget.driver.hasPassengerCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kursi mobil driver sudah penuh.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _sending = true);
    try {
      String? passengerName;
      String? passengerPhotoUrl;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        passengerName = userDoc.data()!['displayName'] as String?;
        passengerPhotoUrl = userDoc.data()!['photoUrl'] as String?;
      }
      passengerName ??= user.email ?? 'Penumpang';

      final orderId = await OrderService.createOrder(
        passengerUid: user.uid,
        driverUid: widget.driver.driverUid,
        routeJourneyNumber: widget.driver.routeJourneyNumber,
        passengerName: passengerName,
        passengerPhotoUrl: passengerPhotoUrl,
        originText: asal,
        destText: tujuan,
        originLat: null,
        originLng: null,
        destLat: null,
        destLng: null,
      );
      if (orderId != null && mounted) widget.onSubmitted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengirim: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kirim permintaan ke ${widget.driver.driverName ?? "driver"}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (widget.driver.remainingPassengerCapacity != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.driver.hasPassengerCapacity
                      ? 'Sisa ${widget.driver.remainingPassengerCapacity} kursi'
                      : 'Kursi penuh – tidak dapat mengirim permintaan travel.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.driver.hasPassengerCapacity
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.asalController,
              decoration: const InputDecoration(
                labelText: 'Dari (asal Anda)',
                border: OutlineInputBorder(),
                hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.tujuanController,
              decoration: const InputDecoration(
                labelText: 'Tujuan',
                border: OutlineInputBorder(),
                hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_sending || !widget.driver.hasPassengerCapacity)
                  ? null
                  : _submit,
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _sending
                    ? 'Mengirim...'
                    : (widget.driver.hasPassengerCapacity
                          ? 'Kirim permintaan'
                          : 'Kursi penuh'),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

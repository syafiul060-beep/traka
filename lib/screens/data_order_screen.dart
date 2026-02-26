import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../models/order_model.dart';
import '../services/chat_service.dart';
import '../services/order_service.dart';
import '../services/rating_service.dart';
import '../services/violation_service.dart';
import '../services/route_notification_service.dart';
import '../services/sos_service.dart';
import '../services/track_share_service.dart';
import '../theme/responsive.dart';
import 'admin_chat_screen.dart';
import 'cek_lokasi_barang_screen.dart';
import 'cek_lokasi_driver_screen.dart';
import 'chat_room_penumpang_screen.dart';
import 'lacak_barang_payment_screen.dart';
import 'lacak_driver_payment_screen.dart';
import 'scan_barcode_penumpang_screen.dart';

/// Halaman Data Order untuk penumpang dengan 3 menu:
/// 1. Pesanan - pesanan yang sudah terjadi kesepakatan (agreed)
/// 2. Driver - pesanan yang sudah dijemput (picked_up), tombol Scan barcode driver
/// 3. Riwayat - pesanan yang sudah selesai (completed)
class DataOrderScreen extends StatefulWidget {
  const DataOrderScreen({super.key});

  @override
  State<DataOrderScreen> createState() => _DataOrderScreenState();
}

class _DataOrderScreenState extends State<DataOrderScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, Map<String, dynamic>> _driverInfoCache = {};
  Position? _positionForCancel;
  bool _loadingPositionForCancel = false;
  Timer? _autoCompleteTimer;

  Future<void> _loadPositionForCancel() async {
    if (_loadingPositionForCancel) return;
    setState(() => _loadingPositionForCancel = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() {
          _positionForCancel = pos;
          _loadingPositionForCancel = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPositionForCancel = false);
    }
  }

  Future<void> _loadDriverInfoIfNeeded(List<OrderModel> orders) async {
    final uids = orders
        .map((o) => o.driverUid)
        .where((uid) => !_driverInfoCache.containsKey(uid))
        .toSet();
    if (uids.isEmpty) return;
    final newInfo = <String, Map<String, dynamic>>{};
    for (final uid in uids) {
      try {
        final info = await ChatService.getUserInfo(
          uid,
        ).timeout(const Duration(seconds: 5));
        newInfo[uid] = info;
      } catch (_) {
        newInfo[uid] = {
          'displayName': null,
          'photoUrl': null,
          'verified': false,
        };
      }
    }
    if (!mounted) return;
    setState(() {
      _driverInfoCache.addAll(newInfo);
    });
  }

  void _onTabChanged() {
    if (!mounted) return;
    if ((_tabController.index == 0 || _tabController.index == 1) &&
        _positionForCancel == null &&
        !_loadingPositionForCancel) {
      _loadPositionForCancel();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _autoCompleteTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _checkAutoCompleteWhenFarApart();
    });
  }

  @override
  void dispose() {
    _autoCompleteTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Jika status picked_up dan jarak driver–penumpang > 500 m → selesai otomatis (tanpa tombol).
  Future<void> _checkAutoCompleteWhenFarApart() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final orders = await OrderService.getPickedUpTravelOrdersForPassenger();
      if (!mounted || orders.isEmpty) {
        if (orders.isEmpty) if (kDebugMode) debugPrint('[Traka AutoComplete] Penumpang: 0 order picked_up.');
        return;
      }

      final passLat = pos.latitude;
      final passLng = pos.longitude;
      if (kDebugMode) debugPrint('[Traka AutoComplete] Penumpang: cek ${orders.length} order picked_up, penumpang @ ($passLat, $passLng)');

      for (final order in orders) {
        if (kDebugMode) debugPrint('[Traka AutoComplete] Penumpang order ${order.id}: panggil completeOrderWhenFarApart');
        final (ok, err) = await OrderService.completeOrderWhenFarApart(
          order.id,
          passLat,
          passLng,
          false,
        );
        if (!mounted) return;
        if (ok) {
          if (kDebugMode) debugPrint('[Traka AutoComplete] Penumpang order ${order.id}: sukses - chat, notifikasi, SnackBar');
          await ChatService.sendMessage(
            order.id,
            'Pesanan selesai (konfirmasi otomatis – driver dan penumpang sudah menjauh).',
          );
          if (!mounted) return;
          await RouteNotificationService.showAutoCompleteNotification();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pesanan selesai otomatis. Notifikasi telah dikirim.',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
          setState(() {});
        } else {
          if (kDebugMode) debugPrint('[Traka AutoComplete] Penumpang order ${order.id}: gagal - $err');
        }
        break;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka AutoComplete] Penumpang error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Order'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'Pesanan'),
            Tab(text: 'Dalam Perjalanan'),
            Tab(text: 'Riwayat'),
          ],
        ),
      ),
      body: user == null
          ? const Center(child: Text('Anda belum login.'))
          : Column(
              children: [
                StreamBuilder<List<OrderModel>>(
                  stream: OrderService.streamOrdersForReceiver(user.uid),
                  builder: (context, recSnap) {
                    final recList = recSnap.data ?? [];
                    final pending = recList
                        .where((o) => o.status == OrderService.statusPendingReceiver)
                        .toList();
                    if (pending.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      color: Colors.amber.shade50,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Anda ditunjuk sebagai penerima (Kirim Barang)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...pending.map((order) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${order.passengerName} → ${order.originText} ke ${order.destText}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final ok = await OrderService.setReceiverRejected(order.id);
                                        if (context.mounted && ok) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Ditolak.'), behavior: SnackBarBehavior.floating),
                                          );
                                        }
                                      },
                                      child: const Text('Tolak'),
                                    ),
                                    FilledButton(
                                      onPressed: () async {
                                        final ok = await OrderService.setReceiverAgreed(order.id);
                                        if (context.mounted && ok) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Anda setuju. Pesanan masuk ke driver.'),
                                              backgroundColor: Colors.green,
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('Setuju'),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildPesananTab(), _buildDriverTab(), _buildRiwayatTab()],
                  ),
                ),
              ],
            ),
    );
  }

  /// 1. Pesanan: hanya tampil jika sudah terjadi kesepakatan (agreed atau picked_up).
  Widget _buildPesananTab() {
    return StreamBuilder<List<OrderModel>>(
      stream: OrderService.streamOrdersForPassenger(includeHidden: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Terjadi kesalahan',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gagal memuat data pesanan. Silakan coba lagi.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final allOrders = snapshot.data ?? [];

        // Filter: hanya pesanan status agreed (belum dijemput; setelah driver scan pindah ke tab Driver)
        final agreedOrders = allOrders
            .where((order) => order.status == OrderService.statusAgreed)
            .toList();

        if (agreedOrders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada pesanan',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pesanan yang sudah terjadi kesepakatan akan muncul di sini.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        if (_positionForCancel == null && !_loadingPositionForCancel) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _loadPositionForCancel(),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadDriverInfoIfNeeded(agreedOrders);
        });
        return RefreshIndicator(
          onRefresh: () async {
            _loadPositionForCancel();
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: ListView.builder(
            padding: EdgeInsets.all(context.responsive.spacing(16)),
            itemCount: agreedOrders.length,
            cacheExtent: 200,
            itemBuilder: (context, index) {
              final order = agreedOrders[index];
              return _buildOrderCard(order);
            },
          ),
        );
      },
    );
  }

  /// 2. Driver: pesanan yang sudah dijemput (status picked_up). Gabungan order sebagai penumpang + sebagai penerima (kirim barang).
  Widget _buildDriverTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Belum login.'));
    return StreamBuilder<List<OrderModel>>(
      stream: OrderService.streamOrdersForPassenger(includeHidden: true),
      builder: (context, snapPassenger) {
        return StreamBuilder<List<OrderModel>>(
          stream: OrderService.streamOrdersForReceiver(user.uid),
          builder: (context, snapReceiver) {
            if (snapPassenger.connectionState == ConnectionState.waiting &&
                snapReceiver.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final passengerOrders = snapPassenger.data ?? [];
            final receiverOrders = snapReceiver.data ?? [];
            final pickedPassenger = passengerOrders
                .where((o) => o.status == OrderService.statusPickedUp)
                .toList();
            final pickedReceiver = receiverOrders
                .where((o) => o.status == OrderService.statusPickedUp)
                .toList();
            final Map<String, OrderModel> merged = {};
            for (final o in pickedPassenger) merged[o.id] = o;
            for (final o in pickedReceiver) {
              if (!merged.containsKey(o.id)) merged[o.id] = o;
            }
            final pickedUpOrders = merged.values.toList();
            pickedUpOrders.sort((a, b) {
              final at = a.updatedAt ?? a.createdAt;
              final bt = b.updatedAt ?? b.createdAt;
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });
            if (pickedUpOrders.isEmpty) {
              return Center(
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
                        'Belum ada perjalanan aktif',
                        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Setelah setuju harga, pesanan ada di tab Pesanan.\n'
                        '2. Driver scan barcode Anda saat jemput → pesanan pindah ke sini.\n'
                        '3. Saat sampai tujuan, scan barcode driver.\n'
                        '(Penerima kirim barang: scan barcode driver untuk terima barang.)',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            if (_positionForCancel == null && !_loadingPositionForCancel) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _loadPositionForCancel(),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadDriverInfoIfNeeded(pickedUpOrders);
            });
            return FutureBuilder<int>(
              future: ViolationService.getViolationFeeRupiah(),
              builder: (context, feeSnap) {
                final feeStr = feeSnap.hasData
                    ? feeSnap.data!.toString().replaceAllMapped(
                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                        (m) => '${m[1]}.',
                      )
                    : '5.000';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.responsive.spacing(16),
                        context.responsive.spacing(16),
                        context.responsive.spacing(16),
                        0,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Colors.orange.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Scan barcode driver saat sampai tujuan. Jika tidak scan dan sudah menjauh, akan selesai otomatis dan dikenakan denda Rp $feeStr.',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          _loadPositionForCancel();
                          await Future.delayed(const Duration(milliseconds: 400));
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.all(context.responsive.spacing(16)),
                          itemCount: pickedUpOrders.length,
                          cacheExtent: 200,
                          itemBuilder: (context, index) {
                            final order = pickedUpOrders[index];
                            return _buildDriverTabOrderCard(order, isReceiver: order.receiverUid == user.uid);
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Kartu order di tab Driver (status picked_up): foto & nama driver + centang verifikasi, lalu Scan barcode driver.
  /// [isReceiver]: true jika user adalah penerima (kirim barang) — tampilkan label "Terima barang".
  Widget _buildDriverTabOrderCard(OrderModel order, {bool isReceiver = false}) {
    final info = _driverInfoCache[order.driverUid];
    final driverName = (info?['displayName'] as String?)?.isNotEmpty == true
        ? (info!['displayName'] as String)
        : 'Driver';
    final driverPhotoUrl = info?['photoUrl'] as String?;
    final driverVerified = info?['verified'] == true;
    return Card(
      margin: EdgeInsets.only(bottom: context.responsive.spacing(12)),
      child: Padding(
        padding: EdgeInsets.all(context.responsive.spacing(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (order.orderNumber != null) ...[
              Text(
                'No. Pesanan: ${order.orderNumber}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Foto profil driver, nama driver, centang verifikasi
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (driverPhotoUrl != null && driverPhotoUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(driverPhotoUrl)
                      : null,
                  child: (driverPhotoUrl == null || driverPhotoUrl.isEmpty)
                      ? Icon(
                          Icons.person,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 28,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              driverName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (driverVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.destText.isNotEmpty
                            ? 'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}'
                            : 'Dalam perjalanan',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isReceiver) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Anda penerima kirim barang. Scan barcode driver saat barang sampai.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // SOS Darurat + Bagikan ke keluarga dalam 1 baris (tab Driver)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _onSOS(context, order),
                    icon: const Icon(Icons.emergency, size: 18),
                    label: const Text('SOS'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (!order.isKirimBarang) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _onBagikanKeKeluarga(context, order),
                      icon: const Icon(Icons.share_location, size: 18),
                      label: const Text('Bagikan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: order.passengerTrackDriverPaidAt != null
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        side: BorderSide(
                          color: order.passengerTrackDriverPaidAt != null
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.outline,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (order.isKirimBarang)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: () => _onLacakBarang(context, order, isReceiver: isReceiver),
                  icon: const Icon(Icons.local_shipping, size: 20),
                  label: const Text('Lacak Barang'),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(
                      builder: (ctx) => const ScanBarcodePenumpangScreen(),
                    ),
                  );
                  if (context.mounted) {
                    if (result == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Perjalanan selesai. Pesanan pindah ke Riwayat.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else if (result is String) {
                      _showRatingDialog(context, result);
                    }
                  }
                },
                icon: const Icon(Icons.qr_code_scanner, size: 22),
                label: Text(
                  isReceiver
                      ? 'Scan barcode driver (untuk terima barang)'
                      : 'Scan barcode driver (saat sampai tujuan)',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.deepPurple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Riwayat: pesanan yang sudah selesai (status completed).
  /// Gabungkan order sebagai penumpang + sebagai penerima (kirim barang) agar riwayat lengkap.
  Widget _buildRiwayatTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Belum login.'));
    return StreamBuilder<List<OrderModel>>(
      stream: OrderService.streamOrdersForPassenger(includeHidden: true),
      builder: (context, snapPassenger) {
        return StreamBuilder<List<OrderModel>>(
          stream: OrderService.streamOrdersForReceiver(user.uid),
          builder: (context, snapReceiver) {
            if (snapPassenger.connectionState == ConnectionState.waiting &&
                snapReceiver.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final passengerOrders = snapPassenger.data ?? [];
            final receiverOrders = snapReceiver.data ?? [];
            final Map<String, OrderModel> merged = {};
            for (final o in passengerOrders) merged[o.id] = o;
            for (final o in receiverOrders) {
              if (!merged.containsKey(o.id)) merged[o.id] = o;
            }
            final allOrders = merged.values.toList();
            final completedOrders = allOrders
                .where((o) => o.status == OrderService.statusCompleted)
                .toList();
            completedOrders.sort((a, b) {
              final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
              final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });
            if (completedOrders.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada riwayat pesanan',
                        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pesanan yang sudah selesai (setelah Anda scan barcode driver di tujuan) akan muncul di sini.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadDriverInfoIfNeeded(completedOrders);
            });
            return RefreshIndicator(
              onRefresh: () async {
                _loadPositionForCancel();
                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: completedOrders.length,
                cacheExtent: 200,
                itemBuilder: (context, index) {
                  final order = completedOrders[index];
                  return _buildRiwayatOrderCard(order);
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Kartu order di tab Riwayat (status completed): hanya info, tanpa tombol aksi.
  Widget _buildRiwayatOrderCard(OrderModel order) {
    final info = _driverInfoCache[order.driverUid];
    final driverName = (info?['displayName'] as String?)?.isNotEmpty == true
        ? (info!['displayName'] as String)
        : 'Driver';
    final driverPhotoUrl = info?['photoUrl'] as String?;
    final driverVerified = info?['verified'] == true;
    final completedStr = order.completedAt != null
        ? _formatRiwayatDate(order.completedAt!)
        : '';
    return Card(
      margin: EdgeInsets.only(bottom: context.responsive.spacing(12)),
      child: Padding(
        padding: EdgeInsets.all(context.responsive.spacing(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (order.orderNumber != null)
              Text(
                'No. Pesanan: ${order.orderNumber}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            if (order.orderNumber != null) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (driverPhotoUrl != null && driverPhotoUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(driverPhotoUrl)
                      : null,
                  child: (driverPhotoUrl == null || driverPhotoUrl.isEmpty)
                      ? Icon(
                          Icons.person,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 28,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              driverName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (driverVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.originText.isNotEmpty
                            ? 'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}'
                            : 'Dari: -',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        order.destText.isNotEmpty
                            ? 'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}'
                            : 'Tujuan: -',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (order.tripDistanceKm != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Jarak: ${order.tripDistanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (order.agreedPrice != null &&
                          order.agreedPrice! >= 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Harga kesepakatan : Rp ${order.agreedPrice!.round()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (completedStr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Selesai: $completedStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (order.orderType == OrderModel.typeTravel) ...[
                        const SizedBox(height: 8),
                        if (order.passengerRating != null)
                          Row(
                            children: [
                              Icon(Icons.star, size: 16, color: Colors.amber.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Rating: ${order.passengerRating}/5',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (order.passengerReview != null &&
                                  order.passengerReview!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '"${order.passengerReview}"',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          )
                        else
                          TextButton.icon(
                            onPressed: () => _showRatingDialog(context, order.id),
                            icon: const Icon(Icons.star_border, size: 18),
                            label: const Text('Beri rating driver'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                      if (order.agreedPrice != null && order.agreedPrice! >= 0) ...[
                        const SizedBox(height: 2),
                        TextButton.icon(
                          onPressed: () => _reportPriceMismatch(context, order),
                          icon: Icon(Icons.report_outlined, size: 16, color: Colors.orange.shade700),
                          label: Text(
                            'Laporkan harga tidak sesuai',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        order.orderType == OrderModel.typeKirimBarang
                            ? 'Kirim barang'
                            : (order.jumlahKerabat != null &&
                                      order.jumlahKerabat! > 0
                                  ? 'Travel (${order.totalPenumpang} orang)'
                                  : 'Travel (1 orang)'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatRiwayatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  void _reportPriceMismatch(BuildContext context, OrderModel order) {
    final hargaStr = order.agreedPrice != null
        ? order.agreedPrice!.round().toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]}.',
          )
        : '-';
    final initialMessage =
        'Laporkan harga tidak sesuai - No. Pesanan: ${order.orderNumber ?? order.id}, '
        'Harga kesepakatan: Rp $hargaStr. Driver meminta harga berbeda. ';
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AdminChatScreen(initialMessage: initialMessage),
      ),
    );
  }

  /// Format alamat: hanya kecamatan dan kabupaten, tanpa provinsi.
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

  Widget _buildOrderCard(OrderModel order) {
    return Card(
      margin: EdgeInsets.only(bottom: context.responsive.spacing(12)),
      child: Padding(
        padding: EdgeInsets.all(context.responsive.spacing(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No. Pesanan dengan icon salin
            if (order.orderNumber != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'No. Pesanan: ${order.orderNumber}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: order.orderNumber!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nomor pesanan disalin'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // Foto profil driver, nama driver, dan centang verifikasi
            Builder(
              builder: (context) {
                final info = _driverInfoCache[order.driverUid];
                final driverName =
                    (info?['displayName'] as String?)?.isNotEmpty == true
                    ? (info!['displayName'] as String)
                    : 'Driver';
                final driverPhotoUrl = info?['photoUrl'] as String?;
                final driverVerified = info?['verified'] == true;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage:
                          (driverPhotoUrl != null && driverPhotoUrl.isNotEmpty)
                          ? CachedNetworkImageProvider(driverPhotoUrl)
                          : null,
                      child: (driverPhotoUrl == null || driverPhotoUrl.isEmpty)
                          ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  driverName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (driverVerified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Dari: hanya kecamatan & kabupaten
                          Text(
                            order.originText.isNotEmpty
                                ? 'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}'
                                : 'Dari: -',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Tujuan: hanya kecamatan & kabupaten
                          Text(
                            order.destText.isNotEmpty
                                ? 'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}'
                                : 'Tujuan: -',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Harga kesepakatan (tab Pesanan)
                          if (order.agreedPrice != null && order.agreedPrice! >= 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Harga: Rp ${order.agreedPrice!.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Tombol Tunjukkan barcode ke driver (jika sudah setuju)
            if (order.hasPassengerBarcode &&
                order.passengerBarcodePayload != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showPassengerBarcodeFullScreen(
                    context,
                    order.passengerBarcodePayload!,
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 20),
                  label: const Text('Tunjukkan barcode ke driver'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Banner: Driver sudah di titik penjemputan – minta konfirmasi / auto 5 menit
            if (order.status == OrderService.statusAgreed &&
                order.driverArrivedAtPickupAt != null) ...[
              _buildDriverArrivedBanner(order),
              const SizedBox(height: 12),
            ],
            // Tombol SOS Darurat (agreed atau picked_up)
            if (order.status == OrderService.statusAgreed ||
                order.status == OrderService.statusPickedUp) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _onSOS(context, order),
                  icon: const Icon(Icons.emergency, size: 20),
                  label: const Text('SOS Darurat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // 3 action cards: Batalkan, Chat, Lacak Driver
            Row(
              children: [
                Expanded(child: _buildBatalkanCardWithDekatCheck(order)),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionCard(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    color: Theme.of(context).colorScheme.primary,
                    onTap: () => _onChat(order),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: order.isKirimBarang
                      ? _buildActionCard(
                          icon: Icons.local_shipping,
                          label: 'Lacak Barang',
                          color: Colors.green,
                          onTap: () => _onLacakBarang(context, order, isReceiver: false),
                        )
                      : _buildActionCard(
                          icon: Icons.directions_car,
                          label: 'Lacak Driver',
                          color: Colors.green,
                          onTap: () => _onLacakDriver(order),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const Duration _driverArrivedAutoConfirmDuration = Duration(minutes: 15);

  Widget _buildDriverArrivedBanner(OrderModel order) {
    final arrivedAt = order.driverArrivedAtPickupAt!;
    final autoConfirmAt = arrivedAt.add(_driverArrivedAutoConfirmDuration);
    final now = DateTime.now();
    final remaining = autoConfirmAt.difference(now);
    final remainingText = remaining.isNegative
        ? '0 menit'
        : '${remaining.inMinutes} menit ${remaining.inSeconds % 60} detik';

    return Container(
      padding: EdgeInsets.all(context.responsive.spacing(10)),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.amber.shade700, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Driver sudah berada di titik penjemputan.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tanpa perlu tombol: terkonfirmasi otomatis dalam 15 menit berdekatan atau perpindahan 1 km dari titik penjemputan. Notifikasi akan dikirim ke HP Anda.',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
          ),
          const SizedBox(height: 4),
          FutureBuilder<int>(
            future: ViolationService.getViolationFeeRupiah(),
            builder: (context, feeSnap) {
              final feeStr = feeSnap.hasData
                  ? feeSnap.data!.toString().replaceAllMapped(
                      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                      (m) => '${m[1]}.',
                    )
                  : '5.000';
              return Text(
                'Jika tidak scan barcode, akan terkonfirmasi otomatis dan dikenakan denda Rp $feeStr.',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.w500),
              );
            },
          ),
          if (!remaining.isNegative) ...[
            const SizedBox(height: 4),
            Text(
              'Konfirmasi otomatis dalam: $remainingText',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.amber.shade800,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _onMintaKonfirmasiDijemput(order),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Minta konfirmasi dijemput'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMintaKonfirmasiDijemput(OrderModel order) async {
    try {
      await ChatService.sendMessage(
        order.id,
        'Penumpang meminta Anda menekan Konfirmasi dijemput di Data Order.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesan permintaan konfirmasi telah dikirim ke driver.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRatingDialog(BuildContext context, String orderId) {
    int selectedRating = 5;
    final reviewController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Beri rating driver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bagaimana pengalaman perjalanan Anda?'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return IconButton(
                      icon: Icon(
                        star <= selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () => setState(() => selectedRating = star),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  decoration: const InputDecoration(
                    labelText: 'Ulasan (opsional)',
                    hintText: 'Tulis pengalaman Anda...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Nanti saja'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await RatingService.submitPassengerRating(
                  orderId,
                  rating: selectedRating,
                  review: reviewController.text.trim().isEmpty
                      ? null
                      : reviewController.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Terima kasih atas rating Anda!'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatalkanCardWithDekatCheck(OrderModel order) {
    final isAdminCancelled = order.adminCancelled;
    if (_positionForCancel == null) {
      return _buildActionCard(
        icon: Icons.cancel_outlined,
        label: _getBatalkanLabel(order),
        color: Colors.red,
        onTap: isAdminCancelled ? () {} : () => _onBatalkanPesanan(order),
        enabled: !isAdminCancelled,
        disabledHint: isAdminCancelled ? 'Pesanan telah dibatalkan oleh admin' : null,
      );
    }
    return FutureBuilder<bool>(
      future: OrderService.isDriverPenumpangDekatForCancel(
        order: order,
        currentLat: _positionForCancel!.latitude,
        currentLng: _positionForCancel!.longitude,
        isDriver: false,
      ),
      builder: (context, snap) {
        final disable = snap.data == true || order.adminCancelled;
        return _buildActionCard(
          icon: Icons.cancel_outlined,
          label: _getBatalkanLabel(order),
          color: Colors.red,
          enabled: !disable,
          disabledHint: disable && !order.adminCancelled
              ? 'Tidak bisa dibatalkan saat dalam radius ${OrderService.radiusDekatMeter} m dari driver'
              : (order.adminCancelled ? 'Pesanan telah dibatalkan oleh admin' : null),
          onTap: disable
              ? () {
                  if (!order.adminCancelled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Tidak bisa dibatalkan saat dekat dengan driver (radius ${OrderService.radiusDekatMeter} m).',
                        ),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              : () => _onBatalkanPesanan(order),
        );
      },
    );
  }

  void _showPassengerBarcodeFullScreen(BuildContext context, String payload) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tunjukkan barcode ini ke driver',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Label tombol Batalkan: "Batalkan", "Konfirmasi", atau "Dibatalkan oleh admin".
  String _getBatalkanLabel(OrderModel order) {
    if (order.adminCancelled) return 'Dibatalkan oleh admin';
    // Jika driver sudah klik batalkan, penumpang lihat "Konfirmasi"
    if (order.driverCancelled && !order.passengerCancelled) {
      return 'Konfirmasi';
    }
    if (order.status == OrderService.statusCancelled) return 'Dibatalkan';
    return 'Batalkan';
  }

  /// Tombol Batalkan: konfirmasi, jika salah satu klik maka tombol lawan berubah jadi "Konfirmasi".
  Future<void> _onBatalkanPesanan(OrderModel order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Cek apakah ini konfirmasi (lawan sudah klik batalkan)
    final isConfirming = order.driverCancelled && !order.passengerCancelled;

    final title = isConfirming ? 'Konfirmasi Pembatalan' : 'Batalkan Pesanan';
    final content = isConfirming
        ? 'Driver telah membatalkan pesanan. Apakah anda mengkonfirmasi pembatalan ini?'
        : 'Apakah anda membatalkan pesanan?';

    final policyText = 'Kebijakan: Pembatalan tidak dapat dilakukan saat Anda dalam radius ${OrderService.radiusDekatMeter} m dari driver. '
        'Refund (jika ada pembayaran di muka) mengikuti kebijakan Google Play.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(content),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(policyText, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isConfirming ? 'Konfirmasi' : 'Iya'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Set flag cancellation untuk penumpang
    final ok = await OrderService.setCancellationFlag(order.id, false);
    if (!mounted) return;
    if (ok) {
      final message = isConfirming
          ? 'Pembatalan telah dikonfirmasi. Pesanan dibatalkan.'
          : 'Permintaan pembatalan telah dikirim. Menunggu konfirmasi driver.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal membatalkan. Coba lagi.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Tombol Chat: navigasi ke chat room dengan driver.
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

  void _onChat(OrderModel order) {
    final info = _driverInfoCache[order.driverUid];
    final driverName = (info?['displayName'] as String?)?.isNotEmpty == true
        ? (info!['displayName'] as String)
        : 'Driver';
    final driverPhotoUrl = info?['photoUrl'] as String?;
    final driverVerified = info?['verified'] == true;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPenumpangScreen(
          orderId: order.id,
          driverUid: order.driverUid,
          driverName: driverName,
          driverPhotoUrl: driverPhotoUrl,
          driverVerified: driverVerified,
        ),
      ),
    );
  }

  /// Tombol Lacak Barang (kirim barang): pengirim/penerima bayar via Google Play jika belum bayar, lalu full-screen map.
  void _onLacakBarang(BuildContext context, OrderModel order, {required bool isReceiver}) {
    final paid = isReceiver
        ? order.receiverLacakBarangPaidAt != null
        : order.passengerLacakBarangPaidAt != null;
    if (paid) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CekLokasiBarangScreen(
            orderId: order.id,
            isPengirim: !isReceiver,
            order: order,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => LacakBarangPaymentScreen(
            order: order,
            isPengirim: !isReceiver,
          ),
        ),
      );
    }
  }

  /// Tombol Lacak Driver: bayar Rp 3000 via Google Play jika belum bayar, lalu full-screen map dengan posisi driver.
  void _onLacakDriver(OrderModel order) {
    if (order.passengerTrackDriverPaidAt != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CekLokasiDriverScreen(
            orderId: order.id,
            order: order,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => LacakDriverPaymentScreen(order: order),
        ),
      );
    }
  }

  /// Bagikan link lacak ke keluarga. Jika belum bayar Lacak Driver, arahkan ke halaman bayar (sama seperti Lacak Driver).
  Future<void> _onBagikanKeKeluarga(BuildContext context, OrderModel order) async {
    if (order.passengerTrackDriverPaidAt == null) {
      _onLacakDriver(order);
      return;
    }
    try {
      final url = await TrackShareService.generateShareUrl(order);
      await Share.share(
        'Keluarga bisa lacak perjalanan saya di: $url\n\nLink tidak berlaku setelah sampai tujuan.',
        subject: 'Lacak perjalanan Traka',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link berhasil dibagikan. Keluarga bisa buka di browser.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Widget untuk action card yang modern (bukan tombol).
  /// [enabled] false = tampilan disabled (abu-abu), [disabledHint] untuk tooltip saat disabled.
  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    String? disabledHint,
  }) {
    final effectiveColor = enabled ? color : Colors.grey;
    final opacity = enabled ? 1.0 : 0.6;
    final child = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: effectiveColor.withOpacity(enabled ? 0.1 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: effectiveColor.withOpacity(enabled ? 0.3 : 0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: effectiveColor.withOpacity(opacity)),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: effectiveColor.withOpacity(opacity),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    if (!enabled && disabledHint != null && disabledHint.isNotEmpty) {
      return Tooltip(
        message: disabledHint,
        child: child,
      );
    }
    return child;
  }
}

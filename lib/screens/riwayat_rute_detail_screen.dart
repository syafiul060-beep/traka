import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/order_model.dart';
import '../services/chat_service.dart';
import '../services/order_service.dart';

/// Halaman detail satu rute di Riwayat: daftar order completed (penumpang/barang yang sudah dijemput dan diantar).
class RiwayatRuteDetailScreen extends StatefulWidget {
  const RiwayatRuteDetailScreen({
    super.key,
    required this.routeOriginText,
    required this.routeDestText,
    required this.routeJourneyNumber,
    this.scheduleId,
    this.endedAt,
    this.showAllCompleted = false,
    this.orders,
  });

  final String routeOriginText;
  final String routeDestText;
  final String routeJourneyNumber;
  /// Untuk rute terjadwal: agar penumpang per jadwal tampil.
  final String? scheduleId;
  final DateTime? endedAt;
  /// true = tampilkan semua pesanan selesai (fallback untuk riwayat lama tanpa sesi rute).
  final bool showAllCompleted;
  /// Jika diset, pakai daftar order ini (untuk riwayat lama per rute).
  final List<OrderModel>? orders;

  @override
  State<RiwayatRuteDetailScreen> createState() =>
      _RiwayatRuteDetailScreenState();
}

class _RiwayatRuteDetailScreenState extends State<RiwayatRuteDetailScreen> {
  final Map<String, Map<String, dynamic>> _passengerInfoCache = {};

  Future<void> _loadPassengerInfoIfNeeded(List<OrderModel> orders) async {
    final uids = orders
        .where((o) =>
            (o.passengerName.trim().isEmpty ||
                o.passengerPhotoUrl == null ||
                o.passengerPhotoUrl!.trim().isEmpty) &&
            o.passengerUid.isNotEmpty)
        .map((o) => o.passengerUid)
        .where((uid) => !_passengerInfoCache.containsKey(uid))
        .toSet();
    if (uids.isEmpty) return;
    final newInfo = <String, Map<String, dynamic>>{};
    for (final uid in uids) {
      try {
        final info = await ChatService.getUserInfo(uid)
            .timeout(const Duration(seconds: 5));
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
      _passengerInfoCache.addAll(newInfo);
    });
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Rincian Kontribusi Aplikasi: disesuaikan jumlah penumpang (sendiri ×1, dengan kerabat × total).
  List<Widget> _buildKontribusiRincian(OrderModel order) {
    final base = order.tripFareRupiah!;
    final totalPax = order.orderType == OrderModel.typeTravel
        ? order.totalPenumpang
        : 1;
    final total = (base * totalPax).round();
    final baseRounded = base.round();

    final widgets = <Widget>[
      Text(
        'Kontribusi Aplikasi : Rp $total',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];

    if (order.orderType == OrderModel.typeTravel && totalPax > 1) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Rincian: $totalPax orang (1+${order.jumlahKerabat ?? 0} kerabat) × Rp ${baseRounded} = Rp $total',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else if (order.orderType == OrderModel.typeTravel && totalPax == 1) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Rincian: 1 orang (penumpang sendiri) × Rp ${baseRounded} = Rp $total',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Rute'),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.showAllCompleted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.routeOriginText.isNotEmpty
                          ? widget.routeOriginText
                          : 'Lokasi awal',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Icon(
                        Icons.arrow_downward,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      widget.routeDestText.isNotEmpty
                          ? widget.routeDestText
                          : 'Tujuan',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.endedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selesai: ${_formatDate(widget.endedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (widget.routeJourneyNumber.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'No. Rute: ${widget.routeJourneyNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Semua pesanan selesai (riwayat lama)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Penumpang yang sudah sampai tujuan',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.orders != null
                ? Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadPassengerInfoIfNeeded(widget.orders!);
                      });
                      return _buildOrdersList(widget.orders!);
                    },
                  )
                : FutureBuilder<List<OrderModel>>(
                    future: widget.showAllCompleted
                        ? OrderService.getAllCompletedOrdersForDriver()
                        : OrderService.getCompletedOrdersForRoute(
                            widget.routeJourneyNumber,
                            scheduleId: widget.scheduleId,
                          ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final orderList = snapshot.data ?? [];
                      if (orderList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tidak ada pesanan selesai untuk rute ini',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _loadPassengerInfoIfNeeded(orderList);
                });
                return _buildOrdersList(orderList);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<OrderModel> orderList) {
    if (orderList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Tidak ada pesanan selesai untuk rute ini',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      itemCount: orderList.length,
      itemBuilder: (context, index) {
        final order = orderList[index];
        final info = _passengerInfoCache[order.passengerUid];
        final passengerName = order.passengerName.trim().isNotEmpty
            ? order.passengerName
            : (info?['displayName'] as String?)?.trim().isNotEmpty == true
                ? (info!['displayName'] as String)
                : 'Penumpang';
        final passengerPhotoUrl = (order.passengerPhotoUrl != null &&
                order.passengerPhotoUrl!.trim().isNotEmpty)
            ? order.passengerPhotoUrl
            : info?['photoUrl'] as String?;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  (passengerPhotoUrl != null && passengerPhotoUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(passengerPhotoUrl)
                      : null,
              child: (passengerPhotoUrl == null || passengerPhotoUrl.isEmpty)
                  ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : null,
            ),
            title: Text(
              passengerName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (order.orderNumber != null)
                              Text(
                                'No. Pesanan: ${order.orderNumber}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Text(
                              '${order.originText} → ${order.destText}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (order.tripDistanceKm != null)
                              Text(
                                'Jarak: ${order.tripDistanceKm!.toStringAsFixed(1)} km',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (order.tripFareRupiah != null &&
                                order.tripFareRupiah! >= 0)
                              ..._buildKontribusiRincian(order),
                            Text(
                              order.orderType == OrderModel.typeKirimBarang
                                  ? 'Kirim barang'
                                  : (order.totalPenumpang == 1
                                      ? 'Penumpang sendiri'
                                      : 'Penumpang (${order.totalPenumpang} orang)'),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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

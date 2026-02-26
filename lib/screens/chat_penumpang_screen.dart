import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../models/order_model.dart';
import '../services/chat_service.dart';
import '../services/order_service.dart';
import 'chat_room_penumpang_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Halaman daftar chat penumpang (seperti WhatsApp: pilih akun dulu).
/// Menampilkan list obrolan: foto profil + nama driver. Tap → buka ruang chat untuk kirim pesan.
class ChatPenumpangScreen extends StatefulWidget {
  const ChatPenumpangScreen({super.key});

  @override
  State<ChatPenumpangScreen> createState() => _ChatPenumpangScreenState();
}

class _ChatPenumpangScreenState extends State<ChatPenumpangScreen> {
  Map<String, Map<String, dynamic>> _driverInfo = {};
  final ScrollController _scrollController = ScrollController();

  // State untuk selection mode
  bool _isSelectionMode = false;
  final Set<String> _selectedOrderIds = {}; // Set of order IDs yang dipilih

  // Daftar penuh order dari stream (untuk hapus semua order dengan driver yang sama)
  List<OrderModel> _latestAllOrders = [];

  // Cache untuk driver info (untuk menghindari fetch berulang)
  final Map<String, Map<String, dynamic>> _driverInfoCache = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Load driver info untuk order yang belum ada di cache
  /// Hanya memanggil setState ketika ada info yang benar-benar baru (hasil fetch), agar list tidak berkedip.
  Future<void> _loadDriverInfo(List<OrderModel> orders) async {
    final newInfo = <String, Map<String, dynamic>>{};
    final uidsToLoad = orders
        .where((o) => !_driverInfoCache.containsKey(o.driverUid))
        .map((o) => o.driverUid)
        .toSet()
        .toList();
    if (uidsToLoad.isEmpty) return;

    for (final uid in uidsToLoad) {
      try {
        final info = await ChatService.getUserInfo(
          uid,
        ).timeout(const Duration(seconds: 5));
        _driverInfoCache[uid] = info;
        newInfo[uid] = info;
      } catch (_) {
        final defaultInfo = {
          'displayName': 'Driver',
          'photoUrl': null,
          'verified': false,
        };
        _driverInfoCache[uid] = defaultInfo;
        newInfo[uid] = defaultInfo;
      }
    }

    if (mounted && newInfo.isNotEmpty) {
      setState(() {
        _driverInfo = {..._driverInfo, ...newInfo};
      });
    }
  }

  /// Icon kategori pesanan berdasarkan jenis pesanan.
  IconData _getCategoryIcon(OrderModel order) {
    if (order.isKirimBarang) {
      return Icons.local_shipping; // Kirim barang
    } else if (order.isTravelSendiri) {
      return Icons.person; // Travel sendiri
    } else if (order.isTravelKerabat) {
      return Icons.people; // Travel dengan kerabat
    }
    return Icons.directions_car; // Default
  }

  void _openChat(OrderModel order) {
    final info = _driverInfo[order.driverUid];
    final driverName = (info?['displayName'] as String?)?.isNotEmpty == true
        ? info!['displayName'] as String
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

  /// Toggle selection mode
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedOrderIds.clear();
      }
    });
  }

  /// Toggle selection untuk order tertentu
  void _toggleOrderSelection(String orderId, bool isAgreed) {
    // Hanya bisa pilih order yang belum agreed (warna kuning)
    if (isAgreed) return;

    setState(() {
      if (_selectedOrderIds.contains(orderId)) {
        _selectedOrderIds.remove(orderId);
      } else {
        _selectedOrderIds.add(orderId);
      }

      // Keluar dari selection mode jika tidak ada yang dipilih
      if (_selectedOrderIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  /// Hapus order yang dipilih
  Future<void> _deleteSelectedOrders() async {
    if (_selectedOrderIds.isEmpty) return;

    // Konfirmasi hapus
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pesan'),
        content: Text(
          'Apakah Anda yakin ingin menghapus ${_selectedOrderIds.length} pesan yang dipilih?',
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

    // Pisah: pending_agreement dan cancelled → delete; (pembatasan pesanan bisa dihapus manual)
    final idsToDelete = <String>{};
    for (final orderId in _selectedOrderIds) {
      final idx = _latestAllOrders.indexWhere((o) => o.id == orderId);
      if (idx >= 0) {
        final order = _latestAllOrders[idx];
        if (order.status == OrderService.statusCancelled ||
            order.status == OrderService.statusPendingAgreement) {
          final driverUid = order.driverUid;
          for (final o in _latestAllOrders) {
            if (o.driverUid == driverUid &&
                (o.status == OrderService.statusPendingAgreement ||
                    o.status == OrderService.statusCancelled)) {
              idsToDelete.add(o.id);
            }
          }
        }
      } else {
        idsToDelete.add(orderId);
      }
    }
    if (idsToDelete.isEmpty) return;

    int successCount = 0;
    int failCount = 0;
    String? lastError;

    for (final orderId in idsToDelete) {
      try {
        final err = await OrderService.deleteOrderAndChat(orderId);
        if (err == null) {
          successCount++;
        } else {
          failCount++;
          lastError = err;
        }
      } catch (e) {
        failCount++;
        lastError = e.toString();
        if (kDebugMode) debugPrint('Error menghapus order $orderId: $e');
      }
    }

    if (mounted) {
      final msg = failCount > 0
          ? (successCount > 0
                ? 'Berhasil $successCount. $failCount gagal.'
                : 'Gagal menghapus. ${lastError ?? ""}')
          : 'Berhasil menghapus $successCount pesan.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
          duration: failCount > 0
              ? const Duration(seconds: 5)
              : const Duration(seconds: 2),
          action: failCount > 0
              ? SnackBarAction(
                  label: 'OK',
                  textColor: Colors.white,
                  onPressed: () {},
                )
              : null,
        ),
      );
    }

    // Keluar dari selection mode (stream akan otomatis update)
    setState(() {
      _selectedOrderIds.clear();
      _isSelectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode ? '${_selectedOrderIds.length} dipilih' : 'Pesan',
        ),
        elevation: 0,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                if (_selectedOrderIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Hapus',
                    onPressed: _deleteSelectedOrders,
                  ),
              ]
            : null,
      ),
      body: SafeArea(
        child: StreamBuilder<List<OrderModel>>(
          stream: OrderService.streamOrdersForPassenger(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: AppTheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            // Hanya tampilkan chat yang sudah ada isi pesan dan belum selesai.
            // Pesanan selesai tidak ditampilkan agar tidak bisa dihapus/sembunyikan (riwayat tetap di Data Order).
            final allOrders = (snapshot.data ?? [])
                .where((o) => o.lastMessageAt != null && !o.isCompleted)
                .toList();
            _latestAllOrders = allOrders;

            // Kelompokkan orders berdasarkan driverUid, ambil order terbaru per driver
            final Map<String, OrderModel> groupedOrders = {};
            for (final order in allOrders) {
              final driverUid = order.driverUid;
              if (!groupedOrders.containsKey(driverUid)) {
                groupedOrders[driverUid] = order;
              } else {
                final existingOrder = groupedOrders[driverUid]!;
                final existingTime =
                    existingOrder.lastMessageAt ?? existingOrder.updatedAt;
                final currentTime = order.lastMessageAt ?? order.updatedAt;
                if (currentTime != null && existingTime != null) {
                  if (currentTime.isAfter(existingTime)) {
                    groupedOrders[driverUid] = order;
                  }
                } else if (currentTime != null) {
                  groupedOrders[driverUid] = order;
                }
              }
            }

            // Convert ke list dan urutkan berdasarkan waktu terbaru (terbaru di atas)
            final List<OrderModel> orders = groupedOrders.values.toList();
            orders.sort((a, b) {
              final aTime = a.lastMessageAt ?? a.updatedAt;
              final bTime = b.lastMessageAt ?? b.updatedAt;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

            // Load driver info hanya bila ada UID yang belum di cache (hindari setState berulang = berkedip)
            final needDriverInfo = orders.any(
              (o) => !_driverInfoCache.containsKey(o.driverUid),
            );
            if (needDriverInfo) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadDriverInfo(orders);
              });
            }

            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: AppTheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada obrolan',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pesan travel dari map,\nlalu obrolan akan muncul di sini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                // Stream akan otomatis refresh
                setState(() {});
              },
              child: ListView.separated(
                controller: _scrollController,
                reverse: false,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final order = orders[i];
                  final info = _driverInfo[order.driverUid];
                  final driverName =
                      (info?['displayName'] as String?)?.isNotEmpty == true
                      ? (info!['displayName'] as String)
                      : 'Driver';
                  final photoUrl = info?['photoUrl'] as String?;
                  final driverVerified = info?['verified'] == true;

                  // Warna berdasarkan status kesepakatan
                  final isAgreed =
                      order.status == OrderService.statusAgreed ||
                      order.status == OrderService.statusPickedUp;
                  final tileColor = isAgreed
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.yellow.shade50;

                  // Icon kategori pesanan
                  final categoryIcon = _getCategoryIcon(order);

                  final isSelected = _selectedOrderIds.contains(order.id);
                  final canSelect =
                      !isAgreed; // Hanya yang belum agreed bisa dipilih

                  return Container(
                    color: tileColor,
                    child: ListTile(
                      leading: _isSelectionMode && canSelect
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (value) =>
                                  _toggleOrderSelection(order.id, isAgreed),
                            )
                          : CircleAvatar(
                              radius: 28,
                              backgroundColor: AppTheme.outline,
                              backgroundImage:
                                  photoUrl != null && photoUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(photoUrl)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      color: AppTheme.onSurfaceVariant,
                                    )
                                  : null,
                            ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              driverName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (driverVerified) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      subtitle:
                          order.lastMessageText != null &&
                              order.lastMessageText!.isNotEmpty
                          ? Text(
                              order.lastMessageText!,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            categoryIcon,
                            color: isAgreed
                                ? Theme.of(context).colorScheme.primary
                                : Colors.yellow.shade700,
                            size: 24,
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              if (value == 'sembunyikan') {
                                final err = await OrderService.hideChatForPassenger(
                                    order.id);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(err ?? 'Chat disembunyikan'),
                                      backgroundColor:
                                          err != null ? Colors.orange : null,
                                    ),
                                  );
                                }
                              } else if (value == 'hapus') {
                                final err = await OrderService.deleteOrderAndChat(
                                    order.id);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(err ?? 'Pesan dihapus'),
                                      backgroundColor:
                                          err != null ? Colors.orange : null,
                                    ),
                                  );
                                }
                              }
                            },
                            itemBuilder: (ctx) => [
                              if (isAgreed || order.isCompleted)
                                const PopupMenuItem(
                                  value: 'sembunyikan',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility_off),
                                      SizedBox(width: 8),
                                      Text('Sembunyikan'),
                                    ],
                                  ),
                                ),
                              if (!isAgreed && !order.isCompleted)
                                const PopupMenuItem(
                                  value: 'hapus',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Hapus'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      onTap: _isSelectionMode && canSelect
                          ? () => _toggleOrderSelection(order.id, isAgreed)
                          : () => _openChat(order),
                      onLongPress: canSelect
                          ? () {
                              if (!_isSelectionMode) {
                                _toggleSelectionMode();
                              }
                              _toggleOrderSelection(order.id, isAgreed);
                            }
                          : null,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/order_model.dart';
import '../services/driver_contribution_service.dart';
import '../services/order_service.dart';

/// Product ID one-time untuk kontribusi Traka (harus sama dengan di Google Play Console).
const String kContributionProductId = 'traka_contribution_once';

/// Halaman bayar kontribusi driver via Google Play (in-app purchase).
/// Dibuka dari Beranda/Data Order/Chat saat driver wajib bayar (1× kapasitas).
class ContributionDriverScreen extends StatefulWidget {
  const ContributionDriverScreen({super.key});

  @override
  State<ContributionDriverScreen> createState() =>
      _ContributionDriverScreenState();
}

class _ContributionDriverScreenState extends State<ContributionDriverScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  DriverContributionStatus? _status;
  List<OrderModel> _breakdownOrders = [];

  @override
  void initState() {
    super.initState();
    _listenContribution();
    _listenPurchases();
    _loadProducts();
  }

  void _listenContribution() {
    DriverContributionService.streamContributionStatus().listen((status) {
      if (mounted) {
        setState(() => _status = status);
        _loadBreakdownOrders(status);
      }
    });
  }

  Future<void> _loadBreakdownOrders(DriverContributionStatus status) async {
    final count = status.totalPenumpangServed - status.contributionPaidUpToCount;
    if (count <= 0) {
      if (mounted) setState(() => _breakdownOrders = []);
      return;
    }
    final all = await OrderService.getAllCompletedOrdersForDriver();
    final travelOrders = all
        .where((o) => o.orderType == OrderModel.typeTravel)
        .toList();
    int sum = 0;
    final batch = <OrderModel>[];
    for (final o in travelOrders) {
      if (sum >= count) break;
      batch.add(o);
      sum += o.totalPenumpang;
    }
    if (mounted) setState(() => _breakdownOrders = batch);
  }

  void _listenPurchases() {
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _purchaseSub?.cancel(),
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _purchasing = false;
          });
        }
      },
    );
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasing = true);
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            _purchasing = false;
            _error = purchase.error?.message ?? 'Pembayaran gagal';
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _verifyAndComplete(purchase);
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _purchasing = false);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData;
    final orderId = purchase.purchaseID;
    if (token.isEmpty || (orderId?.isEmpty ?? true)) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = 'Data pembayaran tidak lengkap';
        });
      }
      return;
    }
    try {
      await DriverContributionService.verifyContributionPayment(
        purchaseToken: token,
        orderId: orderId!,
        productId: purchase.productID,
      );
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kontribusi berhasil. Anda dapat menerima order dan balas chat.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final available = await _iap.isAvailable();
    if (!available) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Toko aplikasi tidak tersedia';
        });
      }
      return;
    }
    try {
      final response = await _iap.queryProductDetails({kContributionProductId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk kontribusi belum dikonfigurasi di Play Console (ID: $kContributionProductId)';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _products = response.productDetails;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _buy() async {
    if (_products.isEmpty) {
      await _loadProducts();
      if (_products.isEmpty) return;
    }
    final product = _products.first;
    setState(() {
      _purchasing = true;
      _error = null;
    });
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar Kontribusi Traka'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.volunteer_activism,
              size: 64,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Kontribusi driver',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Setelah melayani penumpang 1× kapasitas mobil, driver wajib membayar kontribusi Traka via Google Play. Setelah bayar, Anda dapat kembali menerima order dan balas chat.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (_status != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Penumpang dilayani: ${_status!.totalPenumpangServed}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sudah bayar sampai: ${_status!.contributionPaidUpToCount}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kapasitas mobil: ${_status!.capacity}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (_breakdownOrders.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Rincian penumpang (belum dibayar):',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._breakdownOrders.map((o) {
                          final label = o.totalPenumpang == 1
                              ? '1 orang (penumpang sendiri)'
                              : '${o.totalPenumpang} orang (1+${o.jumlahKerabat ?? 0} kerabat)';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $label',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
            const SizedBox(height: 32),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_products.isNotEmpty)
              FilledButton.icon(
                onPressed: _purchasing ? null : _buy,
                icon: _purchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payment),
                label: Text(
                  _purchasing ? 'Memproses...' : 'Bayar via Google Play',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _loadProducts,
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang produk'),
              ),
          ],
        ),
      ),
    );
  }
}

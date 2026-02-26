import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/order_model.dart';
import '../services/lacak_barang_payment_service.dart';
import '../services/lacak_barang_service.dart';
import 'cek_lokasi_barang_screen.dart';

/// Halaman bayar Lacak Barang via Google Play.
/// [isPengirim]: true = pengirim bayar, false = penerima bayar.
class LacakBarangPaymentScreen extends StatefulWidget {
  const LacakBarangPaymentScreen({
    super.key,
    required this.order,
    required this.isPengirim,
  });

  final OrderModel order;
  final bool isPengirim;

  @override
  State<LacakBarangPaymentScreen> createState() => _LacakBarangPaymentScreenState();
}

class _LacakBarangPaymentScreenState extends State<LacakBarangPaymentScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  int _feeRupiah = 7500;

  @override
  void initState() {
    super.initState();
    _listenPurchases();
    _loadConfigAndProducts();
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
    if (token.isEmpty) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = 'Data pembayaran tidak lengkap';
        });
      }
      return;
    }
    try {
      await LacakBarangPaymentService.verifyLacakBarangPayment(
        purchaseToken: token,
        orderId: widget.order.id,
        payerType: widget.isPengirim ? 'passenger' : 'receiver',
        productId: purchase.productID,
      );
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pembayaran berhasil. Anda dapat melacak barang.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CekLokasiBarangScreen(
              orderId: widget.order.id,
              order: widget.order,
              isPengirim: widget.isPengirim,
            ),
          ),
        );
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

  Future<void> _loadConfigAndProducts() async {
    final originLat = widget.order.pickupLat ?? widget.order.passengerLat ?? widget.order.originLat;
    final originLng = widget.order.pickupLng ?? widget.order.passengerLng ?? widget.order.originLng;
    final destLat = widget.order.receiverLat ?? widget.order.destLat;
    final destLng = widget.order.receiverLng ?? widget.order.destLng;

    if (originLat == null || originLng == null || destLat == null || destLng == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Lokasi tidak lengkap';
          _feeRupiah = 7500;
        });
      }
      return;
    }

    final (_, fee) = await LacakBarangService.getTierAndFee(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    if (mounted) {
      setState(() => _feeRupiah = fee);
    }
    await _loadProducts();
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
    final productId = LacakBarangService.productIdForFee(_feeRupiah);
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk Lacak Barang Rp $_feeRupiah belum dikonfigurasi di Play Console (ID: $productId)';
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
    await _iap.buyConsumable(purchaseParam: param);
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isPengirim ? 'Pengirim' : 'Penerima';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar Lacak Barang'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.local_shipping,
              size: 64,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              'Lacak Barang',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sebagai $label, bayar Rp ${_feeRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} untuk melacak posisi driver dan barang di peta sampai barang diterima.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
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
                  _purchasing
                      ? 'Memproses...'
                      : 'Bayar Rp ${_feeRupiah.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} via Google Play',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.orange.shade700,
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

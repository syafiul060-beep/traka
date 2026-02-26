import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/violation_payment_service.dart';
import '../services/violation_service.dart';

/// Product ID format: traka_violation_fee_{amount}. Contoh: traka_violation_fee_5000, traka_violation_fee_10000.
String violationFeeProductId(int amountRupiah) =>
    'traka_violation_fee_$amountRupiah';

/// Halaman bayar pelanggaran (tidak scan barcode) via Google Play.
/// Penumpang wajib bayar sebelum bisa cari travel lagi.
class ViolationPayScreen extends StatefulWidget {
  const ViolationPayScreen({super.key});

  @override
  State<ViolationPayScreen> createState() => _ViolationPayScreenState();
}

class _ViolationPayScreenState extends State<ViolationPayScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;
  double _outstandingFee = 0;
  int _outstandingCount = 0;
  int _feePerViolation = 5000;

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
      await ViolationPaymentService.verifyViolationPayment(
        purchaseToken: token,
        productId: purchase.productID,
      );
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pembayaran berhasil. Anda dapat mencari travel lagi.'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadOutstanding();
        if (_outstandingFee <= 0) {
          if (mounted) Navigator.of(context).pop();
        }
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
    _feePerViolation = await ViolationService.getViolationFeeRupiah();
    if (mounted) setState(() {});
    await _loadOutstanding();
    await _loadProducts();
  }

  Future<void> _loadOutstanding() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final fee = await ViolationService.getOutstandingViolationFee(user.uid);
    final count = await ViolationService.getOutstandingViolationCount(user.uid);
    if (mounted) {
      setState(() {
        _outstandingFee = fee;
        _outstandingCount = count;
      });
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
    final productId = violationFeeProductId(_feePerViolation);
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.notFoundIDs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Produk pelanggaran Rp $_feePerViolation belum dikonfigurasi di Play Console (ID: $productId)';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar Pelanggaran'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              'Pelanggaran: Tidak Scan Barcode',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Perjalanan terkonfirmasi otomatis tanpa scan barcode (berdasarkan lokasi). Sesuai Ketentuan Layanan, dikenakan biaya Rp ${_feePerViolation.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} per pelanggaran.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_outstandingFee > 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total belum dibayar: Rp ${_outstandingFee.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    if (_outstandingCount > 0)
                      Text(
                        '$_outstandingCount pelanggaran',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange.shade800,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Bayar Rp ${_feePerViolation.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} per pelanggaran via Google Play. Setelah bayar, Anda dapat mencari travel lagi.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      : 'Bayar Rp ${_feePerViolation.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} via Google Play',
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
            if (_outstandingFee > 0 && _outstandingCount > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Anda punya $_outstandingCount pelanggaran. Bayar satu per satu (Rp $_feePerViolation tiap kali).',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

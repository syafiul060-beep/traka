import 'package:cloud_functions/cloud_functions.dart';

/// Service untuk verifikasi pembayaran Lacak Barang via Google Play.
/// payerType: 'passenger' (pengirim) atau 'receiver' (penerima).
class LacakBarangPaymentService {
  static Future<Map<String, dynamic>> verifyLacakBarangPayment({
    required String purchaseToken,
    required String orderId,
    required String payerType,
    required String productId,
    String? packageName,
  }) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyLacakBarangPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'purchaseToken': purchaseToken,
      'orderId': orderId,
      'payerType': payerType,
      'productId': productId,
      if (packageName != null) 'packageName': packageName,
    });
    return result.data;
  }
}

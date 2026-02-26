import 'package:cloud_functions/cloud_functions.dart';

/// Service untuk verifikasi pembayaran pelanggaran penumpang via Google Play.
class ViolationPaymentService {
  /// Panggil Cloud Function untuk verifikasi pembayaran dan update outstanding.
  /// productId: traka_violation_fee_5000, traka_violation_fee_10000, dll.
  static Future<Map<String, dynamic>> verifyViolationPayment({
    required String purchaseToken,
    required String productId,
    String? packageName,
  }) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyViolationPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'purchaseToken': purchaseToken,
      'productId': productId,
      if (packageName != null) 'packageName': packageName,
    });
    return result.data;
  }
}

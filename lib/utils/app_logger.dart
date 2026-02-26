import 'package:flutter/foundation.dart';

/// Log hanya di debug mode. Di release build tidak menulis ke console.
void log(String message, [Object? error, StackTrace? stackTrace]) {
  if (kDebugMode) {
    if (error != null) {
      debugPrint('$message: $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    } else {
      debugPrint(message);
    }
  }
}

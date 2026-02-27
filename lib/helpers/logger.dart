import 'package:flutter/foundation.dart';

void kLog(Object? message) {
  if (kDebugMode) {
    debugPrint(message?.toString());
  }
}

import 'package:flutter/material.dart';

/// App-wide messenger, so background work (optimistic mail actions whose
/// server round trip runs after the UI already moved on) can surface a
/// failure from anywhere — even after the originating screen was popped.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showRootSnackBar(String message) {
  rootMessengerKey.currentState
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: 420,
      duration: const Duration(seconds: 4),
    ));
}

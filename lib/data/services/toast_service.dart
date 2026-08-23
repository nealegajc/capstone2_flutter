import 'package:flutter/material.dart';
import '../../ui/components/alert_toast.dart';

class ToastService {
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void showToast({
    required String title,
    required String message,
    String type = 'info',
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 90.0, right: 24.0, left: 24.0),
        duration: duration,
        content: Center(
          child: AlertToast(
            title: title,
            message: message,
            type: type,
            onDismiss: () => messenger.hideCurrentSnackBar(),
          ),
        ),
      ),
    );
  }
}

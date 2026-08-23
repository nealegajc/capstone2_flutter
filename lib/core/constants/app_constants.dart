class AppConstants {
  static const String appName = 'Otto Scents Smart Shelf';
  static const String appSubtitle = 'Computer Vision Perfume Inventory System';
  static const String storeLocation = 'Otto Scents - Main Kiosk';

  // API Base URL (Local Python FastAPI backend)
  static const String defaultApiBaseUrl = 'http://127.0.0.1:8000';

  // Kiosk UI Specifications
  static const double minTouchTargetSize = 64.0;
  static const double numpadKeyHeight = 76.0;
  static const double numpadKeyWidth = 100.0;
  static const int pinLength = 6;
  static const int maxFailedAttempts = 5;
  static const int lockoutDurationSeconds = 30;

  // Default Fallback PIN for emergency offline owner access
  static const String defaultOwnerPin = '123456';
}

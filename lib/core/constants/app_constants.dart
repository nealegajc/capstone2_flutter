class AppConstants {
  static const String appName = 'Otto Scents Smart Shelf';
  static const String appSubtitle = 'Computer Vision Perfume Inventory System';
  static const String storeLocation = 'Otto Scents - Main Kiosk';

  // API Base URL (Local Python FastAPI backend)
  static const String defaultApiBaseUrl = 'http://127.0.0.1:8000';

  // Kiosk UI Specifications
  static const double minTouchTargetSize = 64.0;
  static const double numpadKeyHeight = 88.0;
  static const double numpadKeyWidth = 120.0;
  static const int pinLength = 6;
  static const int maxFailedAttempts = 5;
  static const int lockoutDurationSeconds = 30;

  // Default Fallback PIN for emergency offline owner access
  static const String defaultOwnerPin = '123456';
  static const int defaultLowStockThreshold = 2;

  // Security Recovery Answers
  static const String recoveryQuestion1 = 'When did the business start?';
  static const String recoveryAnswer1 = '2020';

  static const String recoveryQuestion2 = "What is the owner's nickname?";
  static const String recoveryAnswer2 = 'mj';

  static const String recoveryQuestion3 =
      "Where was the first branch originated?";
  static const String recoveryAnswer3 = 'san pablo';

  // Fragrance Pricing (Universal across branches)
  static const double price100ml = 260.0;
  static const double price50ml = 180.0;

  static double priceFor(String bottleSize) {
    if (bottleSize.toLowerCase().contains('100')) {
      return price100ml;
    }
    return price50ml;
  }
}

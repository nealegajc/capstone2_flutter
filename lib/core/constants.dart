class AppConstants {
  static const String appName = 'Otto Scents Smart Shelf';
  static const String pythonApiBaseUrl = 'http://localhost:8000';

  // Branches
  static const String branchSanPablo = 'San Pablo';
  static const String branchLipa = 'Lipa';
  static const List<String> branches = [branchSanPablo, branchLipa];

  // User Roles
  static const String roleAdmin = 'admin';
  static const String roleStaff = 'staff';

  // Item Status
  static const String statusNormal = 'normal';
  static const String statusLow = 'low';
  static const String statusOutOfStock = 'out_of_stock';
  static const String statusMissing = 'missing';
  static const String statusMisplaced = 'misplaced';
  static const String statusNeedsReview = 'needs_review';

  // Event Types
  static const String eventRemoved = 'REMOVED';
  static const String eventRestocked = 'RESTOCKED';
  static const String eventMisplaced = 'MISPLACED';
  static const String eventVerified = 'VERIFIED';
  static const String eventNeedsReview = 'NEEDS_REVIEW';

  // Alert Types
  static const String alertLowStock = 'low_stock';
  static const String alertOutOfStock = 'out_of_stock';
  static const String alertMissing = 'missing';
  static const String alertMisplaced = 'misplaced';
  static const String alertRestock = 'restock';
  static const String alertConnection = 'connection';
  static const String alertCloud = 'cloud';
  static const String alertQuality = 'image_quality';

  // System Settings Defaults
  static const int defaultLowStockThreshold = 2;
  static const double defaultPricePerUnit = 250.0;
  static const int heartbeatTimeoutSeconds = 90;

  // Touch screen sizing constraints for 1920x1080
  static const double minTouchTargetSize = 56.0;
  static const double bottomNavHeight = 72.0;
  static const double standardCardPadding = 20.0;
}

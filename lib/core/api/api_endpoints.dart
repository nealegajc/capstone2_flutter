class ApiEndpoints {
  // Auth
  static const String verifyPin = '/api/auth/verify-pin';
  static const String changePin = '/api/auth/change-pin';

  // Inventory & Detection
  static const String inventorySummary = '/api/inventory/summary';
  static const String inventoryItems = '/api/inventory/items';
  static const String shelfRegions = '/api/inventory/regions';
  static const String cameraFeed = '/api/camera/stream';
  static const String triggerScan = '/api/camera/scan';

  // Alerts & Logs
  static const String alerts = '/api/alerts';
  static const String restock = '/api/restock';
  static const String syncStatus = '/api/sync/status';
  static const String systemLogs = '/api/logs';
}

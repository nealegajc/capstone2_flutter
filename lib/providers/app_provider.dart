import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../data/models/user_model.dart';
import '../data/models/inventory_record_model.dart';
import '../data/models/alert_model.dart';
import '../data/models/inventory_event_model.dart';
import '../data/models/system_log_model.dart';
import '../data/models/restock_record_model.dart';
import '../data/models/sync_queue_model.dart';
import '../data/models/detection_result_model.dart';
import '../data/models/image_quality_log_model.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/firestore_repository.dart';
import '../data/repositories/python_api_repository.dart';
import '../data/repositories/theme_repository.dart';
import '../data/services/sqlite_service.dart';
import '../data/services/sync_service.dart';
import '../data/services/toast_service.dart';

enum InventoryViewMode { list, grid }

class AppProvider extends ChangeNotifier {
  final AuthRepository _authRepo = AuthRepository();
  final FirestoreRepository _firestoreRepo = FirestoreRepository();
  final PythonApiRepository _pythonApiRepo = PythonApiRepository();
  final ThemeRepository _themeRepo = ThemeRepository();
  final SqliteService _sqlite = SqliteService.instance;
  final SyncService syncService = SyncService.instance;

  // Subscriptions
  StreamSubscription? _inventorySub;
  StreamSubscription? _alertsSub;
  StreamSubscription? _eventsSub;
  StreamSubscription? _logsSub;
  StreamSubscription? _syncQueueSub;
  StreamSubscription? _restockSub;
  Timer? _heartbeatTimer;
  Timer? _calibrationTimer;

  // Auth State
  UserModel? _currentUser;
  bool _isLoggedIn = false;
  bool _isLoadingAuth = false;
  String? _authError;

  // UI / Theme State
  bool _isDarkMode = true;
  int _currentTabIndex = 0;
  InventoryViewMode _inventoryViewMode = InventoryViewMode.list;
  String _selectedInventoryBranch = 'All Branches';
  String _selectedInventoryFilter = 'All Items';
  String _inventorySearchQuery = '';

  // Data Lists
  List<InventoryRecordModel> _inventoryList = [];
  List<AlertModel> _alertsList = [];
  List<InventoryEventModel> _movementLogs = [];
  List<SystemLogModel> _systemLogs = [];
  List<RestockRecordModel> _restockRecords = [];
  List<SyncQueueModel> _syncQueue = [];
  List<DetectionResultModel> _lastDetections = [];
  ImageQualityLogModel? _imageQualityLog;

  // Hardware & Camera / ROI State
  bool _isEdgeConnected = true;
  String _hardwareStatus = 'Active';
  bool _isScanning = false;
  String _scanStatusText = 'Processing...';
  bool _isLiveCalibrationActive = false;
  Uint8List? _calibrationFrame;
  List<double> _roiBoundaries = [0.0, 0.25, 0.50, 0.75, 1.0];
  double _roiTop = 0.15;
  double _roiBottom = 0.85;

  // System Settings
  int _lowStockThreshold = AppConstants.defaultLowStockThreshold;
  String _captureSchedule = 'Every hour';

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoadingAuth => _isLoadingAuth;
  String? get authError => _authError;
  bool get isDarkMode => _isDarkMode;
  int get currentTabIndex => _currentTabIndex;
  InventoryViewMode get inventoryViewMode => _inventoryViewMode;
  String get selectedInventoryBranch => _selectedInventoryBranch;
  String get selectedInventoryFilter => _selectedInventoryFilter;
  String get inventorySearchQuery => _inventorySearchQuery;

  List<InventoryRecordModel> get inventoryList => _filterInventory();
  List<InventoryRecordModel> get allInventoryList => _inventoryList;
  List<AlertModel> get alertsList => _alertsList;
  int get unreadAlertsCount => _alertsList.where((a) => !a.isRead).length;
  List<InventoryEventModel> get movementLogs => _movementLogs;
  List<SystemLogModel> get systemLogs => _systemLogs;
  List<RestockRecordModel> get restockRecords => _restockRecords;
  List<SyncQueueModel> get syncQueue => _syncQueue;
  List<DetectionResultModel> get lastDetections => _lastDetections;
  ImageQualityLogModel? get imageQualityLog => _imageQualityLog;

  bool get isEdgeConnected => _isEdgeConnected;
  String get hardwareStatus => _hardwareStatus;
  bool get isScanning => _isScanning;
  String get scanStatusText => _scanStatusText;
  bool get isLiveCalibrationActive => _isLiveCalibrationActive;
  Uint8List? get calibrationFrame => _calibrationFrame;
  List<double> get roiBoundaries => _roiBoundaries;
  double get roiTop => _roiTop;
  double get roiBottom => _roiBottom;

  int get lowStockThreshold => _lowStockThreshold;
  String get captureSchedule => _captureSchedule;
  DateTime? get lastSyncTime => syncService.lastSyncTime;

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    _isDarkMode = await _themeRepo.loadDarkMode();
    syncService.initialize();

    // 1. Instant local SQLite initialization
    await _loadFromLocalSqlite();

    // 2. Start background streams & hardware heartbeat
    _startStreams();
    _startHeartbeatMonitor();
  }

  Future<void> _loadFromLocalSqlite() async {
    try {
      final branch = _currentUser?.isAdmin == true ? null : _currentUser?.branch;
      _inventoryList = await _sqlite.getInventoryRecords(branch);
      _alertsList = await _sqlite.getAlerts(branch);
      _movementLogs = await _sqlite.getInventoryEvents(branch);
      _systemLogs = await _sqlite.getSystemLogs(branch);
      _syncQueue = await _sqlite.getSyncQueue(branch);

      final settings = await _sqlite.getSystemSettings();
      _captureSchedule = settings['captureSchedule'] as String? ?? 'Every hour';
      _lowStockThreshold = int.tryParse(settings['lowStockThreshold']?.toString() ?? '2') ?? 2;
      if (settings['roiBoundaries'] is List) {
        _roiBoundaries = (settings['roiBoundaries'] as List).map((e) => (e as num).toDouble()).toList();
      }
      _roiTop = double.tryParse(settings['roiTop']?.toString() ?? '0.15') ?? 0.15;
      _roiBottom = double.tryParse(settings['roiBottom']?.toString() ?? '0.85') ?? 0.85;

      notifyListeners();
    } catch (_) {}
  }

  void _startStreams() {
    final branchFilter = _currentUser?.isAdmin == true ? null : _currentUser?.branch;

    _inventorySub?.cancel();
    _inventorySub = _firestoreRepo.streamInventory(branchFilter).listen((list) {
      _inventoryList = list;
      for (final item in list) {
        _sqlite.upsertInventoryRecord(item);
      }
      notifyListeners();
    });

    _alertsSub?.cancel();
    _alertsSub = _firestoreRepo.streamAlerts(branchFilter).listen((list) {
      _alertsList = list;
      for (final item in list) {
        _sqlite.insertAlert(item);
      }
      notifyListeners();
    });

    _eventsSub?.cancel();
    _eventsSub = _firestoreRepo.streamInventoryEvents(branchFilter).listen((list) {
      _movementLogs = list;
      notifyListeners();
    });

    _logsSub?.cancel();
    _logsSub = _firestoreRepo.streamSystemLogs(branchFilter).listen((list) {
      _systemLogs = list;
      notifyListeners();
    });

    _syncQueueSub?.cancel();
    _syncQueueSub = _firestoreRepo.streamSyncQueue(branchFilter).listen((list) {
      _syncQueue = list;
      notifyListeners();
    });

    _restockSub?.cancel();
    _restockSub = _firestoreRepo.streamRestockRecords().listen((list) {
      _restockRecords = list;
      notifyListeners();
    });

    _loadSettings();
    _fetchLatestQualityLog();
  }

  Future<void> _loadSettings() async {
    final settings = await _firestoreRepo.getSystemSettings();
    _captureSchedule = settings['captureSchedule'] as String? ?? 'Every hour';
    _lowStockThreshold = (settings['lowStockThreshold'] as num?)?.toInt() ?? 2;
    if (settings['roiBoundaries'] is List) {
      _roiBoundaries = (settings['roiBoundaries'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }
    _roiTop = (settings['roiTop'] as num?)?.toDouble() ?? 0.15;
    _roiBottom = (settings['roiBottom'] as num?)?.toDouble() ?? 0.85;
    notifyListeners();
  }

  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final status = await _pythonApiRepo.getHardwareStatus();
      _isEdgeConnected = status['connected'] as bool? ?? true;
      _hardwareStatus = status['hardwareStatus'] as String? ?? 'Active';
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------
  Future<bool> login(String email, String password) async {
    _isLoadingAuth = true;
    _authError = null;
    notifyListeners();

    try {
      final user = await _authRepo.signIn(email, password);
      _currentUser = user;
      _isLoggedIn = true;
      _isLoadingAuth = false;
      await _loadFromLocalSqlite();
      _startStreams();

      ToastService.showToast(
        title: 'Welcome, ${user.email}',
        message: 'Signed in as ${user.role.toUpperCase()} (${user.branch})',
        type: 'success',
      );

      final log = SystemLogModel(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        type: 'user_login',
        description: 'User ${user.email} signed in on kiosk.',
        user: user.email,
        branch: user.branch,
      );
      await _sqlite.logSystemActivity(log);
      _firestoreRepo.logSystemActivity(log);

      notifyListeners();
      return true;
    } catch (e) {
      _isLoadingAuth = false;
      _authError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String role,
    required String branch,
  }) async {
    _isLoadingAuth = true;
    _authError = null;
    notifyListeners();

    try {
      final user = await _authRepo.register(email, password, role, branch);
      _currentUser = user;
      _isLoggedIn = true;
      _isLoadingAuth = false;
      await _loadFromLocalSqlite();
      _startStreams();

      ToastService.showToast(
        title: 'Account Registered',
        message: 'Created ${user.role.toUpperCase()} account for ${user.branch}.',
        type: 'success',
      );

      final log = SystemLogModel(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        type: 'user_register',
        description: 'New user ${user.email} registered on kiosk.',
        user: user.email,
        branch: user.branch,
      );
      await _sqlite.logSystemActivity(log);
      _firestoreRepo.logSystemActivity(log);

      notifyListeners();
      return true;
    } catch (e) {
      _isLoadingAuth = false;
      _authError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authRepo.signOut();
    _currentUser = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION & UI STATE
  // ---------------------------------------------------------------------------
  void setTab(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    await _themeRepo.saveDarkMode(_isDarkMode);
  }

  void setInventoryViewMode(InventoryViewMode mode) {
    _inventoryViewMode = mode;
    notifyListeners();
  }

  void setSelectedInventoryBranch(String branch) {
    _selectedInventoryBranch = branch;
    notifyListeners();
  }

  void setInventoryBranchFilter(String branch) => setSelectedInventoryBranch(branch);

  void setSelectedInventoryFilter(String filter) {
    _selectedInventoryFilter = filter;
    notifyListeners();
  }

  void setInventoryStatusFilter(String filter) => setSelectedInventoryFilter(filter);

  void setInventorySearchQuery(String query) {
    _inventorySearchQuery = query;
    notifyListeners();
  }

  List<InventoryRecordModel> _filterInventory() {
    var list = List<InventoryRecordModel>.from(_inventoryList);

    if (_currentUser?.isStaff == true) {
      list = list.where((item) => item.branch == _currentUser?.branch).toList();
    } else if (_selectedInventoryBranch != 'All Branches') {
      list = list.where((item) => item.branch == _selectedInventoryBranch).toList();
    }

    if (_selectedInventoryFilter == 'Low Stock') {
      list = list.where((item) => item.isLowStock).toList();
    } else if (_selectedInventoryFilter == 'Out of Stock') {
      list = list.where((item) => item.isOutOfStock).toList();
    } else if (_selectedInventoryFilter != 'All Items') {
      list = list.where((item) => item.category.toLowerCase() == _selectedInventoryFilter.toLowerCase()).toList();
    }

    if (_inventorySearchQuery.trim().isNotEmpty) {
      final q = _inventorySearchQuery.trim().toLowerCase();
      list = list.where((item) =>
        item.name.toLowerCase().contains(q) ||
        item.perfumeCode.toLowerCase().contains(q) ||
        item.shelf.toLowerCase().contains(q) ||
        item.branch.toLowerCase().contains(q)
      ).toList();
    }

    return list;
  }

  // ---------------------------------------------------------------------------
  // AI VISION SCAN TRIGGER
  // ---------------------------------------------------------------------------
  Future<void> triggerManualScan([String? targetBranch]) async {
    final branch = targetBranch ?? _currentUser?.branch ?? 'San Pablo';
    _isScanning = true;
    _scanStatusText = 'Acquiring camera frame...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));
    _scanStatusText = 'Checking brightness, contrast & sharpness...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));
    _scanStatusText = 'Running YOLOv8 shelf detection...';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));
    _scanStatusText = 'Extracting PaddleOCR perfume codes...';
    notifyListeners();

    final result = await _pythonApiRepo.triggerManualScan(branch);
    _isScanning = false;

    if (result['success'] == true && result['detections'] is List) {
      _lastDetections = (result['detections'] as List)
          .map((d) => DetectionResultModel.fromJson(d as Map<String, dynamic>))
          .toList();
    }

    await _fetchLatestQualityLog();
    await _loadFromLocalSqlite();
    notifyListeners();

    ToastService.showToast(
      title: 'Scan Completed',
      message: result['message'] as String? ?? 'Shelf verification completed.',
      type: 'success',
    );

    final scanLog = SystemLogModel(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      type: 'shelf_check',
      description: 'Manual scan triggered for $branch. Detections verified.',
      user: _currentUser?.email ?? 'Staff',
      branch: branch,
    );
    await _sqlite.logSystemActivity(scanLog);
    _firestoreRepo.logSystemActivity(scanLog);
  }

  Future<void> toggleLiveCalibration() async {
    _isLiveCalibrationActive = !_isLiveCalibrationActive;
    notifyListeners();

    if (_isLiveCalibrationActive) {
      _calibrationTimer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
        if (!_isLiveCalibrationActive) return;
        _calibrationFrame = await _pythonApiRepo.getCalibrationFrame();
        notifyListeners();
      });
    } else {
      _calibrationTimer?.cancel();
    }
  }

  Future<void> updateRoiBoundaries({
    required List<double> boundaries,
    required double top,
    required double bottom,
  }) async {
    _roiBoundaries = boundaries;
    _roiTop = top;
    _roiBottom = bottom;
    notifyListeners();

    await _pythonApiRepo.updateRoiBoundaries(
      boundaries: boundaries,
      top: top,
      bottom: bottom,
    );

    await _sqlite.setSystemSetting('roiBoundaries', boundaries);
    await _sqlite.setSystemSetting('roiTop', top.toString());
    await _sqlite.setSystemSetting('roiBottom', bottom.toString());

    await _firestoreRepo.saveSystemSettings({
      'roiBoundaries': boundaries,
      'roiTop': top,
      'roiBottom': bottom,
    });
  }

  void nudgeRoi(int index, double delta) {
    if (index <= 0 || index >= _roiBoundaries.length - 1) return;
    final updated = List<double>.from(_roiBoundaries);
    updated[index] = (updated[index] + delta).clamp(updated[index - 1] + 0.05, updated[index + 1] - 0.05);
    updateRoiBoundaries(boundaries: updated, top: _roiTop, bottom: _roiBottom);
  }

  Future<void> _fetchLatestQualityLog() async {
    _imageQualityLog = await _pythonApiRepo.getLatestImageQualityLog();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // INVENTORY & PRODUCT ACTIONS (Offline-first SQLite + Cloud Queue)
  // ---------------------------------------------------------------------------
  Future<void> saveInventoryRecord(InventoryRecordModel item) async {
    // 1. Local SQLite Write
    await _sqlite.upsertInventoryRecord(item);

    // 2. Enqueue for Cloud Sync
    await _sqlite.enqueueSyncItem(
      id: 'sync_${item.id}_${DateTime.now().millisecondsSinceEpoch}',
      pendingEventId: item.id,
      targetCollection: 'inventory_records',
      operation: 'UPSERT',
      payload: item.toMap(),
      branch: item.branch,
    );

    // 3. Attempt immediate sync
    syncService.syncPendingQueue();
    await _loadFromLocalSqlite();

    ToastService.showToast(
      title: 'Product Saved',
      message: '${item.name} (${item.perfumeCode}) updated in ${item.branch}.',
      type: 'success',
    );
  }

  Future<void> deleteInventoryRecord(String id) async {
    await _sqlite.deleteInventoryRecord(id);
    await _sqlite.enqueueSyncItem(
      id: 'sync_del_${id}_${DateTime.now().millisecondsSinceEpoch}',
      pendingEventId: id,
      targetCollection: 'inventory_records',
      operation: 'DELETE',
      payload: {},
      branch: _currentUser?.branch ?? 'San Pablo',
    );
    syncService.syncPendingQueue();
    await _loadFromLocalSqlite();

    ToastService.showToast(
      title: 'Product Deleted',
      message: 'Product record removed from inventory.',
      type: 'info',
    );
  }

  // ---------------------------------------------------------------------------
  // ALERT ACTIONS
  // ---------------------------------------------------------------------------
  Future<void> markAlertRead(String id) async {
    await _sqlite.markAlertRead(id);
    await _firestoreRepo.markAlertRead(id);
    await _loadFromLocalSqlite();
  }

  Future<void> markAllAlertsRead() async {
    final unread = _alertsList.where((a) => !a.isRead).map((a) => a.id).toList();
    if (unread.isNotEmpty) {
      await _sqlite.markAllAlertsRead(unread);
      await _firestoreRepo.markAllAlertsRead(unread);
      await _loadFromLocalSqlite();
    }
  }

  Future<void> deleteAlert(String id) async {
    await _sqlite.deleteAlert(id);
    await _firestoreRepo.deleteAlert(id);
    await _loadFromLocalSqlite();
  }

  Future<void> deleteAllReadAlerts() async {
    final readIds = _alertsList.where((a) => a.isRead).map((a) => a.id).toList();
    if (readIds.isNotEmpty) {
      await _sqlite.deleteAllReadAlerts(readIds);
      await _firestoreRepo.deleteAllReadAlerts(readIds);
      await _loadFromLocalSqlite();
    }
  }

  Future<void> deleteSystemLog(String id) async {
    await _sqlite.deleteSystemLog(id);
    await _firestoreRepo.deleteSystemLog(id);
    await _loadFromLocalSqlite();
  }

  Future<void> deleteAllSystemLogs() async {
    await _sqlite.deleteAllSystemLogs();
    final ids = _systemLogs.map((l) => l.id).toList();
    if (ids.isNotEmpty) {
      await _firestoreRepo.deleteAllSystemLogs(ids);
    }
    await _loadFromLocalSqlite();
  }

  // ---------------------------------------------------------------------------
  // SYSTEM SETTINGS & RESTOCK
  // ---------------------------------------------------------------------------
  Future<void> setLowStockThreshold(int threshold) async {
    _lowStockThreshold = threshold;
    notifyListeners();
    await _sqlite.setSystemSetting('lowStockThreshold', threshold.toString());
    await _firestoreRepo.saveSystemSettings({'lowStockThreshold': threshold});
  }

  Future<void> setCaptureSchedule(String schedule) async {
    _captureSchedule = schedule;
    notifyListeners();
    await _sqlite.setSystemSetting('captureSchedule', schedule);
    await _firestoreRepo.saveSystemSettings({'captureSchedule': schedule});
  }

  Future<void> createRestockRequest({
    required String productName,
    required String perfumeCode,
    required int quantity,
    String? fromBranch,
    required String toBranch,
  }) async {
    final effectiveFromBranch = fromBranch ?? (toBranch == 'San Pablo' ? 'Lipa' : 'San Pablo');
    final request = RestockRecordModel(
      id: 'restock_${DateTime.now().millisecondsSinceEpoch}',
      productName: productName,
      perfumeCode: perfumeCode,
      quantity: quantity,
      fromBranch: effectiveFromBranch,
      toBranch: toBranch,
      requestedBy: _currentUser?.email ?? 'staff',
      status: 'pending',
    );

    await _firestoreRepo.createRestockRequest(request);

    final event = InventoryEventModel(
      id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
      eventType: 'RESTOCKED',
      productName: productName,
      perfumeCode: perfumeCode,
      shelfArea: 'Area $perfumeCode',
      branch: toBranch,
      quantity: quantity,
    );
    await _sqlite.logInventoryEvent(event);
    await _firestoreRepo.logInventoryEvent(event);

    ToastService.showToast(
      title: 'Restock Requested',
      message: 'Request for $quantity units of $productName sent to $fromBranch.',
      type: 'success',
    );
  }

  Future<void> forceCloudSync() async {
    final branch = _currentUser?.branch ?? 'San Pablo';
    ToastService.showToast(
      title: 'Syncing With Cloud',
      message: 'Processing pending queue and pulling remote updates...',
      type: 'info',
    );

    await syncService.forceSyncNow(branch);
    await _loadFromLocalSqlite();

    ToastService.showToast(
      title: syncService.isOnline ? 'Sync Completed' : 'Sync Offline',
      message: syncService.isOnline
          ? 'Local SQLite and Cloud Firestore are in sync.'
          : 'Network unavailable. Events stored in local SQLite queue.',
      type: syncService.isOnline ? 'success' : 'warning',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    syncService.stop();
    _inventorySub?.cancel();
    _alertsSub?.cancel();
    _eventsSub?.cancel();
    _logsSub?.cancel();
    _syncQueueSub?.cancel();
    _restockSub?.cancel();
    _heartbeatTimer?.cancel();
    _calibrationTimer?.cancel();
    super.dispose();
  }
}

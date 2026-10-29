import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/inventory_record_model.dart';
import '../data/models/product_model.dart';
import '../data/models/shelf_region_model.dart';
import '../data/models/alert_model.dart';
import '../data/models/inventory_event_model.dart';
import '../data/models/system_log_model.dart';
import '../data/models/sync_queue_model.dart';
import '../data/models/image_quality_log_model.dart';
import '../data/models/restock_record_model.dart';
import '../data/models/hardware_camera_device.dart';
import '../data/services/sqlite_service.dart';
import '../data/services/sync_service.dart';
import '../data/services/camera_hardware_service.dart';
import '../data/services/network_service.dart';
import '../data/repositories/python_api_repository.dart';

final pythonApiRepositoryProvider = Provider<PythonApiRepository>((ref) {
  return PythonApiRepository();
});

/// Edge Vision AI Backend Health Status Provider
final visionBackendHealthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(pythonApiRepositoryProvider);
  return await repo.checkHealth();
});

final sqliteServiceProvider = Provider<SqliteService>((ref) {
  return SqliteService.instance;
});

final syncServiceProvider = ChangeNotifierProvider<SyncService>((ref) {
  return SyncService.instance;
});

final networkServiceProvider = ChangeNotifierProvider<NetworkService>((ref) {
  return NetworkService.instance;
});

final networkStatusProvider = Provider<NetworkStatus>((ref) {
  final netService = ref.watch(networkServiceProvider);
  return netService.status;
});

/// Dynamic Inventory Records Provider
final liveInventoryProvider = FutureProvider.autoDispose
    .family<List<InventoryRecordModel>, String?>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getInventoryRecords(branch);
    });

/// Dynamic Master Products Catalog Provider
final masterProductsProvider = FutureProvider.autoDispose<List<ProductModel>>((
  ref,
) async {
  final sqlite = ref.watch(sqliteServiceProvider);
  return await sqlite.getProducts();
});

/// Dynamic Shelf Regions (6 Cameras) Provider
final shelfRegionsProvider = FutureProvider.autoDispose
    .family<List<ShelfRegionModel>, String>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getShelfRegions(branch);
    });

/// Dynamic Active Alerts Provider
final liveAlertsProvider = FutureProvider.autoDispose
    .family<List<AlertModel>, String?>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getAlerts(branch);
    });

/// Dynamic Stock Movement Events Logs Provider
final stockMovementLogsProvider = FutureProvider.autoDispose
    .family<List<InventoryEventModel>, String?>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getInventoryEvents(branch);
    });

/// Dynamic System Activity Logs Provider
final systemActivityLogsProvider = StreamProvider.autoDispose
    .family<List<SystemLogModel>, String?>((ref, branch) {
      final sqlite = ref.watch(sqliteServiceProvider);
      final syncService = ref.read(syncServiceProvider);

      // Auto-pull latest logs from Supabase cloud in the background once upon provider initialization
      syncService.pullLatestSystemLogs(limit: 200);

      final controller = StreamController<List<SystemLogModel>>();
      Timer? debounceTimer;

      Future<void> emitLogs() async {
        try {
          final logs = await sqlite.getSystemLogs(branch, limit: 300);
          if (!controller.isClosed) {
            controller.add(logs);
          }
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        }
      }

      // Initial fetch
      emitLogs();

      final subscription = sqlite.onActivityLogUpdated.listen((_) {
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 150), () {
          emitLogs();
        });
      });

      ref.onDispose(() {
        debounceTimer?.cancel();
        subscription.cancel();
        controller.close();
      });

      return controller.stream;
    });

/// Dynamic Sync Queue Provider bound to SyncService State
final syncQueueListProvider = FutureProvider.autoDispose
    .family<List<SyncQueueModel>, String?>((ref, branch) async {
      ref.watch(syncServiceProvider);
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getSyncQueue(branch);
    });

/// Dynamic Restock Records Provider
final restockRecordsProvider = FutureProvider.autoDispose
    .family<List<RestockRecordModel>, String?>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getRestockRecords(branch);
    });

/// Dynamic Image Quality Logs Provider
final imageQualityLogsProvider = FutureProvider.autoDispose
    .family<List<ImageQualityLogModel>, String?>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getImageQualityLogs(branch);
    });

/// Computed Dashboard Statistics Provider with 5s Auto-Refresh
class DashboardStats {
  final int totalInStock;
  final int lowStockCount;
  final int misplacedCount;
  final int needsVerificationCount;
  final int totalCapacity;
  final int activeItemCount;

  const DashboardStats({
    required this.totalInStock,
    required this.lowStockCount,
    required this.misplacedCount,
    required this.needsVerificationCount,
    required this.totalCapacity,
    this.activeItemCount = 60,
  });
}

final dashboardStatsProvider = FutureProvider.autoDispose
    .family<DashboardStats, String?>((ref, branch) async {
      final inventory = await ref.watch(liveInventoryProvider(branch).future);
      final alerts = await ref.watch(liveAlertsProvider(branch).future);

      int totalInStock = 0;
      int lowStock = 0;
      int misplaced = 0;
      int needsVerification = 0;
      int activeItemCount = 0;

      for (final item in inventory) {
        if (item.isSeasonalOff) continue;
        activeItemCount++;
        totalInStock += item.detected;
        if (item.isLowStock) lowStock++;
        if (item.status == 'misplaced') misplaced++;
      }

      for (final alert in alerts) {
        if (!alert.isRead && alert.type == 'quality') {
          needsVerification++;
        }
      }

      final capacityItems = activeItemCount > 0
          ? activeItemCount
          : inventory.length;

      return DashboardStats(
        totalInStock: totalInStock,
        lowStockCount: lowStock,
        misplacedCount: misplaced,
        needsVerificationCount: needsVerification,
        totalCapacity: capacityItems * 5, // 5 max bottles per active slot
        activeItemCount: activeItemCount > 0 ? activeItemCount : 60,
      );
    });

// -----------------------------------------------------------------------------
// Hardware Presence Detection & Camera Providers
// -----------------------------------------------------------------------------
final cameraHardwareServiceProvider = Provider<CameraHardwareService>((ref) {
  final service = CameraHardwareService.instance;
  service.startMonitoring();
  ref.onDispose(() => service.stopMonitoring());
  return service;
});

final hardwareCamerasProvider = StreamProvider<List<HardwareCameraDevice>>((
  ref,
) async* {
  final service = ref.watch(cameraHardwareServiceProvider);
  yield await service.probeHardwareDevices();

  // Periodic poll stream
  final controller = StreamController<List<HardwareCameraDevice>>();
  void listener() {
    if (!controller.isClosed) {
      controller.add(service.devices);
    }
  }

  service.addListener(listener);
  ref.onDispose(() {
    service.removeListener(listener);
    controller.close();
  });

  yield* controller.stream;
});

final rapooCameraPresenceProvider = Provider<HardwareCameraDevice?>((ref) {
  final camerasAsync = ref.watch(hardwareCamerasProvider);
  return camerasAsync.when(
    data: (devices) =>
        devices.where((d) => d.isRapooCamera || d.isSunplusCamera).firstOrNull,
    loading: () => null,
    error: (_, _) => null,
  );
});

final sunplusCameraPresenceProvider = Provider<HardwareCameraDevice?>((ref) {
  final camerasAsync = ref.watch(hardwareCamerasProvider);
  return camerasAsync.when(
    data: (devices) => devices.where((d) => d.isSunplusCamera).firstOrNull,
    loading: () => null,
    error: (_, _) => null,
  );
});

final lowStockThresholdProvider = FutureProvider.autoDispose<int>((ref) async {
  final sqlite = ref.watch(sqliteServiceProvider);
  return await sqlite.getLowStockThreshold();
});

final activeMisplacementsProvider = Provider.autoDispose<List<AlertModel>>((ref) {
  final alertsAsync = ref.watch(liveAlertsProvider('San Pablo'));
  return alertsAsync.when(
    data: (alerts) => alerts.where((a) => a.type == 'misplaced' && !a.isRead).toList(),
    loading: () => [],
    error: (_, _) => [],
  );
});

final hasActiveMisplacementProvider = Provider.autoDispose<bool>((ref) {
  final misplacements = ref.watch(activeMisplacementsProvider);
  return misplacements.isNotEmpty;
});


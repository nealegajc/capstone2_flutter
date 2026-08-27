import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../ui/components/kiosk_shell.dart';
import '../../ui/screens/activity_logs/activity_logs_screen.dart';
import '../../ui/screens/alerts/alerts_screen.dart';
import '../../ui/screens/auth/pin_login_screen.dart';
import '../../ui/screens/camera_monitor/camera_monitor_screen.dart';
import '../../ui/screens/camera_monitor/image_quality_screen.dart';
import '../../ui/screens/camera_monitor/schedule_screen.dart';
import '../../ui/screens/camera_monitor/shelf_area_detail_screen.dart';
import '../../ui/screens/camera_monitor/shelf_check_history_screen.dart';
import '../../ui/screens/dashboard/dashboard_screen.dart';
import '../../ui/screens/help_guide/help_guide_screen.dart';
import '../../ui/screens/inventory/inventory_screen.dart';
import '../../ui/screens/inventory/product_detail_screen.dart';
import '../../ui/screens/inventory/product_form_screen.dart';
import '../../ui/screens/inventory/stock_movement_logs_screen.dart';
import '../../ui/screens/reports/reports_screen.dart';
import '../../ui/screens/restock/create_restock_screen.dart';
import '../../ui/screens/restock/receiving_verification_screen.dart';
import '../../ui/screens/restock/restock_screen.dart';
import '../../ui/screens/settings/settings_screen.dart';
import '../../ui/screens/sync_status/sync_queue_screen.dart';
import '../../ui/screens/sync_status/sync_status_screen.dart';
import 'route_names.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutePaths.login,
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final isLoggingIn = state.matchedLocation == AppRoutePaths.login;

      // If not authenticated, ensure user stays on login screen
      if (!authState.isAuthenticated) {
        return isLoggingIn ? null : AppRoutePaths.login;
      }

      // If already authenticated and trying to visit login, send to dashboard
      if (isLoggingIn) {
        return AppRoutePaths.dashboard;
      }

      return null;
    },
    routes: [
      // Fig 3.14: 6-Digit PIN Authentication Entry Screen
      GoRoute(
        path: AppRoutePaths.login,
        name: AppRouteNames.login,
        builder: (context, state) => const PinLoginScreen(),
      ),

      // Kiosk Application Shell (Top Bar & Touch Sidebar)
      ShellRoute(
        builder: (context, state, child) {
          return KioskShell(child: child);
        },
        routes: [
          // Fig 3.15: Dashboard Screen
          GoRoute(
            path: AppRoutePaths.dashboard,
            name: AppRouteNames.dashboard,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),

          // Fig 3.16: Inventory Monitoring Screen
          GoRoute(
            path: AppRoutePaths.inventory,
            name: AppRouteNames.inventory,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: InventoryScreen(),
            ),
          ),

          // Fig 3.17: Product Detail Screen
          GoRoute(
            path: AppRoutePaths.productDetail,
            name: AppRouteNames.productDetail,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProductDetailScreen(),
            ),
          ),

          // Fig 3.18: Add / Edit Product Screen
          GoRoute(
            path: AppRoutePaths.productForm,
            name: AppRouteNames.productForm,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProductFormScreen(),
            ),
          ),

          // Fig 3.24: Stock Movement Logs Screen
          GoRoute(
            path: AppRoutePaths.stockMovements,
            name: AppRouteNames.stockMovements,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: StockMovementLogsScreen(),
            ),
          ),

          // Fig 3.19: Shelf Camera Monitor Screen
          GoRoute(
            path: AppRoutePaths.cameraMonitor,
            name: AppRouteNames.cameraMonitor,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CameraMonitorScreen(),
            ),
          ),

          // Fig 3.20: Shelf Area (ROI) Detail Screen
          GoRoute(
            path: AppRoutePaths.roiDetail,
            name: AppRouteNames.roiDetail,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShelfAreaDetailScreen(),
            ),
          ),

          // Fig 3.21: Shelf Check Schedule Screen
          GoRoute(
            path: AppRoutePaths.schedule,
            name: AppRouteNames.schedule,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ScheduleScreen(),
            ),
          ),

          // Fig 3.22: Shelf Check History Screen
          GoRoute(
            path: AppRoutePaths.shelfHistory,
            name: AppRouteNames.shelfHistory,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShelfCheckHistoryScreen(),
            ),
          ),

          // Fig 3.23: Image Quality & Scanning Status Screen
          GoRoute(
            path: AppRoutePaths.imageQuality,
            name: AppRouteNames.imageQuality,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ImageQualityScreen(),
            ),
          ),

          // Fig 3.25: Restock Management Screen
          GoRoute(
            path: AppRoutePaths.restock,
            name: AppRouteNames.restock,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: RestockScreen(),
            ),
          ),

          // Fig 3.26: Create Restock Record Screen
          GoRoute(
            path: AppRoutePaths.createRestock,
            name: AppRouteNames.createRestock,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CreateRestockScreen(),
            ),
          ),

          // Fig 3.27: Receiving Verification Screen
          GoRoute(
            path: AppRoutePaths.receivingVerification,
            name: AppRouteNames.receivingVerification,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReceivingVerificationScreen(),
            ),
          ),

          // Fig 3.28: Synchronization Status Screen
          GoRoute(
            path: AppRoutePaths.syncStatus,
            name: AppRouteNames.syncStatus,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SyncStatusScreen(),
            ),
          ),

          // Fig 3.29: Pending Synchronization Queue Screen
          GoRoute(
            path: AppRoutePaths.syncQueue,
            name: AppRouteNames.syncQueue,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SyncQueueScreen(),
            ),
          ),

          // Fig 3.30: System Alerts Screen
          GoRoute(
            path: AppRoutePaths.alerts,
            name: AppRouteNames.alerts,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AlertsScreen(),
            ),
          ),

          // Fig 3.31: Reports & Analytics Screen
          GoRoute(
            path: AppRoutePaths.reports,
            name: AppRouteNames.reports,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsScreen(),
            ),
          ),

          // Fig 3.32: System Activity Logs Screen
          GoRoute(
            path: AppRoutePaths.activityLogs,
            name: AppRouteNames.activityLogs,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ActivityLogsScreen(),
            ),
          ),

          // Fig 3.33: Settings & Profile Screen
          GoRoute(
            path: AppRoutePaths.settings,
            name: AppRouteNames.settings,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),

          // Fig 3.34: Help / Simple Guide Screen
          GoRoute(
            path: AppRoutePaths.helpGuide,
            name: AppRouteNames.helpGuide,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HelpGuideScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});

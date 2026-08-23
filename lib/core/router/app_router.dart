import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../ui/components/kiosk_shell.dart';
import '../../ui/screens/activity_logs/activity_logs_screen.dart';
import '../../ui/screens/alerts/alerts_screen.dart';
import '../../ui/screens/auth/pin_login_screen.dart';
import '../../ui/screens/camera_monitor/camera_monitor_screen.dart';
import '../../ui/screens/dashboard/dashboard_screen.dart';
import '../../ui/screens/help_guide/help_guide_screen.dart';
import '../../ui/screens/inventory/inventory_screen.dart';
import '../../ui/screens/product_management/product_management_screen.dart';
import '../../ui/screens/restock/restock_screen.dart';
import '../../ui/screens/settings/settings_screen.dart';
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
      // 1. PIN Authentication Entry Screen (Full screen without Kiosk Shell)
      GoRoute(
        path: AppRoutePaths.login,
        name: AppRouteNames.login,
        builder: (context, state) => const PinLoginScreen(),
      ),

      // 2. Kiosk Application Shell (Persistent Top Bar & Touch Navigation Sidebar)
      ShellRoute(
        builder: (context, state, child) {
          return KioskShell(child: child);
        },
        routes: [
          // Dashboard
          GoRoute(
            path: AppRoutePaths.dashboard,
            name: AppRouteNames.dashboard,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),

          // Inventory Monitoring
          GoRoute(
            path: AppRoutePaths.inventory,
            name: AppRouteNames.inventory,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: InventoryScreen(),
            ),
          ),

          // Shelf Camera Monitor
          GoRoute(
            path: AppRoutePaths.cameraMonitor,
            name: AppRouteNames.cameraMonitor,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CameraMonitorScreen(),
            ),
          ),

          // Product & ROI Management
          GoRoute(
            path: AppRoutePaths.productManagement,
            name: AppRouteNames.productManagement,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProductManagementScreen(),
            ),
          ),

          // Alerts & Shelf Events
          GoRoute(
            path: AppRoutePaths.alerts,
            name: AppRouteNames.alerts,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AlertsScreen(),
            ),
          ),

          // Restock Management & Receiving Verification
          GoRoute(
            path: AppRoutePaths.restock,
            name: AppRouteNames.restock,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: RestockScreen(),
            ),
          ),

          // Synchronization Status
          GoRoute(
            path: AppRoutePaths.syncStatus,
            name: AppRouteNames.syncStatus,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SyncStatusScreen(),
            ),
          ),

          // System Activity Logs & Reports
          GoRoute(
            path: AppRoutePaths.activityLogs,
            name: AppRouteNames.activityLogs,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ActivityLogsScreen(),
            ),
          ),

          // Settings & PIN Management
          GoRoute(
            path: AppRoutePaths.settings,
            name: AppRouteNames.settings,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),

          // Beginner-friendly Help & User Guide
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

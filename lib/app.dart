import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'data/services/toast_service.dart';
import 'data/models/inventory_record_model.dart';
import 'ui/theme/app_theme.dart';
import 'ui/components/bottom_nav.dart';
import 'ui/components/scanning_overlay.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/inventory_screen.dart';
import 'ui/screens/shelf_screen.dart';
import 'ui/screens/alerts_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/product_detail_screen.dart';
import 'ui/screens/product_form_screen.dart';
import 'ui/screens/shelf_area_detail_screen.dart';
import 'ui/screens/reports_screen.dart';
import 'ui/screens/image_quality_screen.dart';
import 'ui/screens/sync_status_screen.dart';
import 'ui/screens/sync_queue_screen.dart';
import 'ui/screens/shelf_check_history_screen.dart';
import 'ui/screens/stock_movement_logs_screen.dart';
import 'ui/screens/system_activity_logs_screen.dart';
import 'ui/screens/help_guide_screen.dart';
import 'ui/screens/coming_soon_screen.dart';

enum AppSubScreen {
  none,
  productDetail,
  productForm,
  shelfAreaDetail,
  reports,
  imageQuality,
  syncStatus,
  syncQueue,
  shelfCheckHistory,
  stockMovementLogs,
  systemActivityLogs,
  helpGuide,
  schedule,
  cloudBackup,
  receivingVerification,
}

class SmartShelfApp extends StatelessWidget {
  const SmartShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return MaterialApp(
          title: 'Otto Scents Smart Shelf',
          scaffoldMessengerKey: ToastService.messengerKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const MainKioskShell(),
        );
      },
    );
  }
}

class MainKioskShell extends StatefulWidget {
  const MainKioskShell({super.key});

  @override
  State<MainKioskShell> createState() => _MainKioskShellState();
}

class _MainKioskShellState extends State<MainKioskShell> {
  AppSubScreen _currentSubScreen = AppSubScreen.none;
  InventoryRecordModel? _selectedProduct;
  String _selectedShelfZone = 'A';

  void _navigateToSubScreen(AppSubScreen subScreen) {
    setState(() => _currentSubScreen = subScreen);
  }

  void _popSubScreen() {
    setState(() {
      _currentSubScreen = AppSubScreen.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    // 1. If not logged in, show LoginScreen
    if (!provider.isLoggedIn) {
      return const LoginScreen();
    }

    // 2. Determine which main tab or subscreen to render
    Widget content;

    switch (_currentSubScreen) {
      case AppSubScreen.productDetail:
        content = ProductDetailScreen(
          item: _selectedProduct ?? provider.allInventoryList.first,
          onBack: _popSubScreen,
          onEdit: () => _navigateToSubScreen(AppSubScreen.productForm),
        );
        break;

      case AppSubScreen.productForm:
        content = ProductFormScreen(
          initialItem: _selectedProduct,
          onBack: _popSubScreen,
        );
        break;

      case AppSubScreen.shelfAreaDetail:
        content = ShelfAreaDetailScreen(
          zoneCode: _selectedShelfZone,
          onBack: _popSubScreen,
        );
        break;

      case AppSubScreen.reports:
        content = ReportsScreen(onBack: _popSubScreen);
        break;

      case AppSubScreen.imageQuality:
        content = ImageQualityScreen(onBack: _popSubScreen);
        break;

      case AppSubScreen.syncStatus:
        content = SyncStatusScreen(
          onBack: _popSubScreen,
          onOpenSyncQueue: () => _navigateToSubScreen(AppSubScreen.syncQueue),
        );
        break;

      case AppSubScreen.syncQueue:
        content = SyncQueueScreen(onBack: () => _navigateToSubScreen(AppSubScreen.syncStatus));
        break;

      case AppSubScreen.shelfCheckHistory:
        content = ShelfCheckHistoryScreen(onBack: _popSubScreen);
        break;

      case AppSubScreen.stockMovementLogs:
        content = StockMovementLogsScreen(onBack: _popSubScreen);
        break;

      case AppSubScreen.systemActivityLogs:
        content = SystemActivityLogsScreen(onBack: _popSubScreen);
        break;

      case AppSubScreen.helpGuide:
        content = HelpGuideScreen(onBack: _popSubScreen);
        break;

      case AppSubScreen.schedule:
        content = ComingSoonScreen(
          title: 'Capture Schedule Settings',
          description: 'Automated interval and daily time capture scheduling module is being prepared for hardware deployment.',
          icon: Icons.schedule_rounded,
          onBack: _popSubScreen,
        );
        break;

      case AppSubScreen.cloudBackup:
        content = ComingSoonScreen(
          title: 'Cloud Backup & Image Sync',
          description: 'High resolution cloud model inference and remote verification archive module.',
          icon: Icons.cloud_done_rounded,
          onBack: _popSubScreen,
        );
        break;

      case AppSubScreen.receivingVerification:
        content = ComingSoonScreen(
          title: 'Receiving Verification',
          description: 'Automated comparison between packing slip and AI shelf detection during stock replenishment.',
          icon: Icons.fact_check_rounded,
          onBack: _popSubScreen,
        );
        break;

      case AppSubScreen.none:
        switch (provider.currentTabIndex) {
          case 0:
            content = HomeScreen(
              onNavigateTab: (tab) => provider.setTab(tab),
              onOpenReports: () => _navigateToSubScreen(AppSubScreen.reports),
              onOpenProductForm: () {
                _selectedProduct = null;
                _navigateToSubScreen(AppSubScreen.productForm);
              },
              onOpenSyncStatus: () => _navigateToSubScreen(AppSubScreen.syncStatus),
              onOpenImageQuality: () => _navigateToSubScreen(AppSubScreen.imageQuality),
            );
            break;

          case 1:
            content = InventoryScreen(
              onSelectProduct: (item) {
                _selectedProduct = item;
                _navigateToSubScreen(AppSubScreen.productDetail);
              },
              onAddProduct: () {
                _selectedProduct = null;
                _navigateToSubScreen(AppSubScreen.productForm);
              },
            );
            break;

          case 2:
            content = ShelfScreen(
              onOpenShelfAreaDetail: (zone) {
                _selectedShelfZone = zone;
                _navigateToSubScreen(AppSubScreen.shelfAreaDetail);
              },
            );
            break;

          case 3:
            content = AlertsScreen(
              onSelectAlert: (alert) {
                // If alert references a perfume code, navigate to that item
                if (alert.perfumeCode.isNotEmpty) {
                  final found = provider.allInventoryList.where((i) => i.perfumeCode == alert.perfumeCode).toList();
                  if (found.isNotEmpty) {
                    _selectedProduct = found.first;
                    _navigateToSubScreen(AppSubScreen.productDetail);
                  }
                }
              },
            );
            break;

          case 4:
          default:
            content = SettingsScreen(
              onOpenReports: () => _navigateToSubScreen(AppSubScreen.reports),
              onOpenSystemLogs: () => _navigateToSubScreen(AppSubScreen.systemActivityLogs),
              onOpenMovementLogs: () => _navigateToSubScreen(AppSubScreen.stockMovementLogs),
              onOpenSyncStatus: () => _navigateToSubScreen(AppSubScreen.syncStatus),
              onOpenImageQuality: () => _navigateToSubScreen(AppSubScreen.imageQuality),
              onOpenHelp: () => _navigateToSubScreen(AppSubScreen.helpGuide),
              onOpenSchedule: () => _navigateToSubScreen(AppSubScreen.schedule),
            );
            break;
        }
        break;
    }

    final isSubScreenActive = _currentSubScreen != AppSubScreen.none;

    return Scaffold(
      body: Stack(
        children: [
          // Main Body
          Positioned.fill(child: content),

          // Floating Bottom Navigation (Visible on top-level tabs)
          if (!isSubScreenActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNav(
                currentIndex: provider.currentTabIndex,
                unreadAlertsCount: provider.unreadAlertsCount,
                onTap: (index) {
                  setState(() => _currentSubScreen = AppSubScreen.none);
                  provider.setTab(index);
                },
              ),
            ),

          // Fullscreen Scanning AI Overlay
          Positioned.fill(
            child: ScanningOverlay(
              isScanning: provider.isScanning,
              statusText: provider.scanStatusText,
            ),
          ),
        ],
      ),
    );
  }
}

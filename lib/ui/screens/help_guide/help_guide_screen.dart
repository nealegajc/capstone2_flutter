import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';

class HelpGuideScreen extends StatefulWidget {
  const HelpGuideScreen({super.key});

  @override
  State<HelpGuideScreen> createState() => _HelpGuideScreenState();
}

class _HelpGuideScreenState extends State<HelpGuideScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'label': 'All Guides', 'icon': Icons.menu_book_rounded},
    {
      'id': 'overview',
      'label': '1. System Overview',
      'icon': Icons.home_rounded,
    },
    {
      'id': 'shelf_layout',
      'label': '2. Shelf Layout & Cap Stickers',
      'icon': Icons.shelves,
    },
    {
      'id': 'camera_vision',
      'label': '3. Live Shelf Cameras',
      'icon': Icons.videocam_rounded,
    },
    {
      'id': 'roi_calibration',
      'label': '4. Aligning Slot Positions',
      'icon': Icons.grid_view_rounded,
    },
    {
      'id': 'inventory_catalog',
      'label': '5. Fragrance Stock & Catalog',
      'icon': Icons.inventory_2_rounded,
    },
    {
      'id': 'restock_flow',
      'label': '6. Restocking & Deliveries',
      'icon': Icons.move_to_inbox_rounded,
    },
    {
      'id': 'sales_reports',
      'label': '7. Sales & Sharing Reports',
      'icon': Icons.point_of_sale_rounded,
    },
    {
      'id': 'alerts_troubleshoot',
      'label': '8. Alerts & Daily Best Practices',
      'icon': Icons.notifications_active_rounded,
    },
    {
      'id': 'security_autolock',
      'label': '9. Security PIN & Auto-Lock',
      'icon': Icons.lock_outline_rounded,
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Otto Scents Smart Shelf - User Guide & Operations Manual'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brandAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.brandAccent.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.brandAccent,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'User Guide',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Search & Category Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Column(
              children: [
                // Search Input Field
                TextField(
                  controller: _searchController,
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.trim().toLowerCase()),
                  style: TextStyle(
                    color: context.textPrimaryColor,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search guides, bottle cap codes, camera views, restocking, sales, or troubleshooting...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.brandAccent,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: context.surfaceElevatedColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Category Filter Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat['id'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            cat['icon'] as IconData,
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : context.textSecondaryColor,
                          ),
                          label: Text(
                            cat['label'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : context.textPrimaryColor,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppColors.brandAccent,
                          backgroundColor: context.surfaceElevatedColor,
                          onSelected: (selected) {
                            if (selected) {
                              setState(
                                () => _selectedCategory = cat['id'] as String,
                              );
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Main Interactive Guide Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 1. Welcome & System Overview
                if (_matchesCategory('overview')) ...[
                  _buildSectionHeader(
                    title: '1. Welcome & How the Smart Shelf Works',
                    subtitle: 'A complete overview of your automated perfume display shelf.',
                    icon: Icons.rocket_launch_rounded,
                    accentColor: AppColors.brandAccent,
                  ),
                  _buildGuideCard(
                    title: 'Welcome to Otto Scents Smart Shelf',
                    badge: 'Overview',
                    badgeColor: AppColors.brandAccent,
                    content: [
                      _p(
                        'The Otto Scents Smart Shelf is an automated retail display that keeps track of your perfume inventory in real time using overhead cameras. Instead of manually scanning barcodes with a handheld scanner, overhead cameras automatically count bottles on the shelf whenever you trigger a scan.',
                      ),
                      _p(
                        'The physical display shelf has 3 horizontal tiers monitored by 6 overhead cameras (2 cameras per tier):',
                      ),
                      _bullet([
                        'Top Shelf (Tier A): Holds 10 Men\'s Fragrance positions (Trays A to K).',
                        'Middle Shelf (Tier B): Holds 5 Men\'s (Trays A to E) and 5 Women\'s (Trays F to K) positions.',
                        'Bottom Shelf (Tier C): Holds 10 Women\'s Fragrance positions (Trays A to K).',
                      ]),
                      _tip(
                        'Total Capacity: 30 Fragrance Variants × 2 Bottle Sizes (100ml & 50ml) = 60 Products total. Each slot holds up to 5 bottles, giving a maximum capacity of 300 bottles across the entire display.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. Shelf Layout & Bottle Cap Stickers
                if (_matchesCategory('shelf_layout')) ...[
                  _buildSectionHeader(
                    title: '2. Shelf Layout & Bottle Cap Stickers',
                    subtitle: 'How perfume bottles are arranged in trays and identified by the cameras.',
                    icon: Icons.shelves,
                    accentColor: AppColors.statusGreen,
                  ),
                  _buildGuideCard(
                    title: 'Tray Compartments: 100ML (Left) & 50ML (Right)',
                    badge: 'Shelf Layout',
                    badgeColor: AppColors.statusGreen,
                    content: [
                      _p(
                        'Each tier has 10 individual acrylic trays (5 trays under the left camera, 5 under the right camera). Every tray is split into two sections:',
                      ),
                      _bullet([
                        'Left Side (100ML): Holds up to 5 large (100ml) perfume bottles.',
                        'Right Side (50ML): Holds up to 5 compact (50ml) perfume bottles.',
                        'Each tray holds a maximum of 10 bottles total (5 of 100ml + 5 of 50ml).',
                      ]),
                      _p(
                        'On the live camera screen, the 100ML slots are outlined in green/teal, and the 50ML slots are outlined in pink/purple for easy visual reference.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: 'Understanding the 3-Character Bottle Cap Sticker Codes',
                    badge: 'Cap Sticker Codes',
                    badgeColor: AppColors.statusBlue,
                    content: [
                      _p(
                        'Each perfume bottle has a circular sticker on top of its cap with a 3-character code (such as AA1 or BK2). This code identifies exactly which shelf, tray, and bottle size it belongs to:',
                      ),
                      _bullet([
                        '1st Character = Shelf Tier: A (Top Shelf), B (Middle Shelf), C (Bottom Shelf)',
                        '2nd Character = Tray Position: Letters A, B, C, D, E, F, G, H, J, or K',
                        '3rd Character = Bottle Size: 1 = 100ML (Left), 2 = 50ML (Right)',
                      ]),
                      _tip(
                        'Examples:\n• "AA1" = Top Shelf (A), Tray A, 100ML bottle.\n• "BA2" = Middle Shelf (B), Tray A, 50ML bottle.\n• "CK1" = Bottom Shelf (C), Tray K, 100ML bottle.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Live Shelf Cameras
                if (_matchesCategory('camera_vision')) ...[
                  _buildSectionHeader(
                    title: '3. Live Shelf Cameras & Video Feeds',
                    subtitle: 'Viewing real-time camera feeds and checking camera connections.',
                    icon: Icons.videocam_rounded,
                    accentColor: AppColors.maleBlue,
                  ),
                  _buildGuideCard(
                    title: 'Checking Live Camera Feeds',
                    badge: 'Camera Feeds',
                    badgeColor: AppColors.maleBlue,
                    content: [
                      _p(
                        'Tap "Shelf Camera" in the left sidebar navigation to view the live overhead camera feeds.',
                      ),
                      _p(
                        'The camera selector at the top organizes the 6 cameras by shelf tier:',
                      ),
                      _bullet([
                        'Top Shelf: Camera 1A (Left: Trays A–E) & Camera 1B (Right: Trays F–K)',
                        'Middle Shelf: Camera 2A (Left: Trays A–E) & Camera 2B (Right: Trays F–K)',
                        'Bottom Shelf: Camera 3A (Left: Trays A–E) & Camera 3B (Right: Trays F–K)',
                      ]),
                      _p('Camera Status Dots:'),
                      _bullet([
                        '🟢 Green Dot: Camera is plugged in, powered, and delivering live video.',
                        '⚪ Grey Dot: Camera is disconnected or unplugged.',
                      ]),
                      _tip(
                        'Tap any camera tab to view its live feed immediately. Live feeds show current shelf conditions and allow you to verify bottle placements in real time.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. Aligning Slot Positions
                if (_matchesCategory('roi_calibration')) ...[
                  _buildSectionHeader(
                    title: '4. Aligning Shelf Slot Positions',
                    subtitle: 'How to adjust slot detection boxes if trays are moved or nudged.',
                    icon: Icons.crop_free_rounded,
                    accentColor: AppColors.brandGold,
                  ),
                  _buildGuideCard(
                    title: 'Adjusting Slot Positions (Slot Alignment)',
                    badge: 'Easy Alignment',
                    badgeColor: AppColors.brandGold,
                    content: [
                      _p(
                        'If a shelf tray is bumped or repositioned during cleaning or restocking, you can easily align the camera detection boxes to match the physical tray location:',
                      ),
                      _step(
                        1,
                        'Open "Shelf Camera" from the sidebar and select the camera for the shelf tier you want to adjust.',
                      ),
                      _step(
                        2,
                        'Tap the "Adjust Slot Positions" button on the screen.',
                      ),
                      _step(
                        3,
                        'Drag the detection box to center it directly over the row of trays.',
                      ),
                      _step(
                        4,
                        'Use the circular corner and edge handles to resize the box until it snugly frames the 5 trays.',
                      ),
                      _step(
                        5,
                        'Make sure the left green half covers the 100ML bottles and the right pink half covers the 50ML bottles.',
                      ),
                      _step(
                        6,
                        'Tap "Save Slot Positions" to save your new alignment.',
                      ),
                      _tip(
                        'You can tap "Reset Positions" anytime if you want to restore the default factory alignment.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 5. Managing Perfumes & Stock Catalog
                if (_matchesCategory('inventory_catalog')) ...[
                  _buildSectionHeader(
                    title: '5. Managing Perfumes & Shelf Capacity',
                    subtitle: 'Checking stock, updating retail prices, seasonal perfumes, and the 30-variant limit.',
                    icon: Icons.inventory_2_rounded,
                    accentColor: AppColors.femalePink,
                  ),
                  _buildGuideCard(
                    title: 'Viewing & Editing Perfumes in Your Store',
                    badge: 'Store Catalog',
                    badgeColor: AppColors.femalePink,
                    content: [
                      _p(
                        'Tap "Inventory" in the sidebar to browse all fragrances in your store.',
                      ),
                      _p(
                        'You can quickly search by fragrance name, brand, or filter by Shelf Tier (A, B, C), Size (100ml, 50ml), or Gender (Men, Women).',
                      ),
                      _step(
                        1,
                        'Editing a Perfume: Tap the Edit (pencil) button on any perfume card to update its name, description, retail price, or stock levels.',
                      ),
                      _step(
                        2,
                        'Seasonal / Paused Fragrances: If a fragrance is out of season or temporarily unavailable, switch its status to "Seasonal / Off". The system will pause camera scanning for that slot and skip low-stock warnings.',
                      ),
                      _step(
                        3,
                        'Deleting a Fragrance: To replace a discontinued fragrance with a new one, tap "Delete Product" in the edit screen. This frees up the slot for a new fragrance.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: 'Understanding the 30-Variant Shelf Capacity',
                    badge: 'Capacity Rule',
                    badgeColor: AppColors.statusOrange,
                    content: [
                      _p(
                        'The physical shelf has exactly 30 tray positions (10 on each of the 3 tiers).',
                      ),
                      _warning(
                        'When all 30 positions are assigned to fragrances, the "Add New Product" button shows "Shelf Full (30/30)". You cannot add more products until an existing fragrance is removed or edited.',
                      ),
                      _tip(
                        'To introduce a new scent, simply edit an existing discontinued scent to update its name and bottle cap sticker code.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 6. Restocking & Receiving Deliveries
                if (_matchesCategory('restock_flow')) ...[
                  _buildSectionHeader(
                    title: '6. Restocking & Receiving Deliveries',
                    subtitle: 'Quickly logging new bottle shipments and verifying shelf counts.',
                    icon: Icons.move_to_inbox_rounded,
                    accentColor: AppColors.statusGreen,
                  ),
                  _buildGuideCard(
                    title: 'Fast 2-Step Restocking Flow',
                    badge: 'Restock Flow',
                    badgeColor: AppColors.statusGreen,
                    content: [
                      _p(
                        'When new perfume stock arrives from the supplier, logging it into the system takes just seconds:',
                      ),
                      _step(
                        1,
                        'Go to "Restock & Deliveries" in the sidebar and tap "Log Restock".',
                      ),
                      _step(
                        2,
                        'Select the fragrance being restocked from the visual cards.',
                      ),
                      _step(
                        3,
                        'Use the quick quantity buttons: tap "+1", "+5", or "Fill Tray (5)".',
                      ),
                      _step(
                        4,
                        'Tap "Confirm Restock" to record the delivery.',
                      ),
                      _step(
                        5,
                        'Place the new bottles into their assigned shelf tray with cap stickers facing upward.',
                      ),
                      _step(
                        6,
                        'On the Dashboard, tap "CHECK SHELF NOW" to run a scan and verify the updated bottle count.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 7. Sales & Sharing Reports
                if (_matchesCategory('sales_reports')) ...[
                  _buildSectionHeader(
                    title: '7. Recording Sales & Sharing Reports',
                    subtitle: 'Logging customer purchases and downloading reports directly to your phone via QR code.',
                    icon: Icons.point_of_sale_rounded,
                    accentColor: AppColors.statusBlue,
                  ),
                  _buildGuideCard(
                    title: 'Recording a Retail Sale',
                    badge: 'Sales',
                    badgeColor: AppColors.statusBlue,
                    content: [
                      _p(
                        'When a customer purchases a bottle:',
                      ),
                      _step(
                        1,
                        'Go to "Sales / Reports" in the sidebar.',
                      ),
                      _step(
                        2,
                        'Tap "Record New Sale" at the top right.',
                      ),
                      _step(
                        3,
                        'Select the fragrance sold, enter quantity, and tap "Complete Sale".',
                      ),
                      _p(
                        'The system records the revenue, updates remaining stock, and logs the sale in today\'s sales summary.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: 'Direct Wi-Fi Phone Transfer via QR Code',
                    badge: 'Share Reports',
                    badgeColor: AppColors.brandAccent,
                    content: [
                      _p(
                        'You do not need a USB drive or flash drive to export your sales and inventory reports. You can download them directly to your smartphone (iPhone or Android):',
                      ),
                      _step(
                        1,
                        'Under "Sales / Reports", tap "View & Share Reports".',
                      ),
                      _step(
                        2,
                        'The screen will display a formatted report summary and a large QR Code.',
                      ),
                      _step(
                        3,
                        'Make sure your smartphone is connected to the same store Wi-Fi network as the kiosk.',
                      ),
                      _step(
                        4,
                        'Open your phone\'s camera app and scan the QR code.',
                      ),
                      _step(
                        5,
                        'Tap the link that appears on your phone screen to instantly download the branded PDF summary or clean CSV spreadsheet directly to your phone.',
                      ),
                      _tip(
                        'No special app or account is required on your phone! Any phone camera can scan the QR code and download the files instantly.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 8. Alerts & Daily Best Practices
                if (_matchesCategory('alerts_troubleshoot')) ...[
                  _buildSectionHeader(
                    title: '8. Alerts, Problem Solving & Daily Best Practices',
                    subtitle: 'Keeping your shelf running smoothly and resolving common alerts.',
                    icon: Icons.notifications_active_rounded,
                    accentColor: AppColors.statusRed,
                  ),
                  _buildGuideCard(
                    title: 'Crucial Daily Best Practices',
                    badge: 'Best Practices',
                    badgeColor: AppColors.statusOrange,
                    content: [
                      _bullet([
                        'Do Not Remove or Restock Bottles During a Scan: Keep hands away from the shelf while the cameras are scanning to avoid inaccurate counts.',
                        'Do Not Cover Perfume Caps or Overhead Cameras: Ensure camera lenses are clear and nothing is resting on top of bottles or cameras.',
                        'Upright Bottle Caps: Make sure bottle caps are closed and cap stickers are facing directly upward so the cameras can detect each bottle.',
                      ]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: 'Common Alerts & How to Fix Them',
                    badge: 'Alerts',
                    badgeColor: AppColors.statusRed,
                    content: [
                      _alertItem(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.statusRed,
                        title: 'Low Stock Alert',
                        desc: 'Appears when 2 or fewer bottles remain in a slot. Restock the slot with new bottles from your storage and tap "CHECK SHELF NOW".',
                      ),
                      const SizedBox(height: 10),
                      _alertItem(
                        icon: Icons.move_up_rounded,
                        color: AppColors.statusOrange,
                        title: 'Misplaced Bottle Alert',
                        desc: 'A bottle was placed into the wrong tray. Move the bottle back to its correct slot (check the cap sticker code, e.g. move AA1 back to Top Shelf, Tray A).',
                      ),
                      const SizedBox(height: 10),
                      _alertItem(
                        icon: Icons.visibility_off_rounded,
                        color: AppColors.brandGold,
                        title: 'Camera View Obstructed Alert',
                        desc: 'A camera lens may be covered or dirty. Clean the camera lens with a microfiber cloth and verify that no signs or foreign objects block the view.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: '100% Offline Capability & Automatic Cloud Backup',
                    badge: 'Offline-First',
                    badgeColor: AppColors.statusBlue,
                    content: [
                      _p(
                        'Your smart shelf terminal is built to work 100% offline. If your store\'s internet connection ever drops:',
                      ),
                      _bullet([
                        'All scans, sales, restocks, and inventory checks continue working normally without pause.',
                        'All records are saved securely inside the kiosk\'s local storage.',
                        'When your Wi-Fi reconnects, all pending records automatically back up to the cloud without needing any manual action.',
                      ]),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 9. Security PIN & Auto-Lock
                if (_matchesCategory('security_autolock')) ...[
                  _buildSectionHeader(
                    title: '9. Security PIN & Inactivity Auto-Lock',
                    subtitle: 'Protecting your terminal and managing lock screen settings.',
                    icon: Icons.lock_outline_rounded,
                    accentColor: AppColors.brandAccent,
                  ),
                  _buildGuideCard(
                    title: 'Security PIN & Inactivity Auto-Lock Settings',
                    badge: 'Security',
                    badgeColor: AppColors.brandAccent,
                    content: [
                      _p(
                        'To prevent unauthorized changes when the kiosk is unattended, the terminal includes PIN protection:',
                      ),
                      _bullet([
                        '6-Digit Security PIN: Used to unlock the kiosk. You can change your PIN anytime under Settings > Security PIN.',
                        'Inactivity Auto-Lock: Automatically locks the screen if no one touches the display for 3 minutes (default).',
                        'Instant Lock Button: Located in the top bar with a live countdown timer (e.g. 🔒 Lock Kiosk [⏱️ 2:50]). Tap it anytime to lock immediately.',
                        'Change Auto-Lock Timer: Under Settings, select your preferred idle timeout: 1m, 2m, 3m, 5m, 10m, or Disabled.',
                        'Forgot PIN Recovery: If you forget your PIN, tap "Forgot PIN?" on the lock screen and answer the 3 security questions to reset your 6-digit PIN.',
                      ]),
                      _tip(
                        'Any touch, tap, or interaction on the screen immediately resets the auto-lock timer back to full duration.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesCategory(String catId) {
    if (_searchQuery.isNotEmpty) return true; // Show all matching search
    if (_selectedCategory == 'all') return true;
    return _selectedCategory == catId;
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideCard({
    required String title,
    required String badge,
    required Color badgeColor,
    required List<Widget> content,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            Divider(height: 20, color: context.borderColor),
            ...content,
          ],
        ),
      ),
    );
  }

  Widget _p(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: context.textPrimaryColor,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _bullet(List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.brandAccent,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textPrimaryColor,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.brandAccent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: context.textPrimaryColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tip(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: AppColors.brandAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: context.textPrimaryColor,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warning(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.statusOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.statusOrange,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: context.textPrimaryColor,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textPrimaryColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

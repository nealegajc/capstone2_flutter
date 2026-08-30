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
    {'id': 'overview', 'label': '1. System Overview', 'icon': Icons.rocket_launch_rounded},
    {'id': 'shelf_layout', 'label': '2. Shelf & Cap Codes', 'icon': Icons.shelves},
    {'id': 'camera_vision', 'label': '3. Camera Vision', 'icon': Icons.videocam_rounded},
    {'id': 'roi_calibration', 'label': '4. Touch ROI Calibration', 'icon': Icons.crop_free_rounded},
    {'id': 'inventory_catalog', 'label': '5. Inventory & Catalog', 'icon': Icons.inventory_2_rounded},
    {'id': 'restock_flow', 'label': '6. Restocking & Receiving', 'icon': Icons.move_to_inbox_rounded},
    {'id': 'alerts_troubleshoot', 'label': '7. Alerts & Safeguards', 'icon': Icons.notifications_active_rounded},
    {'id': 'security_autolock', 'label': '8. Security & Auto-Lock', 'icon': Icons.lock_outline_rounded},
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
        title: const Text('Smart Shelf Master Training & Operations Guide'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brandAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.school_rounded, color: AppColors.brandAccent, size: 18),
                SizedBox(width: 8),
                Text(
                  'Staff Onboarding Handbook',
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
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  style: TextStyle(color: context.textPrimaryColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search guides, instructions, cap codes, camera calibration, or troubleshooting...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.brandAccent),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            color: isSelected ? Colors.white : context.textSecondaryColor,
                          ),
                          label: Text(
                            cat['label'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : context.textPrimaryColor,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppColors.brandAccent,
                          backgroundColor: context.surfaceElevatedColor,
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedCategory = cat['id'] as String);
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
                // 1. Welcome & Head-to-Toe Overview
                if (_matchesCategory('overview')) ...[
                  _buildSectionHeader(
                    title: '1. System Overview: Head-to-Toe Architecture',
                    subtitle: 'Welcome to Otto Scents Smart Shelf! Here is how your automated retail system works.',
                    icon: Icons.rocket_launch_rounded,
                    accentColor: AppColors.brandAccent,
                  ),
                  _buildGuideCard(
                    title: 'Welcome to Your Smart Shelf Terminal',
                    badge: 'Core Concept',
                    badgeColor: AppColors.brandAccent,
                    content: [
                      _p('The Otto Scents Smart Shelf is an AI-powered retail inventory terminal designed to give you real-time visibility into your perfume inventory without manual barcode scanning.'),
                      _p('The physical display shelf consists of 3 horizontal layers monitored by 6 synchronized overhead cameras (2 cameras per layer).'),
                      _bullet([
                        'Layer A (Top Shelf): Holds 10 Men\'s Fragrance variants (Slots A to K).',
                        'Layer B (Middle Shelf): Holds 5 Men\'s (Slots A to E) & 5 Women\'s (Slots F to K) variants.',
                        'Layer C (Bottom Shelf): Holds 10 Women\'s Fragrance variants (Slots A to K).',
                      ]),
                      _tip('Total Capacity: 30 Fragrance Variants × 2 Sizes (100ml & 50ml) = 60 SKUs total. Each slot holds up to 5 bottles, for a maximum shelf capacity of 300 bottles.'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. Shelf Layout & Cap OCR Codes
                if (_matchesCategory('shelf_layout')) ...[
                  _buildSectionHeader(
                    title: '2. Physical Shelf Layout & Cap OCR Codes',
                    subtitle: 'How bottles are positioned in trays and how our vision system identifies each scent.',
                    icon: Icons.shelves,
                    accentColor: AppColors.statusGreen,
                  ),
                  _buildGuideCard(
                    title: 'In-Line Tray Partition (100ML Left • 50ML Right)',
                    badge: 'Physical Layout',
                    badgeColor: AppColors.statusGreen,
                    content: [
                      _p('Each slot partition on the shelf is a straight acrylic tray designed to hold two bottle sizes in an organized in-line split:'),
                      _bullet([
                        'Left Half (100ML Bottles): Rendered in Emerald Cyan (#10B981) on the vision monitor.',
                        'Right Half (50ML Bottles): Rendered in Rose Pink (#EC4899) on the vision monitor.',
                        'Each tray partition holds up to 5 bottles of 100ml on the left and 5 bottles of 50ml on the right.',
                      ]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: 'Understanding the 3-Character Cap Code Structure',
                    badge: 'OCR Standard',
                    badgeColor: AppColors.statusBlue,
                    content: [
                      _p('Every perfume cap features a high-contrast circular sticker with a unique 3-character code. The camera AI reads this code to identify the exact scent, slot, and size:'),
                      _bullet([
                        '1st Character = Shelf Layer (A = Top, B = Middle, C = Bottom)',
                        '2nd Character = Tray Slot Letter (A, B, C, D, E, F, G, H, J, K)',
                        '3rd Character = Bottle Size (1 = 100ML, 2 = 50ML)',
                      ]),
                      _tip('Example: "AA1" = Layer A (Top), Slot A, 100ML (e.g. Bvlgari Extreme 100ml).\nExample: "CA2" = Layer C (Bottom), Slot A, 50ML (e.g. Light Blue 50ml).'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Camera Vision & Live Feeds
                if (_matchesCategory('camera_vision')) ...[
                  _buildSectionHeader(
                    title: '3. 6-Camera Vision & Live Monitor',
                    subtitle: 'Monitoring camera feeds, switching devices, and verifying live streams.',
                    icon: Icons.videocam_rounded,
                    accentColor: AppColors.maleBlue,
                  ),
                  _buildGuideCard(
                    title: 'Viewing Live Camera Feeds & Switching Cameras',
                    badge: 'Vision Feeds',
                    badgeColor: AppColors.maleBlue,
                    content: [
                      _p('Navigate to "Shelf Camera" in the left sidebar to open the 6-Camera Monitor.'),
                      _p('The top camera selector bar organizes the 6 mounted cameras into 3 shelf layers:'),
                      _bullet([
                        'Top Layer A (Male): Cam 1A (Left: Slots A–E) & Cam 1B (Right: Slots F–K)',
                        'Middle Layer B (Mixed): Cam 2A (Left: Slots A–E) & Cam 2B (Right: Slots F–K)',
                        'Bottom Layer C (Female): Cam 3A (Left: Slots A–E) & Cam 3B (Right: Slots F–K)',
                      ]),
                      _p('Connection Status Indicators:'),
                      _bullet([
                        '🟢 Green Status Dot: Hardware camera is connected and recognized on that video node.',
                        '⚪ Grey Status Dot: No camera is plugged into that USB/video port.',
                      ]),
                      _tip('Tap "Start Live View" to begin live streaming. You can switch resolutions anytime between 2K QHD (2560x1440), 1080p FHD, and 720p HD using the top dropdown.'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. Touch ROI Calibration
                if (_matchesCategory('roi_calibration')) ...[
                  _buildSectionHeader(
                    title: '4. Touch & Reshape ROI Calibration',
                    subtitle: 'How to adjust and align the Region of Interest (ROI) to your physical shelf trays.',
                    icon: Icons.crop_free_rounded,
                    accentColor: AppColors.brandGold,
                  ),
                  _buildGuideCard(
                    title: 'Calibrating the Single-Tray Unified ROI Box',
                    badge: 'Step-by-Step',
                    badgeColor: AppColors.brandGold,
                    content: [
                      _p('When cameras are first mounted or repositioned, calibrate the Region of Interest so the AI looks only at the perfume bottles:'),
                      _step(1, 'Open "Shelf Camera" from the sidebar and select the camera you wish to align.'),
                      _step(2, 'Tap the green "Touch & Reshape ROI" button in the top action bar to enter calibration mode.'),
                      _step(3, 'Drag the body of the ROI box to center it over the 5 physical trays.'),
                      _step(4, 'Drag any of the 8 circular handles (4 corners + 4 edges) to resize the box until it tightly frames the 5 trays.'),
                      _step(5, 'Verify that the left half aligns with 100ML bottles (Emerald) and the right half aligns with 50ML bottles (Rose).'),
                      _step(6, 'Tap "Save Tray ROI" to save the calibrated coordinates to local SQLite and cloud storage.'),
                      _tip('Double-tap inside the box or tap "Reset ROI" if you ever want to return to default calibration dimensions.'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 5. Inventory Management & Capacity Lock
                if (_matchesCategory('inventory_catalog')) ...[
                  _buildSectionHeader(
                    title: '5. Inventory Catalog & Capacity Lock',
                    subtitle: 'Registering products, updating prices, and managing the 30-variant shelf capacity.',
                    icon: Icons.inventory_2_rounded,
                    accentColor: AppColors.femalePink,
                  ),
                  _buildGuideCard(
                    title: 'Adding, Editing & Managing Products',
                    badge: 'Catalog Control',
                    badgeColor: AppColors.femalePink,
                    content: [
                      _p('Go to "Inventory" in the sidebar to view all perfume variants currently in your store catalog.'),
                      _p('Search by scent name, brand, or filter by Layer (A, B, C), Size (100ml, 50ml), or Gender (Men, Women).'),
                      _step(1, 'To edit an existing scent: Tap the Edit (pencil) icon on its card.'),
                      _step(2, 'To auto-generate cap codes: Select Layer, Gender, and Size, then tap "Auto-Generate Cap Code" to produce the standard 3-character code (e.g. AA1).'),
                      _step(3, 'To delete a discontinued fragrance: Tap "Delete Product" in the edit screen. This immediately frees up a tray slot for a new fragrance.'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: 'Understanding the 30-Variant Physical Shelf Capacity Lock',
                    badge: 'Safety Rule',
                    badgeColor: AppColors.statusOrange,
                    content: [
                      _p('The physical shelf has exactly 30 tray slots (10 per layer × 3 layers).'),
                      _warning('When all 30 slots are occupied, the "Add New Product" button locks and switches to "Shelf Full (30/30)". You cannot add a 31st scent because there are no physical slots remaining.'),
                      _tip('To introduce a new fragrance, edit an existing variant to replace it or delete an obsolete scent to free up a slot.'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 6. Restocking & Receiving Verification
                if (_matchesCategory('restock_flow')) ...[
                  _buildSectionHeader(
                    title: '6. Restocking & Receiving Verification',
                    subtitle: 'Logging incoming supplier deliveries and checking them against vision scans.',
                    icon: Icons.move_to_inbox_rounded,
                    accentColor: AppColors.statusGreen,
                  ),
                  _buildGuideCard(
                    title: 'How to Log an Incoming Restock Delivery',
                    badge: 'Restock Flow',
                    badgeColor: AppColors.statusGreen,
                    content: [
                      _step(1, 'Go to "Restock Records" in the sidebar and tap "Log New Restock".'),
                      _step(2, 'Select the perfume product being delivered and specify the quantity of bottles (e.g. 5 bottles).'),
                      _step(3, 'Tap "Submit Restock Delivery". The batch is logged in SQLite and inventory is updated.'),
                      _step(4, 'Place the bottles into their designated shelf tray slot.'),
                      _step(5, 'Navigate to the Dashboard and tap "SCAN SHELF NOW" to verify that the camera detects the newly restocked bottles.'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 7. Alerts & Troubleshooting
                if (_matchesCategory('alerts_troubleshoot')) ...[
                  _buildSectionHeader(
                    title: '7. Alerts, Safeguards & Offline Sync',
                    subtitle: 'Resolving misplaced items, low stock warnings, and offline operation.',
                    icon: Icons.notifications_active_rounded,
                    accentColor: AppColors.statusRed,
                  ),
                  _buildGuideCard(
                    title: 'Common Alerts & How to Resolve Them',
                    badge: 'Alerts Guide',
                    badgeColor: AppColors.statusRed,
                    content: [
                      _alertItem(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.statusRed,
                        title: '🔴 Low Stock Alert',
                        desc: 'Triggered when detected bottles drop to 2 or fewer. Log a restock delivery or replenish bottles from backroom inventory.',
                      ),
                      const SizedBox(height: 10),
                      _alertItem(
                        icon: Icons.move_up_rounded,
                        color: AppColors.statusOrange,
                        title: '🟠 Misplaced Product Alert',
                        desc: 'A bottle was returned to the wrong tray or shelf layer. Locate the bottle and place it back into its assigned slot (e.g. move AA1 back to Layer A Top Left).',
                      ),
                      const SizedBox(height: 10),
                      _alertItem(
                        icon: Icons.high_quality_rounded,
                        color: AppColors.brandGold,
                        title: '🟡 Image Quality / Glare Safeguard',
                        desc: 'Camera was temporarily blocked or lighting was too dim. Ensure shelf LED lights are on and tap "SCAN SHELF NOW" to re-verify.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGuideCard(
                    title: '100% Offline Capability & Automatic Cloud Sync',
                    badge: 'Sync Engine',
                    badgeColor: AppColors.statusBlue,
                    content: [
                      _p('Your terminal is fully offline-first! If your store internet drops:'),
                      _bullet([
                        'All scans, sales, inventory adjustments, and logs continue functioning without interruption.',
                        'Transactions are stored locally in the high-speed SQLite database.',
                        'When Wi-Fi reconnects, all pending events automatically synchronize to Supabase Cloud.',
                      ]),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 8. Security & Inactivity Auto-Lock
                if (_matchesCategory('security_autolock')) ...[
                  _buildSectionHeader(
                    title: '8. Security PIN & Inactivity Auto-Lock',
                    subtitle: 'Protecting your terminal with PIN authentication and automatic idle locking.',
                    icon: Icons.lock_outline_rounded,
                    accentColor: AppColors.brandAccent,
                  ),
                  _buildGuideCard(
                    title: 'Security PIN & Inactivity Auto-Lock Settings',
                    badge: 'Security',
                    badgeColor: AppColors.brandAccent,
                    content: [
                      _p('To protect store data from unauthorized changes, the terminal includes access security:'),
                      _bullet([
                        '6-Digit Security PIN: Default is "123456". You can change this anytime under Settings > Security PIN.',
                        'Inactivity Auto-Lock: Automatically locks the screen if no touch interaction is detected for 3 minutes (default).',
                        'Unified Lock Button: Located in the top-right bar with live countdown badge (e.g. 🔒 Lock Kiosk [⏱️ 2:52]). Tap it anytime to lock instantly.',
                        'Configuring Timeout: Go to Settings > Terminal Inactivity Auto-Lock to select 1m, 2m, 3m, 5m, 10m, or Disabled.',
                      ]),
                      _tip('Any touch, tap, or mouse movement on the screen instantly resets the idle timer back to your configured timeout.'),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
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
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandAccent)),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(fontSize: 13, color: context.textPrimaryColor, height: 1.3),
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
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: context.textPrimaryColor, height: 1.3),
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
          const Icon(Icons.lightbulb_outline_rounded, color: AppColors.brandAccent, size: 18),
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
        border: Border.all(color: AppColors.statusOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.statusOrange, size: 18),
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
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: context.textPrimaryColor, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

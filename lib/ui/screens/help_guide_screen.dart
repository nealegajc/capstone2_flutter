import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/scroll_screen.dart';

class HelpGuideScreen extends StatefulWidget {
  final VoidCallback onBack;

  const HelpGuideScreen({super.key, required this.onBack});

  @override
  State<HelpGuideScreen> createState() => _HelpGuideScreenState();
}

class _HelpGuideScreenState extends State<HelpGuideScreen> {
  int? _expandedIndex = 0;

  final List<Map<String, dynamic>> _topics = [
    {
      'title': '1. Aligning the Shelf Regions of Interest (ROI)',
      'desc': 'Navigate to the "Shelf AI" tab and tap "Start Live Calibration". Drag the green vertical dividers so each perfume compartment (A, B, C, D) has its own zone. Use the Nudge buttons for 1% fine adjustments.',
    },
    {
      'title': '2. Real-Time YOLOv8 & PaddleOCR Scanning',
      'desc': 'The overhead camera captures shelf frames periodically or when triggered manually. YOLO detects bottle caps, while PaddleOCR recognizes the printed letter code (A/B/C/D) to verify variant accuracy.',
    },
    {
      'title': '3. Image Quality Assessment & Preprocessing',
      'desc': 'Before executing AI detection, the frame is evaluated for brightness (min 40%), contrast, and sharpness. OpenCV applies CLAHE histogram equalization and sharpening if lighting is suboptimal.',
    },
    {
      'title': '4. Offline-First SQLite Operation',
      'desc': 'When internet connection is lost, all shelf checks, ROI calibrations, and stock movements continue locally inside SQLite. Events are queued and automatically synced once online.',
    },
    {
      'title': '5. Multi-Branch Cloud Synchronization',
      'desc': 'The San Pablo main branch kiosk and Lipa secondary branch kiosk continuously replicate state through Cloud Firestore for centralized inventory monitoring and restocking.',
    },
    {
      'title': '6. Detecting Misplaced Perfume Bottles',
      'desc': 'If a bottle with cap code "B" is placed inside Zone "A", the system automatically creates a "Misplaced Item" alert and flags the compartment for staff attention.',
    },
    {
      'title': '7. Low Stock Warnings & Thresholds',
      'desc': 'When detected count drops to or below the configured low stock threshold (default 2 bottles), an orange warning notification is sent to the Alerts center.',
    },
    {
      'title': '8. Requesting Inter-Branch Restock',
      'desc': 'Staff can open any product detail page and tap "Request Branch Restock" to transfer inventory between San Pablo and Lipa branches.',
    },
    {
      'title': '9. Touchscreen Kiosk Navigation',
      'desc': 'Designed with large 56px+ tap targets, high contrast AMOLED dark mode, and a 5-tab pill navigation bar optimized for 1920x1080 landscape displays.',
    },
    {
      'title': '10. Registering New Fragrances',
      'desc': 'Admin users can navigate to Settings > Register Product to create new SKUs, assign them to shelf letter codes (A–D), and configure retail pricing.',
    },
    {
      'title': '11. Role-Based Access Control',
      'desc': 'Admin accounts (San Pablo) have full management rights including financial reports, product creation, and log deletion. Staff accounts (Lipa) focus on daily shelf operations.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScrollScreen(
      title: 'Help & Operational Guide',
      subtitle: 'Complete documentation for Smart Shelf kiosk setup, calibration, and AI workflows',
      showBackButton: true,
      onBack: widget.onBack,
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _topics.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final topic = _topics[index];
            final isExpanded = _expandedIndex == index;

            return AppCard(
              onTap: () {
                setState(() {
                  _expandedIndex = isExpanded ? null : index;
                });
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          topic['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ],
                  ),
                  if (isExpanded) ...[
                    const Divider(height: 24),
                    Text(
                      topic['desc'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

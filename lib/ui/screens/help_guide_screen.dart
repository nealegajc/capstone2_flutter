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
      'title': '1. 3-Camera Multi-Shelf Architecture & Optical Alignment',
      'desc': 'The kiosk integrates 3 fixed overhead cameras corresponding to 3 shelf tiers:\n• Camera 1: Layer A (Top Shelf — Male Scents #1–#19, Cap Codes AA1–AK2)\n• Camera 2: Layer B (Middle Shelf — 5 Male + 5 Female, Cap Codes BA1–BK2)\n• Camera 3: Layer C (Bottom Shelf — Female Scents #14–#32, Cap Codes CA1–CK2)\nEach tier houses 20 SKUs (10 fragrance variants × 2 bottle sizes: 100ML & 50ML).',
    },
    {
      'title': '2. Real-Time YOLOv8 & Cap OCR Vision Verification',
      'desc': 'When triggered from the Dashboard or Camera Monitor, the system captures a frame via the plugged-in Rapoo USB camera (/dev/video2). YOLOv8 detects individual bottle boundaries, while OCR decodes the 3-character cap code (e.g., AA1, BA2, CK1) to count and verify each perfume SKU.',
    },
    {
      'title': '3. Automated Misplacement & Low Stock Alert Detection',
      'desc': 'If a bottle with cap code "AA1" is detected within the ROI compartment assigned to "AA2", a "Misplaced Item" incident is instantly flagged. If any perfume variant drops below the safety threshold (default: 2 bottles), a Low Stock notice is dispatched to the Alerts Center.',
    },
    {
      'title': '4. Hardware-Accelerated Zero-Copy MJPEG Live Feed',
      'desc': 'The camera monitor runs an on-demand 30 FPS hardware stream directly from the Rapoo webcam using native V4L2 MJPEG decoding. Stream only runs when actively monitored to preserve CPU resources for AI inference.',
    },
    {
      'title': '5. Offline-First SQLite Operation & Cloud Sync',
      'desc': 'All stock counts, scans, and audit trail logs are stored securely in local SQLite databases. When network connectivity is established, records automatically replicate to Supabase Cloud.',
    },
    {
      'title': '6. Store Owner 6-Digit PIN Security',
      'desc': 'The kiosk requires a 6-digit PIN to unlock. Store owners can securely change their PIN in Settings > Security. The updated hash is stored in SQLite with SHA-256 encryption, invalidating previous PINs immediately.',
    },
    {
      'title': '7. Restock & Shipment Verification',
      'desc': 'When new perfume shipments arrive, staff log the batch in "Restock Records". Once bottles are placed onto the corresponding shelf layer, the camera scan automatically validates physical placement against the delivery manifest.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ScrollScreen(
      title: 'Otto Scents Kiosk Help & Operational Manual',
      subtitle: 'Complete documentation for 3-camera setup, YOLOv8 vision scanning, cap OCR, and inventory workflows',
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
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 26,
                      ),
                    ],
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(
                      topic['desc'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
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

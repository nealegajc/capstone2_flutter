# Project: OttoScents Smart Shelf Single-Store Kiosk Conversion (R1–R6)

## Architecture
- **Target Form Factor**: Linux Desktop x64 touchscreen kiosk for single store owner (`ottoscents@192.168.1.16`, Display `:0`).
- **Core Principles**:
  - Offline-first standalone architecture with zero dependency on multi-branch routing.
  - Strict retail terminology: elimination of technical jargon (OCR, YOLO, bounding boxes, device nodes, etc.).
  - Friendly retail operations: 2-step restocking, plain-language 9-category handbook, instant automatic bottle counter.
  - Single "Store Owner" profile secured by 6-digit PBKDF2 PIN.
  - Pure YOLO vision backend without dead OCR models or residual branch parameters.
  - Synchronized SQLite local database (v4 table-recreation migration) and single-store Supabase cloud backup.

---

## Feature Inventory

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Pre-Scan Readiness Checklist | Remove lighting/door checks; add Do Not Remove/Restock and Do Not Cover Caps/Cameras; retain upright caps | M1 | R1 |
| F2 | Pipeline Friendly Phrasing | Friendly "Instant Automatic Bottle Counter" banner and retail progress log strings in ScanWorkflowDialog | M1 | R1 |
| F3 | Checklist Test Assertions | Update unit/widget test assertions for R1 checklist rules to keep 100% test pass rate | M1 | R1 |
| F4 | Camera Monitor Terminology | Live Shelf Cameras, Align Shelf Trays, Save Tray Positions, Camera & Shelf Status, Camera Port (Port X) | M2 | R2 |
| F5 | Product Detail & Form Terminology | Bottle Cap Sticker Code, Detection & Verification Status, Detection Accuracy (99.2% Confirmed), Shelf Slot Area | M2 | R2 |
| F6 | Alerts Screen Terminology | Bottle in Wrong Slot, Camera View Obstructed, Smart Bottle Detection Active | M2 | R2 |
| F7 | Reports Screen Clean Retail Exports | Direct CSV Downloads & Store Records, remove branch filters and multi-branch dropdowns | M2 | R2 |
| F8 | Dashboard & Kiosk Shell Branding | Otto Scents - Smart Shelf Kiosk, QUICK ACTIONS, User Guide, Otto Scents Kiosk • ONLINE | M2 | R2 |
| F9 | Business Recovery Question | Security Question 3: "What is the name of the business?", Answer: "ottoscents" in AppConstants & PinRecoveryDialog | M2 | R2 |
| F10 | Operations Manual Overhaul | 9 comprehensive non-technical retail categories in HelpGuideScreen | M3 | R3 |
| F11 | Guide Search Filter Bug Fix | Fix unconditional return on line 654; enable real-time keyword search across guide categories and cards | M3 | R3 |
| F12 | Single Store Owner Profile | Eliminate multi-user roles ("admin", "staff", "manager") and user switching; establish single Store Owner profile | M4 | R4 |
| F13 | Settings Screen Account Cleanup | Remove Assigned Branch card; simplify to Store Owner PIN management and terminal options | M4 | R4 |
| F14 | Data Models Branch Pruning | Remove branch fields, getters, constructors, serialization from 10 data models | M5 | R5 |
| F15 | SQLite v4 Migration & Query Pruning | Drop branch from schemas, implement v4 table recreation migration preserving all records, prune branch parameters | M5 | R5 |
| F16 | Services & Providers Branch Cleanup | SyncService, RoiProvider, PythonApiRepository, ReportExportService, and Riverpod providers cleanup | M5 | R5 |
| F17 | Backend Branch & Dead Code Pruning | Remove branch from FastAPI routes & pipeline.py; delete dataset_generator.py, obsolete .pt models, dataset/, __pycache__ | M5 | R5 |
| F18 | Remote Supabase Migration & Re-Seed | Apply SQL migration dropping NOT NULL and branch columns; update seed_supabase_direct.dart and re-seed clean single-store data | M5 | R5 |
| F19 | Static Analysis & Test Verification | flutter analyze 0 issues; flutter test 100% passing across all suites | M6 | R6 |
| F20 | Linux Release Compilation & Bundling | flutter build linux --release with BypassSandbox: true; bundle .env, best.pt, camera_assignments.json | M6 | R6 |
| F21 | Hardware Deployment & Display :0 Verification | rsync bundle to Mini PC (192.168.1.16); restart smart-shelf-kiosk.service; verify live display :0 with screenshots | M6 | R6 |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Pre-Scan Readiness Checklist & Pipeline Phrasing | F1, F2, F3: `ScanWorkflowDialog`, `kiosk_ui_refactor_test.dart`, `seasonal_scan_and_redundancy_test.dart` | none | DONE |
| M2 | Complete System-Wide Elimination of Technical Jargon | F4, F5, F6, F7, F8, F9: CameraMonitor, Product screens, Alerts, Reports, Dashboard, KioskShell, AppConstants, PinRecovery | M1 | IN_PROGRESS |
| M3 | In-App User Guide & Operations Manual Overhaul | F10, F11: `HelpGuideScreen` search fix + 9 retail categories | M2 | PLANNED |
| M4 | Single Store Owner Profile & Security | F12, F13: `SettingsScreen`, `SqliteService` user seed, PIN dialogs | M2 | PLANNED |
| M5 | End-to-End Frontend & Backend Codebase Cleanup | F14, F15, F16, F17, F18: Models, SQLite v4, SyncService, Providers, vision_backend, dead assets, Supabase migration | M1, M2, M4 | PLANNED |
| M6 | Verification, Build & Hardware Deployment | F19, F20, F21: flutter analyze, flutter test, flutter build linux --release, rsync, service restart, display :0 verification | M1, M2, M3, M4, M5 | PLANNED |

---

## Interface Contracts

### 1. Pre-Scan Checklist & Pipeline (`scan_workflow_dialog.dart`)
- Checklist Items:
  1. "Do Not Remove or Restock Bottles During Scan" (`Icons.pan_tool_rounded`)
  2. "Do Not Cover Perfume Caps or Camera Lenses" (`Icons.visibility_rounded`)
  3. "Upright Bottle Caps Facing Upward" (`Icons.vertical_align_top_rounded`)
- Pipeline Phases:
  1. Camera Check (`Icons.videocam_rounded`)
  2. Clarity Check (`Icons.auto_awesome_rounded`)
  3. Bottle Counter (`Icons.pin_rounded`)
  4. Slot Mapping (`Icons.grid_view_rounded`)
  5. Inventory Sync (`Icons.sync_rounded`)

### 2. Retail Phrasing Contracts
- Device nodes `/dev/video*` -> `"Camera Port (Port X)"`
- "Cap OCR Code" -> `"Bottle Cap Sticker Code"`
- "PaddleOCR & AI Vision Telemetry" -> `"Detection & Verification Status"`
- "OCR Recognition Confidence" -> `"Detection Accuracy (99.2% Confirmed)"`
- "Bounding Box ROI Target" -> `"Shelf Slot Area"`
- "Misplaced Product Alert" -> `"Bottle in Wrong Slot"`
- "Image Quality Safeguard" -> `"Camera View Obstructed"`
- "YOLOv8 + Cap OCR active" -> `"Smart Bottle Detection Active"`
- "Legacy CSV Exports & Diagnostics Auditing" -> `"Direct CSV Downloads & Store Records"`
- "Otto Scents - Branch Kiosk (San Pablo)" -> `"Otto Scents - Smart Shelf Kiosk"`
- "STAFF ACTIONS" -> `"QUICK ACTIONS"`
- "Staff Handbook" -> `"User Guide"`
- "Branch: San Pablo" -> `"Otto Scents Kiosk • ONLINE"`
- Question 3: `"What is the name of the business?"`, Answer: `"ottoscents"`

### 3. SQLite Database Schema Version 4 Migration (`sqlite_service.dart`)
- Version bumped from 3 to 4.
- Tables migrated via temporary table recreation: `inventory_records`, `shelf_regions`, `alerts`, `sales_records`, `inventory_events`, `restock_records`, `system_logs`, `image_quality_logs`, `sync_queue`, `users`.
- Dropped indexes: `idx_inventory_branch`, `idx_shelf_regions_branch`, `idx_alerts_branch_read`, `idx_sales_records_branch_time`, `idx_inventory_events_branch_time`, `idx_restock_records_branch`, `idx_system_logs_branch_time`.
- Created replacement indexes: `idx_inventory_code`, `idx_alerts_read`, `idx_sales_records_sold_at`, `idx_inventory_events_time`, `idx_restock_records_status`, `idx_system_logs_time`.
- Query signatures made non-breaking: `[String? branch]` or `{String? branch}` where callers can pass or omit.

### 4. Vision Backend Clean Endpoints (`vision_backend/main.py`)
- `/api/camera/scan`: accepts `cameraId: Optional[int]`, `camera_device: Optional[str]` without `branch`.
- `/api/camera/test`: accepts `camera_id: Optional[int]`, `camera_device: Optional[str]` without `branch`.
- Deleted: `dataset_generator.py`, `models/cap_recognizer*.pt`, `dataset/`.

---

## Code Layout

- **M1 (Checklist & Pipeline)**:
  - `lib/ui/components/scan_workflow_dialog.dart`
  - `test/kiosk_ui_refactor_test.dart`
  - `test/seasonal_scan_and_redundancy_test.dart`
- **M2 (Retail Jargon Elimination)**:
  - `lib/ui/screens/camera_monitor/camera_monitor_screen.dart`
  - `lib/ui/screens/inventory/product_detail_screen.dart`
  - `lib/ui/screens/inventory/product_form_screen.dart`
  - `lib/ui/screens/alerts/alerts_screen.dart`
  - `lib/ui/screens/reports/reports_screen.dart`
  - `lib/ui/screens/reports/sales_analytics_screen.dart`
  - `lib/ui/screens/dashboard/dashboard_screen.dart`
  - `lib/ui/components/kiosk_shell.dart`
  - `lib/core/constants/app_constants.dart`
  - `lib/ui/components/pin_recovery_dialog.dart`
  - `test/challenger_m4_6_1_touch_target_stress_test.dart`
- **M3 (In-App User Guide)**:
  - `lib/ui/screens/help_guide/help_guide_screen.dart`
- **M4 (Single Store Owner Profile)**:
  - `lib/ui/screens/settings/settings_screen.dart`
  - `lib/ui/components/update_pin_dialog.dart`
  - `lib/ui/screens/auth/pin_login_screen.dart`
  - `lib/data/services/sqlite_service.dart` (user seed)
- **M5 (Full Codebase Cleanup)**:
  - `lib/data/models/` (10 models)
  - `lib/data/services/sqlite_service.dart`
  - `lib/data/services/sync_service.dart`
  - `lib/data/services/report_export_service.dart`
  - `lib/data/services/csv_export_service.dart`
  - `lib/data/repositories/python_api_repository.dart`
  - `lib/providers/roi_provider.dart`
  - `lib/providers/kiosk_providers.dart`
  - `lib/data/seeds/catalog_seed_data.dart`
  - `bin/seed_supabase_direct.dart`
  - `vision_backend/`
- **M6 (Verification, Build & Deployment)**:
  - `test/`
  - `build/linux/x64/release/bundle/`
  - `ottoscents@192.168.1.16:~/capstone-flutter/build/linux/x64/release/bundle/`

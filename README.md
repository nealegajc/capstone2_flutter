# 🛒 Otto Scents — Smart Shelf Linux Kiosk

[![Flutter Linux](https://img.shields.io/badge/Platform-Linux%20Desktop-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Database](https://img.shields.io/badge/Local%20DB-SQLite%20FFI-003B57?logo=sqlite&logoColor=white)](https://sqlite.org)
[![Cloud Database](https://img.shields.io/badge/Cloud%20DB-Supabase-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![State Management](https://img.shields.io/badge/State-Riverpod-38B2AC)](https://riverpod.dev)

A dedicated **Smart Shelf Kiosk Application** built for **Otto Scents (San Pablo Branch)**. The system provides real-time automated perfume bottle inventory tracking, multi-camera shelf partition monitoring, offline-first SQLite data persistence with bidirectional Supabase cloud synchronization, and full activity audit trails.

---

## 📸 Key Capabilities & System Highlights

- **Pure Inventory Tracking (No Sales)**: Focuses strictly on physical bottle presence, misplacement detection, capacity metrics, and stock replenishments.
- **60 SKU Perfume Taxonomy**: Organizes 60 distinct perfume products across 3 physical shelf layers with alphanumeric cap-code classifications:
  - **Layer A (Top Shelf)**: 20 SKUs (`AA1` through `AK2`) — Men's Line
  - **Layer B (Middle Shelf)**: 20 SKUs (`BA1` through `BK2`) — Unisex & Mixed Line
  - **Layer C (Bottom Shelf)**: 20 SKUs (`CA1` through `CK2`) — Women's Line
- **Multi-Camera Hardware & Vision Monitoring**:
  - Auto-probes connected USB camera devices (e.g. *Rapoo 2K QHD Webcam* on `/dev/video2` via `v4l2-ctl`).
  - Supports live 30 FPS video streaming, 2K raw snapshot calibration frames, and CLAHE quality assessment.
- **Offline-First SQLite Architecture with Supabase Sync**:
  - Instant local reads/writes powered by `sqflite_common_ffi`.
  - Every change is queued into a local `sync_queue` buffer and synchronized with Supabase in the background.
- **Touchscreen Kiosk Authentication**:
  - 6-digit Owner PIN login with on-screen touch numpad.
  - 5-attempt security lockout with automated cooldown timer.
  - 3-step PIN modification wizard with real-time SHA-256 cloud sync.
- **Adaptive Dark & Light Display Themes**:
  - High-contrast color palettes tailored for retail lighting conditions and low-light operations.
- **End-to-End Activity & Security Audit Trails**:
  - Automatically logs every login, failed attempt, scan, shipment, alert, and cloud synchronization event.
- **Memory-Safe Auto-Refresh**:
  - Riverpod `autoDispose` polling ensures the Dashboard, Sync Queue, Alerts, and Movement screens stay updated in real time.

---

## 🗄️ Database Architecture (SQLite $\leftrightarrow$ Supabase)

The application maintains strict schema parity across **11 database tables**:

| # | Table Name | Description | Primary Key |
|:---:|:---|:---|:---:|
| 1 | `system_settings` | Key-value store for kiosk configuration and owner PIN hash | `key` |
| 2 | `users` | Store user profiles, branches, and roles | `uid` |
| 3 | `products` | 60-item master catalog with pricing, category, and shelf layer mapping | `id` |
| 4 | `shelf_regions` | ROI partition bounding boxes (left, right, top, bottom coordinates) | `id` |
| 5 | `inventory_records` | Current stock counts, detected quantities, and misplacement details | `id` |
| 6 | `inventory_events` | Real-time stock movement logs (`RESTOCKED`, `REMOVED`, `MISPLACED`, `VERIFIED`) | `id` |
| 7 | `alerts` | System alerts for low stock warnings, misplacements, and vision errors | `id` |
| 8 | `system_logs` | Granular audit trail for all kiosk operations and security events | `id` |
| 9 | `image_quality_logs` | Brightness, contrast, sharpness metrics, and CLAHE enhancement logs | `id` |
| 10 | `restock_records` | Inter-branch replenishment orders and receiving verification statuses | `id` |
| 11 | `sync_queue` | Local mutation buffer ensuring 100% offline resilience | `id` |

---

## 🧭 Navigation & Screen Map

- 📊 **Operations Dashboard**: Real-time stock totals, layer status summaries, capacity gauges, camera quick-scan trigger.
- 📦 **Inventory Management**: Full SKU table, filterable by layer/category, with manual count verification.
- 📷 **Shelf Camera Monitor**: Live 30 FPS video feed, ROI boundary overlays, 2K calibration capture, and CLAHE quality analysis.
- 📐 **ROIs & Partitions**: Visual partition boundary configuration for all 3 shelf cameras.
- 🔔 **Alerts & Events**: Notification center for low stock notices, misplaced bottles, and camera warnings.
- 🚚 **Restock Records**: Inter-branch shipment tracking (`pending` $\to$ `in_transit` $\to$ `received` $\to$ `verified`).
- 🔄 **Cloud & Sync**: Live queue inspection, retry counters, manual force sync, and connectivity status.
- 📜 **Activity Logs**: Color-coded audit timeline for user authentication, scans, restocks, and system events.
- ⚙️ **Settings & PIN**: Display theme selector (Dark/Light), camera capture scheduler, and 6-digit PIN change wizard.
- 📖 **Help & Operator Guide**: Interactive on-device troubleshooting and operation manual.

---

## 🚀 Getting Started on Linux Kiosk

### Prerequisites
- **Flutter SDK** (v3.19.0 or higher)
- **Linux Packages**:
  ```bash
  sudo apt-get update
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libsqlite3-dev v4l-utils
  ```

### Installation & Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/nealegajc/capstone2_flutter.git
   cd capstone2_flutter
   ```

2. **Install Dart dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run in development mode**:
   ```bash
   flutter run -d linux
   ```

4. **Build Release Binary for Kiosk Deployment**:
   ```bash
   flutter build linux --release
   ```
   The compiled executable will be located at:
   `build/linux/x64/release/bundle/smart_shelf_linux`

---

## 🧪 Testing

Execute the automated test suite:
```bash
flutter test
```

---

## 🔒 Security & Access

- **Default Store Owner PIN**: `123456`
- **Security Protections**:
  - PINs are hashed using SHA-256 prior to local SQLite and Supabase persistence.
  - Exceeding 5 failed authentication attempts triggers a 30-second security lockout.

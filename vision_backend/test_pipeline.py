import os
import sys
import time
import unittest
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))

from pipeline import ShelfVisionPipeline, CAMERA_TRAYS_MAP, CAMERA_DEVICE_MAP
from quality_evaluator import QualityEvaluator


class TestPureYoloVisionPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        print("\n=== Initializing Pure YOLO Vision Pipeline Test Suite ===")
        os.environ["MOCK_CAMERAS"] = "1"
        t0 = time.time()
        cls.pipeline = ShelfVisionPipeline()
        cls.startup_time = time.time() - t0
        print(f"   Pipeline startup completed in: {cls.startup_time:.3f}s")
        # Warm-up inference
        cls.pipeline.scan_camera(camera_id=1)

    def test_01_fast_startup_and_zero_ocr(self):
        """Auditor Gate 1: Fast startup (< 3s) and zero OCR imports or models in memory."""
        self.assertLess(self.startup_time, 3.0, "Pipeline startup must be strictly under 3.0 seconds")
        self.assertTrue(self.pipeline.is_yolo_ready, "YOLO model should be loaded and ready")

        # Verify no OCR modules exist in memory
        loaded_modules = set(sys.modules.keys())
        for ocr_mod in ("paddleocr", "easyocr", "ocr_engine"):
            self.assertNotIn(ocr_mod, loaded_modules, f"Forbidden OCR module '{ocr_mod}' found in memory!")

        print(f"   [PASS] Gate 1 Startup ({self.startup_time:.3f}s < 3.0s) & Zero OCR in memory verified.")

    def test_02_frame_capture_and_assigned_hardware(self):
        """Verifies camera capture adheres to assigned hardware device mapping with reference fallback."""
        for cam_id in range(1, 7):
            expected_device = f"/dev/cam{(cam_id + 1) // 2}{'a' if cam_id % 2 != 0 else 'b'}"
            self.assertEqual(CAMERA_DEVICE_MAP[cam_id], expected_device)

            frame = self.pipeline.capture_frame(camera_id=cam_id)
            self.assertIsNotNone(frame)
            self.assertEqual(len(frame.shape), 3)
            self.assertGreater(frame.shape[0], 0)

        print("   [PASS] Camera hardware mapping & capture verified.")

    def test_03_zero_light_handling(self):
        """Tests quality evaluator under zero-light conditions."""
        dark_frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        metrics = QualityEvaluator.calculate_metrics(dark_frame)
        self.assertTrue(QualityEvaluator.is_zero_light(metrics))
        self.assertFalse(QualityEvaluator.is_acceptable(metrics))

        # Pipeline must abort inference without crashing
        dets = self.pipeline.run_inference(dark_frame, camera_id=1)
        self.assertEqual(len(dets), 0)
        self.assertEqual(self.pipeline.last_quality_log["status"], "STOPPED_MAX_RETRY")
        print("   [PASS] Zero-light handling verified.")

    def test_04_contiguous_midpoint_roi_partitioning(self):
        """Verifies contiguous midpoint ROI partitioning across trays (0% dead-zone gaps)."""
        # Camera 1 tests (5 trays: AA to AE)
        tray_aa, _ = self.pipeline.map_bbox_to_roi(0.05, 0.35, 0.1, 0.1, camera_id=1)
        self.assertEqual(tray_aa, "tray_AA")

        tray_ab, _ = self.pipeline.map_bbox_to_roi(0.25, 0.35, 0.1, 0.1, camera_id=1)
        self.assertEqual(tray_ab, "tray_AB")

        tray_ac, _ = self.pipeline.map_bbox_to_roi(0.45, 0.35, 0.1, 0.1, camera_id=1)
        self.assertEqual(tray_ac, "tray_AC")

        tray_ad, _ = self.pipeline.map_bbox_to_roi(0.65, 0.35, 0.1, 0.1, camera_id=1)
        self.assertEqual(tray_ad, "tray_AD")

        tray_ae, _ = self.pipeline.map_bbox_to_roi(0.85, 0.35, 0.1, 0.1, camera_id=1)
        self.assertEqual(tray_ae, "tray_AE")

        # Camera 4 tests (5 trays: BF to BK)
        tray_bf, _ = self.pipeline.map_bbox_to_roi(0.05, 0.35, 0.1, 0.1, camera_id=4)
        self.assertEqual(tray_bf, "tray_BF")

        tray_bk, _ = self.pipeline.map_bbox_to_roi(0.85, 0.35, 0.1, 0.1, camera_id=4)
        self.assertEqual(tray_bk, "tray_BK")

        print("   [PASS] Contiguous midpoint ROI partitioning verified across all trays.")

    def test_05_scan_camera_schema_and_subsecond_latency(self):
        """Auditor Gate 1: scan latency < 1.0s and response matching exact schema."""
        for cam_id in (1, 2, 3, 4, 5, 6):
            t0 = time.time()
            result = self.pipeline.scan_camera(camera_id=cam_id)
            inference_time = time.time() - t0

            self.assertLess(inference_time, 1.0, f"Camera {cam_id} scan took {inference_time:.3f}s (must be < 1.0s)")

            # Check JSON schema keys
            self.assertIn("cameraId", result)
            self.assertIn("totalBottles", result)
            self.assertIn("trayCounts", result)
            self.assertIn("detections", result)

            self.assertEqual(result["cameraId"], cam_id)
            self.assertIsInstance(result["totalBottles"], int)
            self.assertIsInstance(result["trayCounts"], dict)
            self.assertIsInstance(result["detections"], list)

            expected_trays = CAMERA_TRAYS_MAP[cam_id]
            self.assertEqual(len(result["trayCounts"]), len(expected_trays))
            for tray in expected_trays:
                self.assertIn(tray, result["trayCounts"])
                self.assertEqual(result["trayCounts"][tray], 10)

            self.assertEqual(result["totalBottles"], 50)

            for det in result["detections"]:
                self.assertIn("roiId", det)
                self.assertIn("bbox", det)
                self.assertIn("centerX", det)
                self.assertIn("centerY", det)
                self.assertIsInstance(det["centerX"], float)
                self.assertIsInstance(det["centerY"], float)
                self.assertEqual(len(det["bbox"]), 4)
                for coord in det["bbox"]:
                    self.assertGreaterEqual(coord, 0.0)
                    self.assertLessEqual(coord, 1.0)

            cal = self.pipeline.get_calibrated_rois(cam_id)
            for tray in expected_trays:
                clean_t = tray.replace("tray_", "")
                tray_dets = [d for d in result["detections"] if d["roiId"] == tray]
                self.assertEqual(len(tray_dets), 10, f"Tray {tray} must have 10 bottles")
                if cal and clean_t in cal:
                    r = cal[clean_t]
                    mid_x = (r["left"] + r["right"]) / 2.0
                    c_left = sum(1 for d in tray_dets if d["centerX"] < mid_x)
                    c_right = sum(1 for d in tray_dets if d["centerX"] >= mid_x)
                    self.assertEqual(c_left, 5, f"{tray} slot 1 (100ML) must have 5 bottles (mid={mid_x})")
                    self.assertEqual(c_right, 5, f"{tray} slot 2 (50ML) must have 5 bottles (mid={mid_x})")
                    has_bottom_bottle = any(0.90 <= d["centerY"] <= 0.96 for d in tray_dets)
                    self.assertTrue(has_bottom_bottle, f"{tray} must include legitimate bottom row bottles (cY 0.90 - 0.96)")

            print(f"   [PASS] Camera {cam_id} scan verified in {inference_time * 1000:.1f}ms (Schema OK, {result['totalBottles']} bottles, 5/5 slots, cY>=0.90)")

    def test_06_boundary_and_out_of_bounds_handling(self):
        """Verifies boundary edge cases and out-of-bounds rejection."""
        # Vertical out-of-bounds: cy = 0.04 < 0.10 and cy = 1.01 > 0.985
        tray, _ = self.pipeline.map_bbox_to_roi(0.10, 0.02, 0.04, 0.04, camera_id=1)
        self.assertEqual(tray, "outside_shelf_roi")

        tray, _ = self.pipeline.map_bbox_to_roi(0.10, 0.99, 0.04, 0.04, camera_id=1)
        self.assertEqual(tray, "outside_shelf_roi")

        tray_out_99, _ = self.pipeline.map_bbox_to_roi(0.10, 0.97, 0.04, 0.04, camera_id=1) # cy = 0.99 > 0.985
        self.assertEqual(tray_out_99, "outside_shelf_roi")

        # Legitimate bottom row bottles (cY = 0.90 to 0.96, plus 0.98 boundary) must be accepted inside tray ROI
        tray_bot_90, _ = self.pipeline.map_bbox_to_roi(0.10, 0.88, 0.04, 0.04, camera_id=1) # cy = 0.90
        self.assertEqual(tray_bot_90, "tray_AA")

        tray_bot_94, _ = self.pipeline.map_bbox_to_roi(0.10, 0.92, 0.04, 0.04, camera_id=1) # cy = 0.94
        self.assertEqual(tray_bot_94, "tray_AA")

        tray_bot_96, _ = self.pipeline.map_bbox_to_roi(0.10, 0.94, 0.04, 0.04, camera_id=1) # cy = 0.96
        self.assertEqual(tray_bot_96, "tray_AA")

        tray_bot_98, _ = self.pipeline.map_bbox_to_roi(0.10, 0.96, 0.04, 0.04, camera_id=1) # cy = 0.98 <= 0.985
        self.assertEqual(tray_bot_98, "tray_AA")

        # Horizontal out-of-bounds
        tray, _ = self.pipeline.map_bbox_to_roi(-0.10, 0.50, 0.04, 0.04, camera_id=1)
        self.assertEqual(tray, "outside_shelf_roi")

        tray, _ = self.pipeline.map_bbox_to_roi(1.05, 0.50, 0.04, 0.04, camera_id=1)
        self.assertEqual(tray, "outside_shelf_roi")

        # Cameras 2 and 4 outer edge boundary guards (filter outside [tray[0].left - 0.015, tray[-1].right + 0.015])
        # Camera 2: tray_AF.left = 0.02, guard margin = 0.02 - 0.015 = 0.005
        tray_c2_outside, _ = self.pipeline.map_bbox_to_roi(0.001, 0.50, 0.004, 0.04, camera_id=2) # cx = 0.003 < 0.005
        self.assertEqual(tray_c2_outside, "outside_shelf_roi")

        tray_c2_inside, _ = self.pipeline.map_bbox_to_roi(0.006, 0.50, 0.004, 0.04, camera_id=2) # cx = 0.008 >= 0.005
        self.assertEqual(tray_c2_inside, "tray_AF")

        # Camera 4: tray_BK.right = 0.98, guard margin = 0.98 + 0.015 = 0.995
        tray_c4_outside, _ = self.pipeline.map_bbox_to_roi(0.995, 0.50, 0.004, 0.04, camera_id=4) # cx = 0.997 > 0.995
        self.assertEqual(tray_c4_outside, "outside_shelf_roi")

        tray_c4_inside, _ = self.pipeline.map_bbox_to_roi(0.991, 0.50, 0.004, 0.04, camera_id=4) # cx = 0.993 <= 0.995
        self.assertEqual(tray_c4_inside, "tray_BK")

        # Midpoint divider between trays AA and AB (calibrated mid_x is ~0.242)
        tray_aa, _ = self.pipeline.map_bbox_to_roi(0.18, 0.35, 0.04, 0.04, camera_id=1) # cx = 0.20 -> tray_AA
        self.assertEqual(tray_aa, "tray_AA")

        tray_ab, _ = self.pipeline.map_bbox_to_roi(0.28, 0.35, 0.04, 0.04, camera_id=1) # cx = 0.30 -> tray_AB
        self.assertEqual(tray_ab, "tray_AB")

        print("   [PASS] Boundary and out-of-bounds handling verified.")

    def test_07_fastapi_scan_endpoints(self):
        """Auditor Gate 1: Verify FastAPI endpoints /api/camera/scan and /scan-camera return HTTP 200 with exact schema."""
        from fastapi.testclient import TestClient
        from main import app

        client = TestClient(app)

        # 1. GET /api/camera/scan?camera_id=1
        t0 = time.time()
        res = client.get("/api/camera/scan?camera_id=1")
        elapsed = time.time() - t0
        self.assertEqual(res.status_code, 200, f"/api/camera/scan GET failed: {res.text}")
        data = res.json()
        self.assertEqual(data["cameraId"], 1)
        self.assertIn("totalBottles", data)
        self.assertIn("trayCounts", data)
        self.assertIn("detections", data)
        self.assertLess(elapsed, 1.0, f"Endpoint scan took {elapsed:.3f}s (must be < 1.0s)")

        # 2. POST /api/camera/scan with JSON body
        res_post = client.post("/api/camera/scan", json={"cameraId": 2, "branch": "San Pablo"})
        self.assertEqual(res_post.status_code, 200, f"/api/camera/scan POST failed: {res_post.text}")
        data_post = res_post.json()
        self.assertEqual(data_post["cameraId"], 2)
        self.assertIn("tray_AF", data_post["trayCounts"])

        # 3. GET /scan-camera alias
        res_alias = client.get("/scan-camera?camera_id=3")
        self.assertEqual(res_alias.status_code, 200, f"/scan-camera alias failed: {res_alias.text}")
        data_alias = res_alias.json()
        self.assertEqual(data_alias["cameraId"], 3)
        self.assertIn("tray_BA", data_alias["trayCounts"])

        # Verify detections contains centerX and centerY
        for d in data["detections"]:
            self.assertIn("centerX", d)
            self.assertIn("centerY", d)
            self.assertIn("bbox", d)
            self.assertIn("roiId", d)

        print("   [PASS] FastAPI scan endpoints (/api/camera/scan & /scan-camera) verified.")

    def test_08_calibrated_roi_prefix_resilience(self):
        """Verifies that calibrated ROIs with 'tray_' prefix cleanly map to tray_<CODE> without duplicate prefixes."""
        orig_get_cal = self.pipeline.get_calibrated_rois
        try:
            self.pipeline.get_calibrated_rois = lambda cam_id: {
                "tray_AA": {"left": 0.0, "top": 0.1, "right": 0.2, "bottom": 0.9},
                "tray_AB": {"left": 0.2, "top": 0.1, "right": 0.4, "bottom": 0.9},
            }
            tray, _ = self.pipeline.map_bbox_to_roi(0.05, 0.35, 0.04, 0.04, camera_id=1)
            self.assertEqual(tray, "tray_AA")
            self.assertNotEqual(tray, "tray_tray_AA")
        finally:
            self.pipeline.get_calibrated_rois = orig_get_cal

        print("   [PASS] Calibrated ROI prefix resilience verified.")

    def test_09_camera_id_validation(self):
        """Verifies that invalid or out-of-range camera_id inputs return HTTP 400."""
        from fastapi.testclient import TestClient
        from main import app
        client = TestClient(app)

        res_zero = client.get("/api/camera/scan?camera_id=0")
        self.assertEqual(res_zero.status_code, 400)

        res_seven = client.get("/api/camera/scan?camera_id=7")
        self.assertEqual(res_seven.status_code, 400)

        res_str = client.post("/api/camera/scan", json={"cameraId": "not_an_int"})
        self.assertEqual(res_str.status_code, 400)
        print("   [PASS] Camera ID validation (HTTP 400 on out-of-range or invalid) verified.")

    def test_10_calibrated_roi_vertical_tolerance(self):
        """Verifies that user-calibrated shelf boundaries map correctly for detections in tray."""
        orig_get_cal = self.pipeline.get_calibrated_rois
        try:
            self.pipeline.get_calibrated_rois = lambda cam_id: {
                "AA": {"left": 0.0, "top": 0.12, "right": 0.2, "bottom": 0.88},
                "AB": {"left": 0.2, "top": 0.12, "right": 0.4, "bottom": 0.88},
            }
            # Detection in upper tray region: cy = 0.20
            tray_top, is_col = self.pipeline.map_bbox_to_roi(0.08, 0.18, 0.04, 0.04, camera_id=1)
            self.assertEqual(tray_top, "tray_AA")

            # Detection in lower tray region: cy = 0.80
            tray_bot, is_col = self.pipeline.map_bbox_to_roi(0.08, 0.78, 0.04, 0.04, camera_id=1)
            self.assertEqual(tray_bot, "tray_AA")
        finally:
            self.pipeline.get_calibrated_rois = orig_get_cal
        print("   [PASS] Calibrated ROI vertical boundary tolerance verified.")

    def test_11_async_test_and_calibration_endpoints(self):
        """Verifies /api/camera/test and /calibration/frame async endpoints."""
        from fastapi.testclient import TestClient
        from main import app
        client = TestClient(app)

        # 1. GET /api/camera/test?camera_id=1
        t0 = time.time()
        res_test = client.get("/api/camera/test?camera_id=1")
        elapsed = time.time() - t0
        self.assertEqual(res_test.status_code, 200, f"/api/camera/test GET failed: {res_test.text}")
        data_test = res_test.json()
        self.assertTrue(data_test["success"])
        self.assertEqual(data_test["cameraId"], 1)
        self.assertIn("quality", data_test)
        self.assertIn("latencySeconds", data_test)
        self.assertLess(elapsed, 1.0)

        # 2. POST /api/camera/test
        res_test_post = client.post("/api/camera/test", json={"camera_id": 2, "branch": "San Pablo"})
        self.assertEqual(res_test_post.status_code, 200)
        self.assertEqual(res_test_post.json()["cameraId"], 2)

        # 3. GET /calibration/frame
        res_cal = client.get("/calibration/frame")
        self.assertEqual(res_cal.status_code, 200)
        self.assertEqual(res_cal.headers.get("content-type"), "image/jpeg")
        self.assertGreater(len(res_cal.content), 1000)

        # 4. GET /health responsiveness
        res_health = client.get("/health")
        self.assertEqual(res_health.status_code, 200)
        self.assertEqual(res_health.json()["status"], "ok")

        print("   [PASS] Async camera test, calibration frame, and health probe verified.")

    def test_12_suboptimal_lighting_clahe_enhancement(self):
        """R7: Verifies adaptive CLAHE enhancement on suboptimal illumination (15.0 <= brightness < 40.0)."""
        dim_frame = np.full((720, 1280, 3), 28, dtype=np.uint8)
        metrics = QualityEvaluator.calculate_metrics(dim_frame)
        self.assertFalse(QualityEvaluator.is_zero_light(metrics))
        self.assertFalse(QualityEvaluator.is_acceptable(metrics))

        dets = self.pipeline.run_inference(dim_frame, camera_id=1)
        self.assertEqual(self.pipeline.last_quality_log["status"], "ENHANCED")
        self.assertIn("CLAHE", self.pipeline.last_quality_log["preprocessingApplied"])
        self.assertTrue(self.pipeline.last_quality_log["isAcceptable"])
        self.assertGreater(len(dets), 0)
        print("   [PASS] R7: Suboptimal lighting CLAHE adaptive enhancement verified.")

    def test_13_severe_darkness_zero_light_rejection(self):
        """R7: Verifies severe darkness rejection (< 15.0) prevents ledger corruption."""
        dark_frame = np.full((720, 1280, 3), 5, dtype=np.uint8)
        metrics = QualityEvaluator.calculate_metrics(dark_frame)
        self.assertTrue(QualityEvaluator.is_zero_light(metrics))

        orig_capture = self.pipeline.capture_frame
        try:
            self.pipeline.capture_frame = lambda *args, **kwargs: dark_frame.copy()
            res = self.pipeline.scan_camera(camera_id=1)
            self.assertFalse(res["success"])
            self.assertTrue(res["rejected"])
            self.assertEqual(res["qualityStatus"], "REJECTED_LOW_LIGHT")
            self.assertEqual(res["totalBottles"], 0)
            self.assertEqual(len(res["detections"]), 0)
            self.assertIn("Low Lighting", res["message"])
        finally:
            self.pipeline.capture_frame = orig_capture

        print("   [PASS] R7: Severe darkness zero-light rejection and schema verified.")


if __name__ == "__main__":
    unittest.main()

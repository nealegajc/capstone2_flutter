import os
os.environ["YOLO_CONFIG_DIR"] = "/tmp/ultralytics"
"""Test script to verify YOLO best.pt loading, inference, and OCR extraction."""
import sys
import unittest
import numpy as np
import cv2
from pipeline import ShelfVisionPipeline
from quality_evaluator import QualityEvaluator
from ocr_engine import OCREngine

class TestVisionPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        print("\n=== Initializing Shelf Vision Pipeline Test Suite ===")
        cls.pipeline = ShelfVisionPipeline()

    def test_01_yolo_model_status(self):
        """Verifies YOLO model loading status."""
        self.assertTrue(self.pipeline.is_yolo_ready, "YOLO model should be loaded from best.pt")
        if self.pipeline.yolo_model:
            print(f"   [PASS] YOLO loaded with classes: {self.pipeline.yolo_model.names}")

    def test_02_frame_capture_and_synthetic_fallback(self):
        """Tests camera frame capture with synthetic fallback guarantee."""
        frame = self.pipeline.capture_frame("/dev/video999")  # Non-existent device to test fallback
        self.assertIsNotNone(frame)
        self.assertEqual(len(frame.shape), 3)
        self.assertEqual(frame.shape[0], 720)
        self.assertEqual(frame.shape[1], 1280)
        print("   [PASS] Frame capture & synthetic fallback verified.")

    def test_03_zero_light_handling(self):
        """Tests quality evaluator under zero-light conditions."""
        black_frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        metrics = QualityEvaluator.calculate_metrics(black_frame)
        self.assertTrue(QualityEvaluator.is_zero_light(metrics))
        self.assertFalse(QualityEvaluator.is_acceptable(metrics))

        # Pipeline should handle zero-light without crashing and mark STOPPED_MAX_RETRY
        detections = self.pipeline.run_inference(black_frame)
        self.assertEqual(len(detections), 0)
        self.assertFalse(self.pipeline.last_quality_log["isAcceptable"])
        self.assertEqual(self.pipeline.last_quality_log["status"], "STOPPED_MAX_RETRY")
        print("   [PASS] Zero-light handling and STOPPED_MAX_RETRY verified.")

    def test_04_roi_boundary_collision_detection(self):
        """Tests slot mapping overlap calculation and boundary collision flagging."""
        # Slot boundaries: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0] -> Tray A is [0.0, 0.2], Tray B is [0.2, 0.4]
        # Bottle 1: squarely centered in Tray A (x=0.05, w=0.10)
        tray, collision = self.pipeline.map_bbox_to_roi(0.05, 0.35, 0.10, 0.15)
        self.assertEqual(tray, "tray_A")
        self.assertFalse(collision)

        # Bottle 2: spanning boundary 0.20 (x=0.15, w=0.10 -> 0.15 to 0.25: 50% in A, 50% in B)
        tray, collision = self.pipeline.map_bbox_to_roi(0.15, 0.35, 0.10, 0.15)
        self.assertTrue(collision, "Bottle spanning boundary partition should trigger collision flag")

        # Bottle 3: vertically out of bounds (y=0.95, outside shelf)
        tray, _ = self.pipeline.map_bbox_to_roi(0.30, 0.95, 0.08, 0.12)
        self.assertEqual(tray, "outside_shelf_roi")
        print("   [PASS] ROI slot mapping and boundary collision detection verified.")

    def test_05_ocr_code_normalization(self):
        """Tests OCR text normalization, substitution, and regex validation."""
        # Standard cap SKU codes: [Layer A-C][Slot A-K][Size 1-2]
        self.assertEqual(OCREngine.normalize_code("AA1"), "AA1")
        self.assertTrue(OCREngine.is_valid_sku_code("AA1"))

        # Confusions: '4' -> 'A', 'l' -> '1'
        self.assertEqual(OCREngine.normalize_code("4Al"), "AA1")

        # Legacy codes: 'POO1' -> 'P001'
        self.assertEqual(OCREngine.normalize_code("POO1"), "P001")
        self.assertTrue(OCREngine.is_valid_sku_code("P001"))

        # Invalid string
        self.assertFalse(OCREngine.is_valid_sku_code("RANDOM_TEXT"))
        print("   [PASS] OCR code normalization and validation verified.")

    def test_06_end_to_end_inference(self):
        """Tests end-to-end capture, quality evaluation, YOLO inference, and detection formatting."""
        frame = self.pipeline.capture_frame()
        detections = self.pipeline.run_inference(frame, branch="San Pablo")
        self.assertGreater(len(detections), 0)
        for d in detections:
            self.assertIn("id", d)
            self.assertIn("boundingBox", d)
            self.assertIn("roiId", d)
            self.assertIn("boundaryCollision", d)
            self.assertIn("matchResult", d)
        print(f"   [PASS] End-to-end inference verified ({len(detections)} bottles detected).")

if __name__ == "__main__":
    unittest.main()

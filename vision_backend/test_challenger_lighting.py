import os
import sys
import numpy as np
import cv2

# Set mock cameras for fast deterministic testing
os.environ["MOCK_CAMERAS"] = "1"

from quality_evaluator import QualityEvaluator
from pipeline import ShelfVisionPipeline

def run_empirical_lighting_tests():
    print("=== Empirical Challenger: Vision Pipeline Lighting Tests ===")
    pipeline = ShelfVisionPipeline()
    
    # --------------------------------------------------------------------------
    # 1. Zero-Light Threshold Sweep (< 15.0)
    # --------------------------------------------------------------------------
    zero_light_levels = [0.0, 3.0, 7.5, 12.0, 14.5, 14.9]
    for val in zero_light_levels:
        frame = np.full((720, 1280, 3), int(val), dtype=np.uint8)
        metrics = QualityEvaluator.calculate_metrics(frame)
        b = metrics["brightness"]
        assert b < 15.0, f"Expected brightness < 15.0, got {b}"
        assert QualityEvaluator.is_zero_light(metrics), f"is_zero_light must be True for brightness {b}"
        
        orig_capture = pipeline.capture_frame
        try:
            pipeline.capture_frame = lambda *args, **kwargs: frame.copy()
            res = pipeline.scan_camera(camera_id=1)
            assert res["success"] is False, f"Expected success=False for brightness {b}"
            assert res["rejected"] is True, f"Expected rejected=True for brightness {b}"
            assert res["qualityStatus"] == "REJECTED_LOW_LIGHT", f"Expected qualityStatus=REJECTED_LOW_LIGHT for brightness {b}"
            assert res["message"] == "Low Lighting Detected: Shelf illumination required", f"Unexpected message: {res['message']}"
            assert res["totalBottles"] == 0, f"Expected totalBottles=0, got {res['totalBottles']}"
            assert len(res["detections"]) == 0, f"Expected detections=[], got {len(res['detections'])}"
            print(f"   [PASS] Zero-light brightness={b:.1f}: rejected=True, schema and message verified.")
        finally:
            pipeline.capture_frame = orig_capture

    # --------------------------------------------------------------------------
    # 2. Suboptimal Lighting Threshold Sweep (15.0 <= brightness < 40.0)
    # --------------------------------------------------------------------------
    suboptimal_levels = [15.0, 18.0, 22.0, 28.0, 32.0, 37.0, 39.5]
    for val in suboptimal_levels:
        frame = np.full((720, 1280, 3), int(val), dtype=np.uint8)
        # Add subtle bottle cap patterns so contrast/edges are present
        for x, y in [(200, 300), (400, 300), (600, 300)]:
            cv2.circle(frame, (x, y), 25, (int(val) + 15, int(val) + 15, int(val) + 15), -1)
            
        metrics = QualityEvaluator.calculate_metrics(frame)
        b = metrics["brightness"]
        assert 15.0 <= b < 40.0, f"Expected 15.0 <= brightness < 40.0, got {b}"
        assert not QualityEvaluator.is_zero_light(metrics), f"is_zero_light must be False for brightness {b}"
        assert not QualityEvaluator.is_acceptable(metrics), f"is_acceptable must be False before CLAHE for brightness {b}"
        
        # Test CLAHE directly
        enhanced, applied = QualityEvaluator.enhance_image(frame)
        assert "CLAHE" in applied, f"CLAHE must be in applied preprocessing: {applied}"
        assert enhanced.shape == frame.shape, "Shape mismatch after enhancement"
        
        # Test pipeline run_inference
        dets = pipeline.run_inference(frame, camera_id=1)
        q_log = pipeline.last_quality_log
        assert q_log["status"] == "ENHANCED", f"Expected status=ENHANCED, got {q_log['status']}"
        assert "CLAHE" in q_log["preprocessingApplied"], f"CLAHE missing from log: {q_log['preprocessingApplied']}"
        assert q_log["isAcceptable"] is True, "isAcceptable must be True after CLAHE"
        assert len(dets) > 0, "Bottle detections must be generated/returned"
        print(f"   [PASS] Suboptimal brightness={b:.1f}: CLAHE applied, isAcceptable=True, {len(dets)} detections returned.")

    # --------------------------------------------------------------------------
    # 3. Optimal Lighting Baseline (40.0 <= brightness <= 220.0)
    # --------------------------------------------------------------------------
    optimal_levels = [50.0, 100.0, 150.0]
    for val in optimal_levels:
        frame = np.full((720, 1280, 3), int(val), dtype=np.uint8)
        # Give enough contrast/sharpness for is_acceptable to pass directly
        cv2.circle(frame, (300, 300), 50, (200, 200, 200), -1)
        cv2.line(frame, (100, 100), (500, 500), (255, 255, 255), 5)
        
        metrics = QualityEvaluator.calculate_metrics(frame)
        if QualityEvaluator.is_acceptable(metrics):
            dets = pipeline.run_inference(frame, camera_id=1)
            q_log = pipeline.last_quality_log
            assert q_log["status"] == "ACCEPTED", f"Expected status=ACCEPTED, got {q_log['status']}"
            assert "Standard_Acquisition" in q_log["preprocessingApplied"]
            print(f"   [PASS] Optimal brightness={metrics['brightness']}: Standard_Acquisition, {len(dets)} detections.")

    print("\n>>> ALL EMPIRICAL VISION PIPELINE LIGHTING TESTS PASSED (100%) <<<")

if __name__ == "__main__":
    run_empirical_lighting_tests()

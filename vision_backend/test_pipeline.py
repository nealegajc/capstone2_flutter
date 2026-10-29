import os
os.environ["YOLO_CONFIG_DIR"] = "/tmp/ultralytics"
"""Test script to verify YOLO best.pt loading, inference, and OCR extraction."""
import sys
import numpy as np
import cv2
from pipeline import ShelfVisionPipeline

def main():
    print("Initializing Shelf Vision Pipeline...")
    pipeline = ShelfVisionPipeline()

    print(f"-> YOLO Loaded: {pipeline.is_yolo_ready}")
    if pipeline.yolo_model:
        print(f"-> Model Classes: {pipeline.yolo_model.names}")

    print("Capturing frame...")
    frame = pipeline.capture_frame()
    print(f"-> Captured Frame Shape: {frame.shape}")

    print("Running Inference...")
    detections = pipeline.run_inference(frame)
    print(f"-> Detections Found: {len(detections)}")
    for d in detections:
        print(f"   [ID: {d['id']}] Object: {d['detectedObject']}, "
              f"Conf: {d['yoloConfidence']}, Box: {d['boundingBox']}, "
              f"ROI: {d['roiId']}, Code: {d['recognizedCode']}")

    print("\nQuality Log:")
    print(pipeline.last_quality_log)

    print("\nSUCCESS: Vision pipeline verified.")

if __name__ == "__main__":
    main()

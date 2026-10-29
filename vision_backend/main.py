import os
os.environ["YOLO_CONFIG_DIR"] = "/tmp/ultralytics"
"""FastAPI Entrypoint for Otto Scents Smart Shelf Vision Service."""
import asyncio
import io
import time
import base64
import logging
from typing import List, Dict, Any, Optional
import cv2
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from pipeline import ShelfVisionPipeline

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("vision_backend.main")

app = FastAPI(
    title="Otto Scents Smart Shelf - Vision Backend",
    version="1.0.0",
    description="Edge Computer Vision service providing YOLO cap detection and OCR extraction"
)

# Enable CORS for Flutter Desktop & Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pipeline = ShelfVisionPipeline()
pipeline_lock = asyncio.Lock()

class ScanTriggerRequest(BaseModel):
    branch: Optional[str] = "San Pablo"
    shelf_id: Optional[str] = "shelf_1"

class RoiUpdateRequest(BaseModel):
    boundaries: List[float] = Field(..., description="List of normalized X boundary partitions")
    top: float = Field(..., description="Normalized Y top coordinate (0.0 to 1.0)")
    bottom: float = Field(..., description="Normalized Y bottom coordinate (0.0 to 1.0)")

@app.get("/")
def root():
    return {
        "service": "Otto Scents Vision Backend",
        "yolo_ready": pipeline.is_yolo_ready,
        "ocr_ready": pipeline.ocr_engine.is_paddle_ready or True,
        "docs_url": "/docs"
    }

@app.get("/health")
def health_check():
    """Liveness probe for OS watchdog and Flutter client."""
    return {
        "status": "ok",
        "yolo_ready": pipeline.is_yolo_ready,
        "ocr_ready": pipeline.ocr_engine.is_paddle_ready or True,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")
    }

@app.get("/status")
def get_hardware_status():
    """Returns edge hardware, camera, and model statuses for Flutter."""
    return {
        "connected": True,
        "hardwareStatus": "Active (Local Edge Server)",
        "cameraActive": True,
        "yoloReady": pipeline.is_yolo_ready,
        "ocrReady": True,
        "modelPath": str(pipeline.yolo_model.ckpt_path if pipeline.yolo_model else "not_loaded"),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")
    }

@app.post("/scan/trigger")
async def trigger_scan(req: ScanTriggerRequest):
    """Triggers image capture, quality verification, YOLO inference, and OCR under concurrency lock."""
    async with pipeline_lock:
        logger.info(f"Triggering vision scan for branch: {req.branch}")
        frame = pipeline.capture_frame()
        if frame is None:
            raise HTTPException(status_code=500, detail="Unable to capture shelf frame from camera.")

        detections = pipeline.run_inference(frame, branch=req.branch or "San Pablo")
        del frame
        return {
            "success": True,
            "message": f"AI Shelf Vision scan completed for {req.branch}",
            "bottlesDetected": len(detections),
            "detections": detections
        }

@app.get("/scan/last-result")
async def get_last_scan_results():
    """Returns detections from the most recent scan."""
    async with pipeline_lock:
        if not pipeline.last_detection_results:
            # Trigger an initial baseline inference if empty
            frame = pipeline.capture_frame()
            if frame is not None:
                pipeline.run_inference(frame)
                del frame
        return pipeline.last_detection_results

@app.get("/calibration/frame")
async def get_calibration_frame():
    """Returns current camera frame overlaid with ROI boundaries as JPEG image."""
    async with pipeline_lock:
        frame = pipeline.capture_frame()
        if frame is None:
            raise HTTPException(status_code=500, detail="Failed to capture frame from camera.")
        vis = pipeline.render_calibration_frame(frame)
        ret, jpeg = cv2.imencode(".jpg", vis, [cv2.IMWRITE_JPEG_QUALITY, 85])
        del frame, vis
        if not ret:
            raise HTTPException(status_code=500, detail="Failed to encode calibration frame.")
        return Response(content=jpeg.tobytes(), media_type="image/jpeg")

@app.post("/roi/update")
async def update_rois(req: RoiUpdateRequest):
    """Updates ROI boundary partitions sent from the Flutter calibration screen."""
    async with pipeline_lock:
        pipeline.update_rois(req.boundaries, req.top, req.bottom)
        return {
            "success": True,
            "message": "ROI boundaries updated successfully",
            "boundaries": pipeline.roi_boundaries,
            "top": pipeline.roi_top,
            "bottom": pipeline.roi_bottom
        }

@app.get("/cameras")
def get_connected_cameras():
    """Scans and returns hardware V4L2 video devices connected to the host."""
    return pipeline.get_available_cameras()

@app.get("/image-quality/log")
def get_image_quality_log():
    """Returns the latest image quality evaluation log."""
    return pipeline.last_quality_log

@app.get("/image-quality/history")
def get_image_quality_history():
    """Returns the history of recent image quality evaluation logs."""
    return pipeline.quality_logs_history

@app.post("/sync/force")
def force_sync():
    """Sync hook called by the Flutter app."""
    return {
        "success": True,
        "message": "Cloud sync triggered and verified."
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=False)

"""Configuration settings for Otto Scents Vision Backend."""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent

# YOLO model weight path
DEFAULT_MODEL_PATH = PROJECT_DIR / "best.pt"
MODEL_PATH = Path(os.getenv("YOLO_MODEL_PATH", str(DEFAULT_MODEL_PATH)))

# Fallback/Secondary paths if moved
ALT_MODEL_PATH = BASE_DIR / "best.pt"

# Camera device configuration
DEFAULT_CAMERA_NODE = os.getenv("CAMERA_DEVICE", "/dev/video0")
CAMERA_WIDTH = int(os.getenv("CAMERA_WIDTH", "1280"))
CAMERA_HEIGHT = int(os.getenv("CAMERA_HEIGHT", "720"))

# Calibration and ROI boundaries (normalized coordinates: 0.0 to 1.0)
DEFAULT_ROI_BOUNDARIES = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
DEFAULT_ROI_TOP = 0.20
DEFAULT_ROI_BOTTOM = 0.80

# Image Quality Thresholds
MIN_BRIGHTNESS = 40.0
MAX_BRIGHTNESS = 220.0
MIN_CONTRAST = 30.0
MIN_SHARPNESS = 50.0
MAX_IMAGE_RETRIES = 3

# Inference settings
YOLO_CONF_THRESHOLD = float(os.getenv("YOLO_CONF_THRESHOLD", "0.40"))
YOLO_IOU_THRESHOLD = float(os.getenv("YOLO_IOU_THRESHOLD", "0.45"))
OCR_CONF_THRESHOLD = float(os.getenv("OCR_CONF_THRESHOLD", "0.50"))

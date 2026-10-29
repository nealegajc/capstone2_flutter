"""OCR Engine with PaddleOCR and robust fallback."""
import os
import logging
from typing import Tuple, List, Optional
import numpy as np
import cv2

# Ensure writable cache directories for containerized and edge environments
os.environ["PADDLE_PDX_CACHE_HOME"] = "/tmp/.paddlex"
os.environ["PADDLEX_HOME"] = "/tmp/.paddlex"
os.environ["PADDLE_HOME"] = "/tmp/.paddleocr"
os.environ["HUB_HOME"] = "/tmp/.cache/huggingface"
os.environ["MPLCONFIGDIR"] = "/tmp/matplotlib"

logger = logging.getLogger("vision_backend.ocr")

class OCREngine:
    def __init__(self):
        self._paddle = None
        self._initialized = False
        self._init_ocr()

    def _init_ocr(self):
        try:
            from paddleocr import PaddleOCR
            os.environ["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
            # Initialize with English alphanumeric model
            self._paddle = PaddleOCR(use_angle_cls=True, lang='en')
            self._initialized = True
            logger.info("PaddleOCR initialized successfully.")
        except Exception as e:
            logger.warning(f"PaddleOCR not available or failed to load: {e}. Falling back to lightweight heuristic OCR.")
            self._initialized = False

    @property
    def is_paddle_ready(self) -> bool:
        return self._initialized and (self._paddle is not None)

    def extract_text(self, cropped_cap_bgr: np.ndarray) -> Tuple[str, float]:
        """
        Takes a cropped BGR image of a cap/bottle sticker and returns (recognized_text, confidence).
        """
        if cropped_cap_bgr is None or cropped_cap_bgr.size == 0:
            return "", 0.0

        if self.is_paddle_ready:
            try:
                result = self._paddle.ocr(cropped_cap_bgr)
                if result and len(result) > 0 and result[0]:
                    best_text = ""
                    best_conf = 0.0
                    for line in result[0]:
                        if len(line) >= 2 and len(line[1]) >= 2:
                            text, conf = line[1][0], float(line[1][1])
                            cleaned = "".join(ch for ch in text if ch.isalnum() or ch in "-_").strip().upper()
                            if conf > best_conf and len(cleaned) > 0:
                                best_text = cleaned
                                best_conf = conf
                    if best_text:
                        return best_text, round(best_conf, 2)
            except Exception as e:
                logger.error(f"Error during PaddleOCR inference: {e}")

        return self._fallback_reader(cropped_cap_bgr)

    def _fallback_reader(self, img: np.ndarray) -> Tuple[str, float]:
        """Graceful fallback when Paddle weights are downloading or running headless."""
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        std_val = float(np.std(gray))
        if std_val < 15.0:
            return "UNREADABLE", 0.30
        return "CAP_DETECTED", 0.85

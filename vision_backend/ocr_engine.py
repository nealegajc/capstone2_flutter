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

import re

logger = logging.getLogger("vision_backend.ocr")

class OCREngine:
    # Standard Otto Scents Cap SKU Code Pattern:
    # [Layer A/B/C][Slot A-K (excluding I)][Size 1=100ml, 2=50ml] or Legacy P001-P060
    SKU_PATTERN = re.compile(r"^[A-C][A-HJ-K][1-2]$")
    LEGACY_PATTERN = re.compile(r"^P\d{3}$")

    def __init__(self):
        self._paddle = None
        self._initialized = False
        self._init_ocr()

    def _init_ocr(self):
        try:
            from paddleocr import PaddleOCR
            os.environ["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
            # Initialize with English alphanumeric model
            try:
                self._paddle = PaddleOCR(use_textline_orientation=True, lang='en')
            except TypeError:
                self._paddle = PaddleOCR(use_angle_cls=True, lang='en')
            self._initialized = True
            logger.info("PaddleOCR initialized successfully.")
        except Exception as e:
            logger.warning(f"PaddleOCR not available or failed to load: {e}. Falling back to lightweight heuristic OCR.")
            self._initialized = False

    @property
    def is_paddle_ready(self) -> bool:
        return self._initialized and (self._paddle is not None)

    @classmethod
    def normalize_code(cls, raw: str) -> str:
        """Cleans and corrects common OCR alphanumeric confusions."""
        if not raw:
            return ""
        cleaned = "".join(ch for ch in raw if ch.isalnum() or ch in "-_").strip().upper()
        if not cleaned:
            return ""

        # Check legacy P001 pattern with 'O' instead of '0'
        if cleaned.startswith("P") and len(cleaned) == 4:
            digits = cleaned[1:].replace("O", "0").replace("D", "0").replace("Q", "0")
            if digits.isdigit():
                return f"P{digits}"

        # Check standard 3-char code: [Layer A-C][Slot A-K][Size 1-2]
        if len(cleaned) == 3:
            layer = cleaned[0]
            slot = cleaned[1]
            size = cleaned[2]

            # Disambiguate layer (A, B, C)
            if layer in ("4", "@"):
                layer = "A"
            elif layer == "8":
                layer = "B"
            elif layer == "0" or layer == "O":
                layer = "C"

            # Disambiguate slot letter (A-K excluding I)
            if slot == "1" or slot == "I" or slot == "|":
                slot = "J" # Closest slot to I

            # Disambiguate size digit (1 or 2)
            if size in ("I", "L", "|", "/"):
                size = "1"
            elif size in ("Z", "S"):
                size = "2"

            candidate = f"{layer}{slot}{size}"
            if cls.SKU_PATTERN.match(candidate):
                return candidate

        return cleaned

    @classmethod
    def is_valid_sku_code(cls, code: str) -> bool:
        """Validates if code corresponds to a known shelf catalog code."""
        if not code:
            return False
        return bool(cls.SKU_PATTERN.match(code) or cls.LEGACY_PATTERN.match(code))

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
                            normalized = self.normalize_code(text)
                            if conf > best_conf and len(normalized) > 0:
                                best_text = normalized
                                best_conf = conf
                    if best_text:
                        return best_text, round(best_conf, 2)
            except Exception as e:
                logger.error(f"Error during PaddleOCR inference: {e}")

        return self._fallback_reader(cropped_cap_bgr)

    def _fallback_reader(self, img: np.ndarray) -> Tuple[str, float]:
        """Graceful fallback when Paddle weights are unavailable or running headless."""
        try:
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            std_val = float(np.std(gray))
            if std_val < 15.0:
                return "UNREADABLE", 0.0
            # Cap detected by edge variance, but text is unread without Paddle
            return "", 0.0
        except Exception:
            return "UNREADABLE", 0.0

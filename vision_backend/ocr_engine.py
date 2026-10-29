"""OCR Engine with EasyOCR, PyTesseract, and robust circular cap sticker decoding."""
import os
import logging
from typing import Tuple, List, Optional
import numpy as np
import cv2
import re

# Ensure writable cache directories for containerized and edge environments
os.environ["TORCH_HOME"] = os.path.expanduser("~/.cache/torch")
os.environ["MPLCONFIGDIR"] = "/tmp/matplotlib"

logger = logging.getLogger("vision_backend.ocr")

class OCREngine:
    # Standard Otto Scents Cap SKU Code Pattern:
    # [Layer A/B/C][Slot A-K (excluding I)][Size 1=100ml, 2=50ml] or Legacy P001-P060
    SKU_PATTERN = re.compile(r"^[A-C][A-HJ-K][1-2]$")
    LEGACY_PATTERN = re.compile(r"^P\d{3}$")

    def __init__(self):
        self._easyocr = None
        self._paddle = None
        self._has_tesseract = False
        self._initialized = False
        self._init_ocr()

    def _init_ocr(self):
        # 1. Try EasyOCR (best for PyTorch-based environments and arbitrary text rotations)
        try:
            import easyocr
            logger.info("Initializing EasyOCR reader for cap detection...")
            self._easyocr = easyocr.Reader(["en"], gpu=False)
            self._initialized = True
            logger.info("EasyOCR initialized successfully.")
            return
        except Exception as e:
            logger.warning(f"EasyOCR not available: {e}")

        # 2. Try PyTesseract
        try:
            import pytesseract
            pytesseract.get_tesseract_version()
            self._has_tesseract = True
            self._initialized = True
            logger.info("PyTesseract OCR available as fallback.")
            return
        except Exception as e:
            logger.warning(f"PyTesseract not available: {e}")

        # 3. Try PaddleOCR
        try:
            from paddleocr import PaddleOCR
            os.environ["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
            try:
                self._paddle = PaddleOCR(use_textline_orientation=True, lang='en')
            except TypeError:
                self._paddle = PaddleOCR(use_angle_cls=True, lang='en')
            self._initialized = True
            logger.info("PaddleOCR initialized successfully.")
            return
        except Exception as e:
            logger.warning(f"PaddleOCR not available: {e}. Falling back to heuristic OCR.")

    @property
    def is_ready(self) -> bool:
        return self._initialized

    @property
    def is_paddle_ready(self) -> bool:
        return self._paddle is not None

    @classmethod
    def decode_sku(cls, raw: str) -> str:
        """
        Disambiguates alphanumeric characters on round cap stickers,
        handling normal orientation and 180-degree upside down text.
        """
        text = "".join(ch for ch in raw if ch.isalnum()).upper()
        if not text:
            return ""

        if cls.SKU_PATTERN.match(text):
            return text

        if cls.LEGACY_PATTERN.match(text):
            return text

        def map_triplet(s: str) -> str:
            if len(s) != 3:
                return ""
            c0, c1, c2 = s[0], s[1], s[2]

            # Layer (A, B, C)
            if c0 in ("4", "@", "R"):
                c0 = "A"
            elif c0 in ("8", "3"):
                c0 = "B"
            elif c0 in ("0", "O", "D", "Q", "G"):
                c0 = "C"

            # Slot (A-K excluding I)
            if c1 in ("4", "@"):
                c1 = "A"
            elif c1 in ("8", "9", "6", "3", "E"):
                c1 = "B"
            elif c1 in ("0", "O", "D", "Q"):
                c1 = "C"
            elif c1 in ("1", "I", "|"):
                c1 = "J"

            # Size (1 or 2)
            if c2 in ("I", "L", "|", "/", "T", "7", "J", "!"):
                c2 = "1"
            elif c2 in ("Z", "S", "?"):
                c2 = "2"

            cand = f"{c0}{c1}{c2}"
            return cand if cls.SKU_PATTERN.match(cand) else ""

        # 1. Direct triplet substitution
        d = map_triplet(text)
        if d:
            return d

        # 2. 180-degree inverted triplet (read backward: Size, Slot, Layer)
        rev = text[::-1]
        inv = ""
        for c in rev:
            if c in ("Z", "S"):
                inv += "2"
            elif c in ("T", "L", "I", "/", "1", "7"):
                inv += "1"
            elif c in ("9", "6", "8", "E"):
                inv += "B"
            elif c in ("D", "O", "0", "Q"):
                inv += "C"
            elif c in ("V", "@", "4"):
                inv += "A"
            else:
                inv += c

        d_rev = map_triplet(inv)
        if d_rev:
            return d_rev

        return ""

    @classmethod
    def is_valid_sku_code(cls, code: str) -> bool:
        """Validates if code corresponds to a known shelf catalog code."""
        if not code:
            return False
        return bool(cls.SKU_PATTERN.match(code) or cls.LEGACY_PATTERN.match(code))

    def extract_text(self, cropped_cap_bgr: np.ndarray) -> Tuple[str, float]:
        """
        Takes a cropped BGR image of a cap sticker and returns (recognized_sku, confidence).
        Applies circular sticker masking and rotational inspection.
        """
        if cropped_cap_bgr is None or cropped_cap_bgr.size == 0:
            return "", 0.0

        h, w = cropped_cap_bgr.shape[:2]
        if h < 12 or w < 12:
            return "", 0.0

        # Circular mask: bottle cap stickers are white circles in the center.
        # Masking outer 30% removes dark cap edges and metallic reflections.
        cy, cx = h // 2, w // 2
        y, x = np.ogrid[:h, :w]
        inner_mask = (np.sqrt((x - cx) ** 2 + (y - cy) ** 2)) < (min(cx, cy) * 0.70)

        gray = cv2.cvtColor(cropped_cap_bgr, cv2.COLOR_BGR2GRAY)
        clean = np.full((h, w), 255, dtype=np.uint8)
        clean[inner_mask] = gray[inner_mask]

        # Upscale 3x with cubic interpolation for sharp character strokes
        scaled = cv2.resize(clean, (w * 3, h * 3), interpolation=cv2.INTER_CUBIC)

        # 1. EasyOCR evaluation
        if self._easyocr is not None:
            # Test cardinal rotations in order of likelihood: 0°, 180°, 90°, 270°
            rotations = [None, cv2.ROTATE_180, cv2.ROTATE_90_CLOCKWISE, cv2.ROTATE_90_COUNTERCLOCKWISE]
            for rot in rotations:
                curr_img = scaled if rot is None else cv2.rotate(scaled, rot)
                try:
                    res = self._easyocr.readtext(curr_img)
                    for r in res:
                        sku = self.decode_sku(r[1])
                        if sku:
                            conf = float(r[2]) if len(r) > 2 else 0.85
                            return sku, round(conf, 2)
                except Exception as e:
                    logger.debug(f"EasyOCR attempt failed: {e}")

        # 2. PyTesseract fallback
        if self._has_tesseract:
            import pytesseract
            rotations = [None, cv2.ROTATE_180, cv2.ROTATE_90_CLOCKWISE, cv2.ROTATE_90_COUNTERCLOCKWISE]
            for rot in rotations:
                curr_img = scaled if rot is None else cv2.rotate(scaled, rot)
                try:
                    raw = pytesseract.image_to_string(
                        curr_img,
                        config="--psm 7 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                    ).strip()
                    sku = self.decode_sku(raw)
                    if sku:
                        return sku, 0.80
                except Exception:
                    pass

        # 3. PaddleOCR fallback
        if self.is_paddle_ready:
            try:
                result = self._paddle.ocr(scaled)
                if result and result[0]:
                    for line in result[0]:
                        if len(line) >= 2 and len(line[1]) >= 2:
                            raw = line[1][0]
                            sku = self.decode_sku(raw)
                            if sku:
                                return sku, round(float(line[1][1]), 2)
            except Exception as e:
                logger.debug(f"PaddleOCR failed: {e}")

        return "", 0.0


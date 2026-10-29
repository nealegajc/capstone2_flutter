"""Image Quality Evaluator and Preprocessor for Smart Shelf Vision."""
import cv2
import numpy as np
from typing import Tuple, List, Dict, Any
from config import MIN_BRIGHTNESS, MAX_BRIGHTNESS, MIN_CONTRAST, MIN_SHARPNESS

class QualityEvaluator:
    @staticmethod
    def calculate_metrics(image: np.ndarray) -> Dict[str, float]:
        """Calculates brightness, contrast, and sharpness metrics."""
        if image is None or image.size == 0:
            return {"brightness": 0.0, "contrast": 0.0, "sharpness": 0.0}

        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image

        # Brightness: average pixel intensity (0 to 255)
        brightness = float(np.mean(gray))

        # Contrast: standard deviation of pixel intensities
        contrast = float(np.std(gray))

        # Sharpness: variance of Laplacian
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        sharpness = float(np.var(laplacian))

        return {
            "brightness": round(brightness, 2),
            "contrast": round(contrast, 2),
            "sharpness": round(sharpness, 2),
        }

    @staticmethod
    def is_acceptable(metrics: Dict[str, float]) -> bool:
        """Verifies if image metrics meet minimum requirements for detection and OCR."""
        b = metrics.get("brightness", 0.0)
        c = metrics.get("contrast", 0.0)
        s = metrics.get("sharpness", 0.0)

        return (MIN_BRIGHTNESS <= b <= MAX_BRIGHTNESS) and (c >= MIN_CONTRAST) and (s >= MIN_SHARPNESS)

    @classmethod
    def enhance_image(cls, image: np.ndarray) -> Tuple[np.ndarray, List[str]]:
        """Applies adaptive enhancements (CLAHE, Bilateral filtering, Sharpening)."""
        applied: List[str] = []
        if image is None or image.size == 0:
            return image, applied

        # 1. Bilateral filter for noise reduction while keeping edges sharp
        denoised = cv2.bilateralFilter(image, d=9, sigmaColor=75, sigmaSpace=75)
        applied.append("Bilateral_Filter")

        # 2. CLAHE (Contrast Limited Adaptive Histogram Equalization) on LAB color space
        lab = cv2.cvtColor(denoised, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        l_enhanced = clahe.apply(l)
        enhanced_lab = cv2.merge((l_enhanced, a, b))
        enhanced_bgr = cv2.cvtColor(enhanced_lab, cv2.COLOR_LAB2BGR)
        applied.append("CLAHE")

        # 3. Unsharp masking kernel for OCR edge crispness
        kernel = np.array([[0, -1, 0],
                           [-1, 5, -1],
                           [0, -1, 0]], dtype=np.float32)
        sharpened = cv2.filter2D(enhanced_bgr, -1, kernel)
        applied.append("Sharpening")

        return sharpened, applied

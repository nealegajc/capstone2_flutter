#!/usr/bin/env python3
"""
dataset_generator.py

Generates an orientation-invariant training & validation dataset for cap recognition.
Combines harvested physical cap crops with 360-degree rotation & lighting augmentations
and clean synthetic sticker renderings.
"""

import os
import glob
import json
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

ALL_SKUS = [
    # Cam 1 (Layer A Left)
    'AA1', 'AA2', 'AB1', 'AB2', 'AC1', 'AC2', 'AD1', 'AD2', 'AE1', 'AE2',
    # Cam 2 (Layer A Right)
    'AF1', 'AF2', 'AG1', 'AG2', 'AH1', 'AH2', 'AJ1', 'AJ2', 'AK1', 'AK2',
    # Cam 3 (Layer B Left)
    'BA1', 'BA2', 'BB1', 'BB2', 'BC1', 'BC2', 'BD1', 'BD2', 'BE1', 'BE2',
    # Cam 4 (Layer B Right)
    'BF1', 'BF2', 'BG1', 'BG2', 'BH1', 'BH2', 'BJ1', 'BJ2', 'BK1', 'BK2',
    # Cam 5 (Layer C Left)
    'CA1', 'CA2', 'CB1', 'CB2', 'CC1', 'CC2', 'CD1', 'CD2', 'CE1', 'CE2',
    # Cam 6 (Layer C Right)
    'CF1', 'CF2', 'CG1', 'CG2', 'CH1', 'CH2', 'CJ1', 'CJ2', 'CK1', 'CK2',
]

FONTS = [
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/freefont/FreeSansBold.ttf',
    '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
    '/usr/share/fonts/opentype/urw-base35/NimbusSans-Bold.otf',
]
FONTS = [f for f in FONTS if os.path.exists(f)]

def apply_circular_mask(img_np: np.ndarray, radius_ratio: float = 0.44) -> np.ndarray:
    """Masks out everything outside circular cap radius with 0 (pure black)."""
    h, w = img_np.shape[:2]
    cx, cy = w / 2.0, h / 2.0
    r = min(w, h) * radius_ratio
    y, x = np.ogrid[:h, :w]
    outside = (x - cx) ** 2 + (y - cy) ** 2 > r ** 2
    out = img_np.copy()
    out[outside] = 0
    return out

def augment_real_crop(img: Image.Image, target_size=(64, 64)) -> Image.Image:
    """Rotates by random angle (0-360) and applies illumination/blur jitter with circular mask."""
    img = img.convert('RGB')
    angle = random.uniform(0, 360)
    
    # Resize to target size first
    img_resized = img.resize(target_size, resample=Image.BILINEAR)
    
    # Mask to cap disc before rotation so background doesn't smear
    arr = apply_circular_mask(np.array(img_resized), radius_ratio=0.45)
    img_masked = Image.fromarray(arr)
    
    # Rotate with black fillcolor
    rotated = img_masked.rotate(angle, resample=Image.BICUBIC, expand=False, fillcolor=(0, 0, 0))
    
    # Re-apply mask to ensure sharp circular boundary
    final_arr = apply_circular_mask(np.array(rotated), radius_ratio=0.44)
    out = Image.fromarray(final_arr)
    
    # Brightness jitter
    enh_b = ImageEnhance.Brightness(out)
    out = enh_b.enhance(random.uniform(0.70, 1.30))
    
    # Contrast jitter
    enh_c = ImageEnhance.Contrast(out)
    out = enh_c.enhance(random.uniform(0.75, 1.25))
    
    # Slight blur occasionally
    if random.random() < 0.20:
        out = out.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.3, 0.8)))
        
    return out

def generate_synthetic_crop(sku: str, target_size=(64, 64)) -> Image.Image:
    """Generates synthetic cap sticker with text at random rotation and lighting."""
    tw, th = target_size
    img = Image.new('RGB', target_size, color=(0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    cx = tw / 2.0 + random.uniform(-1.5, 1.5)
    cy = th / 2.0 + random.uniform(-1.5, 1.5)
    cap_r = tw * random.uniform(0.42, 0.45)
    sticker_r = tw * random.uniform(0.31, 0.35)
    
    # Cap metallic/black outer rim
    rim_val = random.choice([40, 55, 70, 160, 190])
    draw.ellipse([cx - cap_r, cy - cap_r, cx + cap_r, cy + cap_r], fill=(rim_val, rim_val, rim_val))
    
    # White sticker disc
    sticker_val = random.randint(210, 248)
    draw.ellipse([cx - sticker_r, cy - sticker_r, cx + sticker_r, cy + sticker_r], fill=(sticker_val, sticker_val, sticker_val))
    
    # Render SKU text
    font_file = random.choice(FONTS) if FONTS else None
    font_size = int(tw * random.uniform(0.25, 0.30))
    font = ImageFont.truetype(font_file, font_size) if font_file else ImageFont.load_default()
    
    txt_layer = Image.new('RGBA', target_size, (0, 0, 0, 0))
    txt_draw = ImageDraw.Draw(txt_layer)
    bbox = font.getbbox(sku)
    bw = bbox[2] - bbox[0]
    bh = bbox[3] - bbox[1]
    
    t_val = random.randint(15, 50)
    txt_color = (t_val, t_val, t_val, 255)
    
    tx = (tw - bw) / 2.0 - bbox[0] + random.uniform(-2.5, 2.5)
    ty = (th - bh) / 2.0 - bbox[1] + random.uniform(-4.0, 4.0)
    txt_draw.text((tx, ty), sku, fill=txt_color, font=font)
    
    # Rotate text layer by random angle
    angle = random.uniform(0, 360)
    txt_rot = txt_layer.rotate(angle, resample=Image.BICUBIC)
    img.paste(txt_rot, (0, 0), txt_rot)
    
    # Circular mask outside cap
    arr = apply_circular_mask(np.array(img), radius_ratio=0.44)
    out = Image.fromarray(arr)
    
    # Add subtle lighting variations
    enh_b = ImageEnhance.Brightness(out)
    out = enh_b.enhance(random.uniform(0.75, 1.25))
    
    enh_c = ImageEnhance.Contrast(out)
    out = enh_c.enhance(random.uniform(0.80, 1.25))
    
    if random.random() < 0.20:
        out = out.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.3, 0.6)))
        
    return out

def apply_clahe(img_np: np.ndarray) -> np.ndarray:
    """Enhances local contrast for cap crop."""
    import cv2
    lab = cv2.cvtColor(img_np, cv2.COLOR_RGB2LAB)
    clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    lab[:, :, 0] = clahe.apply(lab[:, :, 0])
    return cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)

def build_dataset(
    raw_dirs: list = None,
    out_dir: str = 'dataset/processed',
    augs_per_real: int = 25,
    synthetics_per_sku: int = 80,
    val_split: float = 0.15
):
    if raw_dirs is None:
        raw_dirs = ['dataset/raw_caps_2k_bright']
    print(f"Building dataset from {raw_dirs} -> {out_dir} (64x64, circular masked)...")
    train_dir = os.path.join(out_dir, 'train')
    val_dir = os.path.join(out_dir, 'val')
    os.makedirs(train_dir, exist_ok=True)
    os.makedirs(val_dir, exist_ok=True)
    
    # Save classes map
    classes_file = os.path.join(out_dir, 'classes.json')
    with open(classes_file, 'w') as f:
        json.dump(ALL_SKUS, f, indent=2)
    print(f"Registered {len(ALL_SKUS)} classes to {classes_file}")
    
    total_train = 0
    total_val = 0
    
    for idx, sku in enumerate(ALL_SKUS):
        real_files = []
        for r_dir in raw_dirs:
            sku_dir = os.path.join(r_dir, sku)
            if os.path.exists(sku_dir):
                real_files.extend(glob.glob(os.path.join(sku_dir, '*.jpg')))
        
        sku_train_dir = os.path.join(train_dir, sku)
        sku_val_dir = os.path.join(val_dir, sku)
        os.makedirs(sku_train_dir, exist_ok=True)
        os.makedirs(sku_val_dir, exist_ok=True)
        
        # Clear existing images in directories to avoid stale data
        for f in glob.glob(os.path.join(sku_train_dir, '*.jpg')):
            try: os.remove(f)
            except: pass
        for f in glob.glob(os.path.join(sku_val_dir, '*.jpg')):
            try: os.remove(f)
            except: pass
            
        generated_images = []
        
        # 1. Augment real crops with circular mask
        for r_file in real_files:
            try:
                base_img = Image.open(r_file)
                base_arr = apply_circular_mask(np.array(base_img.resize((64, 64), resample=Image.BILINEAR)), radius_ratio=0.44)
                generated_images.append(Image.fromarray(base_arr))
                
                for _ in range(augs_per_real):
                    aug = augment_real_crop(base_img, target_size=(64, 64))
                    generated_images.append(aug)
            except Exception as e:
                print(f"Warning: Failed to process real crop {r_file}: {e}")
                
        # 2. Generate synthetic crops
        for _ in range(synthetics_per_sku):
            syn = generate_synthetic_crop(sku, target_size=(64, 64))
            generated_images.append(syn)
            
        random.shuffle(generated_images)
        n_val = max(1, int(len(generated_images) * val_split))
        val_imgs = generated_images[:n_val]
        train_imgs = generated_images[n_val:]
        
        for i, img in enumerate(train_imgs):
            img.save(os.path.join(sku_train_dir, f"{sku}_train_{i:04d}.jpg"), quality=95)
            
        for i, img in enumerate(val_imgs):
            img.save(os.path.join(sku_val_dir, f"{sku}_val_{i:04d}.jpg"), quality=95)
            
        total_train += len(train_imgs)
        total_val += len(val_imgs)
        
        if (idx + 1) % 10 == 0 or (idx + 1) == len(ALL_SKUS):
            print(f"[{idx+1:02d}/{len(ALL_SKUS)}] {sku}: {len(train_imgs)} train, {len(val_imgs)} val | Total: {total_train + total_val}")
            
    print(f"\nDataset build complete! Total: {total_train} train images, {total_val} validation images across {len(ALL_SKUS)} SKUs.")

if __name__ == '__main__':
    build_dataset()

import io
import os
import numpy as np
import torch
from PIL import Image, ImageOps
from pytorch_grad_cam import GradCAM
from pytorch_grad_cam.utils.image import show_cam_on_image

from .classifier import get_classifier, _transform


def generate_heatmap(image_bytes: bytes, target_class: int, save_dir: str = "uploads/heatmaps") -> str:
    """결함 클래스에 대한 Grad-CAM 히트맵 PNG를 생성하고 로컬 경로 반환."""
    os.makedirs(save_dir, exist_ok=True)

    clf = get_classifier()
    target_layer = clf.model.features[-1]

    img = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes)).convert("RGB"))
    rgb_arr = np.array(img.resize((384, 384))) / 255.0   # 튜토리얼 224×224에서 수정
    tensor = _transform(img).unsqueeze(0).to(clf.device)

    cam = GradCAM(model=clf.model, target_layers=[target_layer])
    targets = [__import__("pytorch_grad_cam").utils.model_targets.ClassifierOutputTarget(target_class)]
    grayscale_cam = cam(input_tensor=tensor, targets=targets)[0]

    overlay = show_cam_on_image(rgb_arr.astype(np.float32), grayscale_cam, use_rgb=True)
    out_path = os.path.join(save_dir, f"heatmap_{__import__('uuid').uuid4().hex}.png")
    Image.fromarray(overlay).save(out_path)
    return f"local://{out_path}"   # MVP: 로컬 경로. 운영은 S3 URL.


def to_public_url(local_path: str, base_url: str = "") -> str:
    from app.core.config import settings
    base_url = base_url or settings.SERVER_BASE_URL
    return local_path.replace("local://", f"{base_url}/")

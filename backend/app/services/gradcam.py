import io
import numpy as np
import torch
from PIL import Image, ImageOps
from pytorch_grad_cam import GradCAM
from pytorch_grad_cam.utils.image import show_cam_on_image

from .classifier import get_classifier, _transform


def generate_heatmap(image_bytes: bytes, target_class: int) -> bytes:
    """결함 클래스에 대한 Grad-CAM 히트맵 PNG를 생성하고 PNG bytes 반환. (호출자가 S3 업로드)"""
    clf = get_classifier()
    target_layer = clf.model.features[-1]

    img = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes)).convert("RGB"))
    rgb_arr = np.array(img.resize((384, 384))) / 255.0   # 튜토리얼 224×224에서 수정
    tensor = _transform(img).unsqueeze(0).to(clf.device)

    cam = GradCAM(model=clf.model, target_layers=[target_layer])
    targets = [__import__("pytorch_grad_cam").utils.model_targets.ClassifierOutputTarget(target_class)]
    grayscale_cam = cam(input_tensor=tensor, targets=targets)[0]

    overlay = show_cam_on_image(rgb_arr.astype(np.float32), grayscale_cam, use_rgb=True)
    buf = io.BytesIO()
    Image.fromarray(overlay).save(buf, format="PNG")
    return buf.getvalue()

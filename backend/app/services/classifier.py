import torch
import torchvision.models as models
import torchvision.transforms as T
from PIL import Image, ImageOps
import io


_CLASSES = [
    # 용접 (0~2)
    "용접불량-조인트", "용접블로우홀-조인트", "용접양품-조인트",
    # 절단 (3~6)
    "절단불량-모재", "절단불량-보온재", "절단양품-모재", "절단양품-보온재",
    # 케이블 (7~12)
    "바인딩불량-케이블타이", "바인딩양품-케이블타이",
    "케이블설치불량-케이블그랜드", "케이블설치양품-케이블그랜드",
    "케이블손상-케이블", "케이블양품-케이블",
    # 파이프 (13~14)
    "볼트체결불량-파이프", "볼트체결양품-파이프",
    # 폼스프레이 (15~16)
    "폼스프레이불량-우레탄폼", "폼스프레이양품-우레탄폼",
    # 표면처리 (17~29)
    "균열-도장", "균열-보온재", "도막떨어짐-도장", "도막분리-도장", "도장흐름-도장",
    "보온재손상-보온재", "스크래치-도장", "스크래치-모재", "스크래치-보온재", "탱크클리닝불량-모재",
    "표면양품-도장", "표면양품-모재", "표면양품-보온재",
]  # 단일 통합 모델 30클래스 (불량 19 + 양품 11)


_transform = T.Compose([
    T.Resize((384, 384)),   # 실제 모델 입력 크기 384×384 (튜토리얼 224×224에서 수정)
    T.ToTensor(),
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])


class UnifiedClassifier:
    def __init__(self, weights_path: str, device: str = "cpu"):
        self.device = device
        self.model = models.mobilenet_v3_large(weights=None)
        self.model.classifier[3] = torch.nn.Linear(in_features=1280, out_features=len(_CLASSES))
        self.model.load_state_dict(torch.load(weights_path, map_location=device, weights_only=True))
        self.model.eval()
        self.model.to(device)

    def predict(self, image_bytes: bytes) -> dict:
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes)).convert("RGB"))
        tensor = _transform(img).unsqueeze(0).to(self.device)
        with torch.no_grad():
            logits = self.model(tensor)
            probs = torch.softmax(logits, dim=1)[0].cpu().numpy()

        top3_idx = probs.argsort()[-3:][::-1]
        top3 = [{"class": _CLASSES[i], "confidence": float(probs[i])} for i in top3_idx]
        return {
            "defect_type": top3[0]["class"],
            "confidence": top3[0]["confidence"],
            "top3": top3,
            "is_defect": "양품" not in top3[0]["class"],
        }


_classifier_singleton: UnifiedClassifier | None = None


def get_classifier() -> UnifiedClassifier:
    global _classifier_singleton
    if _classifier_singleton is None:
        _classifier_singleton = UnifiedClassifier("models/best_model_v5_datamatch_full.pth")
    return _classifier_singleton

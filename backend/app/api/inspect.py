import json
import random
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.config import settings
from app.core.db import get_db
from app.api.deps import get_current_inspector_id
from app.services import s3_store


router = APIRouter()


def _parse_iso_naive(s: str) -> datetime:
    """ISO 8601 문자열 → naive(UTC) datetime. asyncpg는 timestamp 컬럼에 문자열을 거부함."""
    dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


async def _apply_default_action_guide(db: AsyncSession, result_id: int, defect_type: str) -> dict | None:
    """매뉴얼(결함_유형 단독 룩업) → 조치_권고 + 조치_권고_매뉴얼 INSERT. RAG/LLM 없는 정적 매핑.

    서버 정밀분석 / 단말 자동 종결 / 오프라인 배치 — 모든 결과 경로에서 동일하게 호출한다.
    process_id 는 위치 메타용이라 룩업에 쓰지 않고 결함_유형으로만 매칭한다(단말 경로 정확도).
    클래스 미등록(룩업 실패) 시 None 반환(가이드 없는 결과로 처리). 반환 dict 는 응답용 action_guide.
    양품 클래스도 매뉴얼 테이블 양품 행(seed_manuals)으로 동일하게 처리된다."""
    m = (await db.execute(text("""
        SELECT 매뉴얼_ID, 제목, 조치_요약, 조치_상세, 페이지_번호, 청크_순서
        FROM 매뉴얼 WHERE 결함_유형 = :d
        ORDER BY 매뉴얼_ID LIMIT 1
    """), {"d": defect_type})).first()
    if m is None:
        return None

    rec = (await db.execute(text("""
        INSERT INTO 조치_권고 (결과_ID, 조치_요약, 조치_상세, 생성_일시, 수정_일시)
        VALUES (:rid, :s, :d, NOW(), NOW())
        RETURNING 권고_ID
    """), {"rid": result_id, "s": m[2], "d": m[3]})).first()
    rec_id = rec[0]

    await db.execute(text("""
        INSERT INTO 조치_권고_매뉴얼 (권고_ID, 매뉴얼_ID, 순위, 유사도_점수)
        VALUES (:r, :m, 1, 1.0)
    """), {"r": rec_id, "m": m[0]})

    return {
        "recommendation_id": rec_id,
        "summary": m[2],
        "detail": m[3],
        "source_manuals": [
            {"manual_id": m[0], "title": m[1], "page": m[4], "chunk_order": m[5], "rank": 1}
        ],
    }


def _classify(image_bytes: bytes, on_device_result: dict | None) -> dict:
    """서버 PyTorch 재추론. 모델 로드 실패 시 on_device_result 폴백.

    반환: {defect_type, confidence, top3, is_defect, top1_idx}"""
    try:
        from app.services.classifier import get_classifier, _CLASSES as _CLF_CLASSES
        r = get_classifier().predict(image_bytes)
        top1_class = r["defect_type"]
        return {
            "defect_type": top1_class,
            "confidence": r["confidence"],
            "top3": r["top3"],
            "is_defect": r["is_defect"],
            "top1_idx": _CLF_CLASSES.index(top1_class) if top1_class in _CLF_CLASSES else 0,
        }
    except Exception as clf_err:
        print(f"[WARN] 서버 분류기 실패: {clf_err}")
        try:
            from app.services.classifier import _CLASSES as _CLF_CLASSES
        except Exception:
            _CLF_CLASSES = []
        if on_device_result:
            dt = on_device_result.get("defect_type", "미분류")
            conf = float(on_device_result.get("confidence", 0.0))
            return {
                "defect_type": dt,
                "confidence": conf,
                "top3": on_device_result.get("top3_predictions", [{"class": dt, "confidence": conf}]),
                "is_defect": "양품" not in dt,
                "top1_idx": _CLF_CLASSES.index(dt) if dt in _CLF_CLASSES else 0,
            }
        return {"defect_type": "미분류", "confidence": 0.0,
                "top3": [{"class": "미분류", "confidence": 0.0}], "is_defect": True, "top1_idx": 0}


async def _process_inspection(
    db: AsyncSession,
    image_bytes: bytes,
    session_id: int,
    process_id: int,
    on_device_result: dict | None,
    captured_at: datetime | None,
) -> dict:
    """단일 검사 처리(온라인 /inspect · 오프라인 배치 공통).

    C-B 단말·서버 검증 합의제: 서버 재추론 후 단말과 합의 여부로 완료/미완료 분기.
    이미지는 S3 inspections/, 학습셋은 samples/(서버 라벨), Grad-CAM은 서버 불량분만 heatmaps/.
    """
    ts = captured_at or datetime.utcnow()
    date_path = ts.strftime("%Y/%m/%d")
    file_uuid = uuid.uuid4().hex

    # 1) 원본 이미지 → S3 inspections/
    inspections_uri = await s3_store.put_image(image_bytes, "inspections", date_path, file_uuid, "jpg")

    # 2) 서버 재추론
    clf = _classify(image_bytes, on_device_result)
    top1_class = clf["defect_type"]
    confidence = clf["confidence"]
    server_is_pass = not clf["is_defect"]

    # 3) C-B 검증 분기
    device_is_pass = ("양품" in on_device_result.get("defect_type", "")) if on_device_result else None
    disagreement = device_is_pass is not None and device_is_pass != server_is_pass

    if server_is_pass:
        if device_is_pass and confidence >= settings.GLOBAL_CONFIDENCE_THRESHOLD:
            status, needs_review = "완료", False      # 단말·서버 합의 → 자동종결
            copy_for_al = False
        else:
            status, needs_review = "미완료", True       # 양품 저신뢰 or 단말 불일치
            copy_for_al = True
        gradcam_flag = False
    else:
        status = "미완료"
        needs_review = confidence < settings.SERVER_RECHECK_THRESHOLD
        gradcam_flag = True
        copy_for_al = needs_review or disagreement      # 저신뢰 OR 단말 양품↔서버 불량 flip

    # 4) Grad-CAM (서버 불량 분류분만) → S3 heatmaps/
    heatmap_uri = None
    if gradcam_flag:
        try:
            from app.services.gradcam import generate_heatmap
            png = generate_heatmap(image_bytes, target_class=clf["top1_idx"])
            heatmap_uri = await s3_store.put_image(png, "heatmaps", date_path, file_uuid, "png")
        except Exception as cam_err:
            print(f"[WARN] Grad-CAM 실패: {cam_err}")

    # 5) 검사_이미지 INSERT
    img_row = (await db.execute(text("""
        INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
        VALUES (:sid, :path, :ts) RETURNING 이미지_ID
    """), {"sid": session_id, "path": inspections_uri, "ts": ts})).first()
    image_id = img_row[0]

    # 6) 서버 결과(대표) INSERT
    server_res = (await db.execute(text("""
        INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
            결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms,
            사람_재확인_필요, "Grad-CAM_경로", 결과_처리_상태)
        VALUES (:iid, :pid, '서버', true, :ok, :dtype, :conf, CAST(:top3 AS JSONB), :ms,
                :review, :gradcam, :status)
        RETURNING 결과_ID
    """), {
        "iid": image_id, "pid": process_id, "ok": server_is_pass,
        "dtype": top1_class, "conf": confidence,
        "top3": json.dumps(clf["top3"]), "ms": 1200,
        "review": needs_review, "gradcam": heatmap_uri, "status": status,
    })).first()
    server_result_id = server_res[0]

    # 7) 단말 결과 INSERT (대표=false, 상태는 서버와 동일)
    if on_device_result:
        await db.execute(text("""
            INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
                결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms, 결과_처리_상태)
            VALUES (:iid, :pid, '단말', false, :ok, :dtype, :conf, CAST(:top3 AS JSONB), :ms, :status)
        """), {
            "iid": image_id, "pid": process_id,
            "ok": "양품" in on_device_result.get("defect_type", ""),
            "dtype": on_device_result.get("defect_type", "미분류"),
            "conf": on_device_result.get("confidence", 0.0),
            "top3": json.dumps(on_device_result.get("top3_predictions", [])),
            "ms": on_device_result.get("inference_ms", 0), "status": status,
        })

    # 8) 세션 카운터 (서버 분류 기준)
    await db.execute(text("""
        UPDATE 검사_세션 SET 총_이미지_수 = 총_이미지_수 + 1,
                          양품_수 = 양품_수 + :p, 불량_수 = 불량_수 + :d
        WHERE 세션_ID = :sid
    """), {"sid": session_id, "p": 1 if server_is_pass else 0, "d": 0 if server_is_pass else 1})

    # 9) 매뉴얼(서버 라벨) 룩업 조치 가이드
    action_data = await _apply_default_action_guide(db, server_result_id, top1_class)

    # 10) 학습셋 복사 (active learning ∪ 서버 random 10%). 라벨=서버 재추론값. uuid당 1객체.
    if copy_for_al or random.random() < 0.10:
        try:
            await s3_store.copy_to_samples(inspections_uri, top1_class)
        except Exception as cp_err:
            print(f"[WARN] 학습셋 복사 실패: {cp_err}")

    return {
        "image_id": image_id,
        "server_result": {
            "result_id": server_result_id,
            "defect_type": top1_class,
            "confidence": confidence,
            "inference_ms": 1200,
            "needs_human_review": needs_review,
            "top3_predictions": clf["top3"],
        },
        "heatmap_url": heatmap_uri,
        "result_status": status,
        "action_guide": action_data or {
            "recommendation_id": None,
            "summary": "조치 가이드를 생성하지 못했습니다.",
            "detail": "",
            "source_manuals": [],
        },
    }


@router.post("/inspect")
async def inspect(
    image: UploadFile = File(...),
    session_id: int = Form(...),
    process_id: int = Form(...),
    tank_type: str = Form(...),
    sector: str | None = Form(default=None),
    subsector: str | None = Form(default=None),
    on_device_result: str | None = Form(default=None),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """양품·불량 통합 검사 엔드포인트(INFER-002). 온라인 동기 처리.

    구 local-result(양품 메타)·sample-upload(양품 샘플)를 흡수. 모든 촬영이 이미지를
    S3 inspections/ 에 1회 업로드하고 서버 재추론으로 검증한다."""
    image_bytes = await image.read()
    dev = json.loads(on_device_result) if on_device_result else None
    result = await _process_inspection(db, image_bytes, session_id, process_id, dev, None)
    await db.commit()
    return result


@router.post("/inspect/offline-batch")
async def offline_batch(
    images: list[UploadFile] = File(default=[]),
    metadata: str = Form(...),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """오프라인 큐 배치 업로드(INFER-005). 멱등성 키로 중복 차단.

    /inspect 와 동일하게 서버 재추론·검증·단말+서버 2행·Grad-CAM·학습셋 복사한다.
    모든 메타에 이미지 동봉 필수(파일명=client_request_id 로 매칭). 청크당 10건 권장."""
    metas = json.loads(metadata)
    if len(metas) > 50:
        raise HTTPException(status_code=400, detail={"error": "BATCH_SIZE_LIMIT_EXCEEDED"})

    images_by_crid: dict[str, UploadFile] = {}
    for f in images:
        name = f.filename or ""
        key = name[:-4] if name.endswith(".jpg") else name
        images_by_crid[key] = f

    results = []
    for meta in metas:
        crid = meta["client_request_id"]

        # 멱등성 — 같은 client_request_id 재전송 시 무시
        existing = (await db.execute(text("""
            SELECT 처리_결과 FROM 멱등성_요청 WHERE client_request_id = :rid
        """), {"rid": crid})).first()
        if existing is not None:
            results.append({"client_request_id": crid, "status": "skipped", "reason": "DUPLICATE"})
            continue

        # 이미지 동봉 필수
        if crid not in images_by_crid:
            results.append({"client_request_id": crid, "status": "failed",
                            "error_code": "IMAGE_MISSING", "error_message": "이미지 누락"})
            continue

        try:
            image_bytes = await images_by_crid[crid].read()
            r = await _process_inspection(
                db, image_bytes,
                session_id=meta["session_id"],
                process_id=meta["process_id"],
                on_device_result=meta.get("on_device_result") or None,
                captured_at=_parse_iso_naive(meta["captured_at"]),
            )

            await db.execute(text("""
                INSERT INTO 멱등성_요청 (client_request_id, 검사원_ID, 처리_결과)
                VALUES (:rid, :iid, :res)
            """), {"rid": crid, "iid": inspector_id,
                   "res": json.dumps({"status": "ok", "image_id": r["image_id"]})})

            results.append({
                "client_request_id": crid,
                "status": "success",
                "image_id": r["image_id"],
                "server_result": r["server_result"],
                "result_status": r["result_status"],
            })
        except Exception as e:
            results.append({"client_request_id": crid, "status": "failed",
                            "error_code": "INFERENCE_ERROR", "error_message": str(e)})

    await db.commit()
    success_count = sum(1 for r in results if r["status"] == "success")
    skipped_count = sum(1 for r in results if r["status"] == "skipped")
    return {
        "batch_size": len(metas),
        "succeeded_count": success_count,
        "failed_count": len(metas) - success_count - skipped_count,
        "skipped_duplicates": skipped_count,
        "results": results,
    }

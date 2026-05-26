import json
import os
import uuid
from datetime import datetime, timezone

import aioboto3
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.config import settings
from app.core.db import get_db
from app.api.deps import get_current_inspector_id


router = APIRouter()


def _parse_iso_naive(s: str) -> datetime:
    """ISO 8601 문자열 → naive(UTC) datetime. asyncpg는 timestamp 컬럼에 문자열을 거부함."""
    dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


async def _put_sample_to_s3(data: bytes, defect_type: str) -> str:
    """양품 재학습 샘플 이미지를 S3 samples/ 에 업로드하고 s3 key 를 반환 (INFER-004 공용)."""
    today = datetime.utcnow().strftime("%Y/%m/%d")
    s3_key = f"samples/{today}/{defect_type}/{uuid.uuid4().hex}.jpg"
    session_factory = aioboto3.Session()
    async with session_factory.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    ) as s3:
        await s3.put_object(
            Bucket=settings.S3_BUCKET,
            Key=s3_key,
            Body=data,
            ContentType="image/jpeg",
        )
    return s3_key


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
    # 1) 이미지 읽기
    image_bytes = await image.read()

    # 2) PyTorch 분류 (모델 파일 없거나 로드 실패 시 on_device_result 폴백)
    clf_result = None
    top1_class = None
    top1_idx = 0
    confidence = 0.0
    is_defect_flag = True
    try:
        from app.services.classifier import get_classifier, _CLASSES as _CLF_CLASSES
        clf_result = get_classifier().predict(image_bytes)
        top1_class = clf_result["defect_type"]
        top1_idx = _CLF_CLASSES.index(top1_class)
        confidence = clf_result["confidence"]
        is_defect_flag = clf_result["is_defect"]
    except Exception as clf_err:
        print(f"[WARN] 서버 분류기 실패: {clf_err}")
        try:
            from app.services.classifier import _CLASSES as _CLF_CLASSES
        except Exception:
            _CLF_CLASSES = []
        # on_device_result가 있으면 단말 결과를 서버 결과 대신 사용
        if on_device_result:
            try:
                dev = json.loads(on_device_result)
                top1_class = dev.get("defect_type", "미분류")
                confidence = float(dev.get("confidence", 0.0))
                is_defect_flag = "양품" not in top1_class
                clf_result = {
                    "defect_type": top1_class,
                    "confidence": confidence,
                    "top3": dev.get("top3_predictions", [{"class": top1_class, "confidence": confidence}]),
                    "is_defect": is_defect_flag,
                }
                top1_idx = _CLF_CLASSES.index(top1_class) if top1_class in _CLF_CLASSES else 0
            except Exception:
                top1_class = "미분류"
        else:
            top1_class = "미분류"
        clf_result = clf_result or {
            "defect_type": top1_class,
            "confidence": confidence,
            "top3": [{"class": top1_class, "confidence": confidence}],
            "is_defect": is_defect_flag,
        }

    # 3) Grad-CAM (실패해도 진행)
    heatmap_url = None
    try:
        from app.services.gradcam import generate_heatmap
        local_hm = generate_heatmap(image_bytes, target_class=top1_idx)
        heatmap_url = local_hm.replace("local://", settings.SERVER_BASE_URL + "/")
    except Exception as cam_err:
        print(f"[WARN] Grad-CAM 실패: {cam_err}")

    # 4) 이미지 저장 (로컬)
    os.makedirs("uploads/images", exist_ok=True)
    file_uuid = uuid.uuid4().hex
    img_path = f"uploads/images/{file_uuid}.jpg"
    with open(img_path, "wb") as f:
        f.write(image_bytes)
    image_url = f"{settings.SERVER_BASE_URL}/{img_path}"

    # 5) 검사_이미지 INSERT
    img_row = (await db.execute(text("""
        INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
        VALUES (:sid, :path, NOW()) RETURNING 이미지_ID
    """), {"sid": session_id, "path": image_url})).first()
    image_id = img_row[0]

    # 서버 결과 INSERT
    server_res = (await db.execute(text("""
        INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
            결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms,
            사람_재확인_필요, "Grad-CAM_경로", 결과_처리_상태)
        VALUES (:iid, :pid, '서버', true, :ok, :dtype, :conf, CAST(:top3 AS JSONB), :ms,
                :review, :gradcam, '미완료')
        RETURNING 결과_ID
    """), {
        "iid": image_id, "pid": process_id, "ok": not is_defect_flag,
        "dtype": top1_class, "conf": confidence,
        "top3": json.dumps(clf_result["top3"]),
        "ms": 1200, "review": confidence < 0.70,
        "gradcam": heatmap_url,
    })).first()
    server_result_id = server_res[0]

    # 단말 결과 동봉 시 row 추가 (대표=false)
    if on_device_result:
        try:
            dev = json.loads(on_device_result)
            await db.execute(text("""
                INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
                    결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms, 결과_처리_상태)
                VALUES (:iid, :pid, '단말', false, :ok, :dtype, :conf, CAST(:top3 AS JSONB), :ms, '미완료')
            """), {
                "iid": image_id, "pid": process_id,
                "ok": "양품" in dev["defect_type"],
                "dtype": dev["defect_type"], "conf": dev["confidence"],
                "top3": json.dumps(dev.get("top3_predictions", [])),
                "ms": dev.get("inference_ms", 0),
            })
        except Exception:
            pass

    # 세션 카운터
    await db.execute(text("""
        UPDATE 검사_세션 SET 총_이미지_수 = 총_이미지_수 + 1,
                          양품_수 = 양품_수 + :p,
                          불량_수 = 불량_수 + :d
        WHERE 세션_ID = :sid
    """), {"sid": session_id, "p": 0 if is_defect_flag else 1, "d": 1 if is_defect_flag else 0})

    # 6) 매뉴얼 조회 → 사전 작성된 조치 가이드를 그대로 사용
    action_data = None
    manuals = []
    try:
        from app.services.manual_search import search_manuals
        print(f"[MANUAL] 분류 결과: {top1_class}, process_id={process_id}")
        manuals = await search_manuals(db, top1_class, process_id, top_k=3)
        print(f"[MANUAL] 매뉴얼 검색 결과: {len(manuals)}건")
    except Exception as e:
        print(f"[WARN] 매뉴얼 검색 실패: {e}")

    if manuals:
        primary = manuals[0]
        summary = primary["summary"] or "조치 가이드가 등록되지 않았습니다."
        detail  = primary["detail"]  or ""
        try:
            rec_row = (await db.execute(text("""
                INSERT INTO 조치_권고 (결과_ID, 조치_요약, 조치_상세, 생성_일시, 수정_일시)
                VALUES (:rid, :sum, :det, NOW(), NOW())
                RETURNING 권고_ID
            """), {"rid": server_result_id, "sum": summary, "det": detail})).first()
            rec_id = rec_row[0]

            for i, m in enumerate(manuals):
                await db.execute(text("""
                    INSERT INTO 조치_권고_매뉴얼 (권고_ID, 매뉴얼_ID, 순위, 유사도_점수)
                    VALUES (:r, :m, :rank, :sim)
                """), {"r": rec_id, "m": m["manual_id"], "rank": i+1, "sim": 1.0})

            action_data = {
                "recommendation_id": rec_id,
                "summary": summary,
                "detail": detail,
                "source_manuals": [
                    {"manual_id": m["manual_id"], "title": m["title"], "page": m["page"],
                     "chunk_order": m["chunk_order"], "rank": i+1}
                    for i, m in enumerate(manuals)
                ],
            }
        except Exception as e:
            print(f"[WARN] 조치 권고 저장 실패: {e}")
            action_data = {
                "recommendation_id": None,
                "summary": summary,
                "detail": detail,
                "source_manuals": [],
            }

    await db.commit()

    return {
        "image_id": image_id,
        "server_result": {
            "result_id": server_result_id,
            "defect_type": top1_class,
            "confidence": confidence,
            "inference_ms": 1200,
            "needs_human_review": confidence < 0.70,
            "top3_predictions": clf_result["top3"],
        },
        "heatmap_url": heatmap_url,
        "action_guide": action_data or {
            "recommendation_id": None,
            "summary": "조치 가이드를 생성하지 못했습니다.",
            "detail": "",
            "source_manuals": [],
        },
    }


@router.post("/inspect/sample-upload")
async def sample_upload(
    image: UploadFile = File(...),
    session_id: int = Form(...),
    process_id: int = Form(...),
    defect_type: str = Form(...),
    confidence: float = Form(...),
    captured_at: str = Form(...),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """양품 사진 10% 샘플 — S3 비동기 업로드 + 검사_이미지 메타 INSERT (INFER-004).

    재학습용 이미지만 S3에 누적. 검사_결과 INSERT 없음(단말 자동 종결 완료)."""

    if "양품" not in defect_type:
        raise HTTPException(status_code=400, detail={"error": "NOT_A_PASS_CLASS"})

    data = await image.read()
    s3_key = await _put_sample_to_s3(data, defect_type)

    await db.execute(text("""
        INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
        VALUES (:sid, :path, :ts)
    """), {
        "sid": session_id,
        "path": f"s3://{settings.S3_BUCKET}/{s3_key}",
        "ts": _parse_iso_naive(captured_at),
    })
    await db.commit()

    return {"uploaded": True, "s3_key": s3_key}


@router.post("/inspect/local-result")
async def local_result(
    payload: dict,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """양품 단말 결과 기록 (이미지 없이 메타만)"""
    sid = payload["session_id"]
    pid = payload["process_id"]
    dtype = payload["defect_type"]
    conf = payload["confidence"]
    top3 = payload.get("top3_predictions", [])

    img_row = (await db.execute(text("""
        INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
        VALUES (:sid, :path, NOW())
        RETURNING 이미지_ID
    """), {"sid": sid, "path": "local://device-only"})).first()
    image_id = img_row[0]

    res_row = (await db.execute(text("""
        INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
            결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms, 결과_처리_상태)
        VALUES (:iid, :pid, '단말', true, true,
            :dtype, :conf, CAST(:top3 AS JSONB), :ms, '완료')
        RETURNING 결과_ID
    """), {
        "iid": image_id, "pid": pid, "dtype": dtype, "conf": conf,
        "top3": __import__("json").dumps(top3), "ms": payload.get("inference_ms", 0),
    })).first()

    await db.execute(text("""
        UPDATE 검사_세션 SET 총_이미지_수 = 총_이미지_수 + 1, 양품_수 = 양품_수 + 1
        WHERE 세션_ID = :sid
    """), {"sid": sid})
    await db.commit()
    return {"image_id": image_id, "result_id": res_row[0]}


@router.post("/inspect/offline-batch")
async def offline_batch(
    images: list[UploadFile] = File(default=[]),
    metadata: str = Form(...),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """오프라인 큐 배치 업로드 (INFER-005). 멱등성 키로 중복 차단, 단말 결과 그대로 저장.

    이미지는 일부 항목(불량 + 양품 10% 샘플)만 동봉되므로 메타와 1:1이 아닐 수 있다.
    파일명(client_request_id)으로 이미지를 메타에 매칭한다. 비샘플링 양품은 메타만 동기화."""
    metas = json.loads(metadata)
    if len(metas) > 50:
        raise HTTPException(status_code=400, detail={"error": "BATCH_SIZE_LIMIT_EXCEEDED"})

    # 파일명(=client_request_id)으로 이미지 매핑
    images_by_crid: dict[str, UploadFile] = {}
    for f in images:
        name = f.filename or ""
        key = name[:-4] if name.endswith(".jpg") else name
        images_by_crid[key] = f

    results = []
    for meta in metas:
        crid = meta["client_request_id"]

        # 1) 멱등성 체크 — 같은 client_request_id 재전송 시 무시
        existing = (await db.execute(text("""
            SELECT 처리_결과 FROM 멱등성_요청 WHERE client_request_id = :rid
        """), {"rid": crid})).first()
        if existing is not None:
            results.append({"client_request_id": crid, "status": "skipped", "reason": "DUPLICATE"})
            continue

        try:
            # 2) 단말 추론 결과 사용 (서버 재추론 없음 — 단일 모델, 단말 자동 종결 완료)
            dev = meta.get("on_device_result") or {}
            defect_type = dev.get("defect_type", "미분류")
            confidence = float(dev.get("confidence", 0.0))
            top3 = dev.get("top3_predictions", [{"class": defect_type, "confidence": confidence}])
            inference_ms = int(dev.get("inference_ms", 0))
            is_defect = "양품" not in defect_type

            # 양품 10% 샘플(needs_sample)이고 이미지가 동봉됐으면 S3 재학습 데이터로 누적.
            # 그 외(불량 + 비샘플링 양품)는 단말 결과만 기록하고 이미지는 보관하지 않음.
            img_path = f"local://batch/{crid}.jpg"
            if (not is_defect) and meta.get("needs_sample") and crid in images_by_crid:
                data = await images_by_crid[crid].read()
                s3_key = await _put_sample_to_s3(data, defect_type)
                img_path = f"s3://{settings.S3_BUCKET}/{s3_key}"

            img_row = (await db.execute(text("""
                INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
                VALUES (:sid, :path, :ts)
                RETURNING 이미지_ID
            """), {"sid": meta["session_id"],
                   "path": img_path,
                   "ts": _parse_iso_naive(meta["captured_at"])})).first()
            image_id = img_row[0]

            res_row = (await db.execute(text("""
                INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
                    결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms, 결과_처리_상태)
                VALUES (:iid, :pid, '단말', true, :ok, :dtype, :conf,
                        CAST(:top3 AS JSONB), :ms, '완료')
                RETURNING 결과_ID
            """), {
                "iid": image_id, "pid": meta["process_id"], "ok": not is_defect,
                "dtype": defect_type, "conf": confidence,
                "top3": json.dumps(top3), "ms": inference_ms,
            })).first()

            await db.execute(text("""
                UPDATE 검사_세션
                   SET 총_이미지_수 = 총_이미지_수 + 1,
                       양품_수 = 양품_수 + :p,
                       불량_수 = 불량_수 + :d
                 WHERE 세션_ID = :sid
            """), {"sid": meta["session_id"],
                   "p": 0 if is_defect else 1,
                   "d": 1 if is_defect else 0})

            # 3) 멱등성 기록 — 재전송이 들어와도 중복 차단
            await db.execute(text("""
                INSERT INTO 멱등성_요청 (client_request_id, 검사원_ID, 처리_결과)
                VALUES (:rid, :iid, :res)
            """), {"rid": crid, "iid": inspector_id,
                   "res": json.dumps({"status": "ok", "image_id": image_id})})

            results.append({
                "client_request_id": crid,
                "status": "success",
                "image_id": image_id,
                "server_result": {
                    "result_id": res_row[0],
                    "defect_type": defect_type,
                    "confidence": confidence,
                    "inference_ms": inference_ms,
                    "needs_human_review": False,
                },
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

import random
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.api.deps import get_current_inspector_id


router = APIRouter()

# 단일 통합 모델의 클래스 30개 (불량 19 + 양품 11) — 시드 데이터(`모델_레지스트리.클래스_라벨`)와 동일 순서
_CLASSES = [
    # 표면처리 (0~12)
    "균열-도장", "균열-보온재", "도장흐름-도장", "도막떨어짐-도장", "도막분리-도장",
    "스크래치-모재", "스크래치-도장", "스크래치-보온재", "보온재손상-보온재", "탱크클리닝불량-모재",
    "표면양품-모재", "표면양품-도장", "표면양품-보온재",
    # 용접 (13~15)
    "용접불량-조인트", "용접블로우홀-조인트", "용접양품-조인트",
    # 절단 (16~19)
    "절단불량-모재", "절단불량-보온재", "절단양품-모재", "절단양품-보온재",
    # 케이블 (20~25)
    "케이블설치불량-케이블그랜드", "케이블손상-케이블", "바인딩불량-케이블타이",
    "케이블설치양품-케이블그랜드", "케이블양품-케이블", "바인딩양품-케이블타이",
    # 파이프 (26~27)
    "볼트체결불량-파이프", "볼트체결양품-파이프",
    # 폼스프레이 (28~29)
    "폼스프레이불량-우레탄폼", "폼스프레이양품-우레탄폼",
]


def _is_defect(label: str) -> bool:
    return "양품" not in label  # 통합 30클래스 공통 — 클래스명에 "양품" 포함 여부


@router.post("/inspect")
async def inspect(
    image: UploadFile = File(...),
    session_id: int = Form(...),
    process_id: int = Form(...),
    tank_type: str = Form(...),
    sector: str | None = Form(default=None),
    subsector: str | None = Form(default=None),
    on_device_result: str | None = Form(default=None),   # JSON 문자열 (옵션)
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    # 1) 이미지 저장 (MVP: 로컬 디스크. 14번에서 S3로)
    file_uuid = uuid.uuid4().hex
    local_path = f"local://uploads/{file_uuid}.jpg"
    # 실제 디스크 저장은 14번에서 보강. 지금은 경로 메타만 기록.

    # 2) 더미 분류 (랜덤)
    # 30클래스 가중치: 불량 19개=1, 양품 11개=3 (양품 비중 ↑로 실제 분포 시뮬)
    _WEIGHTS = [3 if "양품" in c else 1 for c in _CLASSES]
    top1 = random.choices(_CLASSES, weights=_WEIGHTS)[0]
    conf = round(random.uniform(0.55, 0.99), 3)
    top3 = [{"class": top1, "confidence": conf}]
    for c in random.sample([x for x in _CLASSES if x != top1], 2):
        top3.append({"class": c, "confidence": round(random.uniform(0.01, 0.30), 3)})
    is_defect_flag = _is_defect(top1)

    # 3) 검사_이미지 INSERT
    img_row = (await db.execute(text("""
        INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
        VALUES (:sid, :path, NOW())
        RETURNING 이미지_ID
    """), {"sid": session_id, "path": local_path})).first()
    image_id = img_row[0]

    # 4-a) 단말 결과 INSERT (on_device_result가 있을 때)
    if on_device_result:
        import json as _json
        dev = _json.loads(on_device_result)
        await db.execute(text("""
            INSERT INTO 검사_결과 (
                이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
                결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms,
                사람_재확인_필요, 결과_처리_상태
            ) VALUES (
                :iid, :pid, '단말', false, :ok,
                :dtype, :conf, CAST(:top3 AS JSONB), :ms,
                false, '완료'
            )
        """), {
            "iid": image_id, "pid": process_id,
            "ok": "양품" in dev.get("defect_type", ""),
            "dtype": dev.get("defect_type", ""),
            "conf": dev.get("confidence", 0),
            "top3": _json.dumps(dev.get("top3_predictions", [])),
            "ms": dev.get("inference_ms", 0),
        })

    # 4-b) 검사_결과 INSERT (서버 결과, 대표=true)
    res_row = (await db.execute(text("""
        INSERT INTO 검사_결과 (
            이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
            결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms,
            사람_재확인_필요, 결과_처리_상태
        ) VALUES (
            :iid, :pid, '서버', true, :ok,
            :dtype, :conf, CAST(:top3 AS JSONB), :ms,
            :review, '미완료'
        ) RETURNING 결과_ID
    """), {
        "iid": image_id, "pid": process_id, "ok": not is_defect_flag,
        "dtype": top1, "conf": conf, "top3": __import__("json").dumps(top3),
        "ms": random.randint(900, 1500), "review": conf < 0.70,
    })).first()
    result_id = res_row[0]

    # 5) 세션 카운터 UPDATE
    await db.execute(text("""
        UPDATE 검사_세션 SET 총_이미지_수 = 총_이미지_수 + 1,
                          양품_수 = 양품_수 + :p,
                          불량_수 = 불량_수 + :d
        WHERE 세션_ID = :sid
    """), {"sid": session_id, "p": 0 if is_defect_flag else 1, "d": 1 if is_defect_flag else 0})

    await db.commit()

    return {
        "image_id": image_id,
        "server_result": {
            "result_id": result_id,
            "defect_type": top1,
            "confidence": conf,
            "inference_ms": random.randint(900, 1500),
            "needs_human_review": conf < 0.70,
        },
        "heatmap_url": None,    # 14번에서 채움
        "action_guide": {
            "recommendation_id": None,
            "summary": "[MVP 더미] 분석 가이드는 14번 단계에서 RAG로 생성됩니다.",
            "detail": "현재는 더미 응답입니다.",
            "source_manuals": [],
        },
    }


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
    images: list[UploadFile] = File(...),
    metadata: str = Form(...),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    import json
    metas = json.loads(metadata)
    if len(metas) != len(images):
        raise HTTPException(status_code=400, detail={"error": "METADATA_IMAGE_COUNT_MISMATCH"})
    if len(metas) > 50:
        raise HTTPException(status_code=400, detail={"error": "BATCH_SIZE_LIMIT_EXCEEDED"})

    results = []
    for img_file, meta in zip(images, metas):
        try:
            _WEIGHTS = [3 if "양품" in c else 1 for c in _CLASSES]
            top1 = random.choices(_CLASSES, weights=_WEIGHTS)[0]
            conf = round(random.uniform(0.55, 0.99), 3)
            is_defect_flag = _is_defect(top1)

            img_row = (await db.execute(text("""
                INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
                VALUES (:sid, :path, NOW())
                RETURNING 이미지_ID
            """), {"sid": meta["session_id"], "path": f"local://batch/{meta['client_request_id']}.jpg"})).first()
            image_id = img_row[0]

            res_row = (await db.execute(text("""
                INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
                    결함_유형, 신뢰도_점수, 추론_지연_ms, 결과_처리_상태)
                VALUES (:iid, :pid, '서버', true, :ok, :dtype, :conf, :ms, '미완료')
                RETURNING 결과_ID
            """), {
                "iid": image_id, "pid": meta["process_id"], "ok": not is_defect_flag,
                "dtype": top1, "conf": conf, "ms": random.randint(900, 1500),
            })).first()

            await db.execute(text("""
                UPDATE 검사_세션 SET 총_이미지_수 = 총_이미지_수 + 1,
                                  양품_수 = 양품_수 + :p,
                                  불량_수 = 불량_수 + :d
                WHERE 세션_ID = :sid
            """), {"sid": meta["session_id"], "p": 0 if is_defect_flag else 1, "d": 1 if is_defect_flag else 0})

            results.append({
                "client_request_id": meta["client_request_id"],
                "status": "success",
                "image_id": image_id,
                "server_result": {"result_id": res_row[0], "defect_type": top1, "confidence": conf,
                                  "inference_ms": random.randint(900, 1500), "needs_human_review": False},
            })
        except Exception as e:
            results.append({"client_request_id": meta["client_request_id"], "status": "failed",
                            "error_code": "INFERENCE_ERROR", "error_message": str(e)})

    await db.commit()
    success_count = sum(1 for r in results if r["status"] == "success")
    return {
        "batch_size": len(metas),
        "succeeded_count": success_count,
        "failed_count": len(metas) - success_count,
        "results": results,
    }

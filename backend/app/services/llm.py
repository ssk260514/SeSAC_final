import json
from openai import AsyncOpenAI
from app.core.config import settings


_client_singleton: AsyncOpenAI | None = None


def get_llm_client() -> AsyncOpenAI:
    global _client_singleton
    if _client_singleton is None:
        _client_singleton = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
    return _client_singleton


async def generate_action_guide(defect_type: str, manuals: list[dict]) -> dict:
    manuals_text = "\n\n".join([
        f"[매뉴얼 {i+1} - {m['title']}, p.{m['page']}]\n{m['content']}"
        for i, m in enumerate(manuals)
    ])

    prompt = f"""당신은 선박 LNG 탱크 검사 보조 AI입니다. 검사원이 발견한 결함에 대한 조치 가이드를 생성합니다.

발견된 결함: {defect_type}

참고 매뉴얼:
{manuals_text}

위 매뉴얼을 종합하여 다음 JSON 형식으로 출력하세요. 매뉴얼에 없는 내용은 추측하지 말고, 매뉴얼의 절차를 충실히 따르세요.

{{
  "summary": "한 줄 요약 (50자 이내)",
  "detail": "단계별 상세 조치 (번호 매김, 4~6단계, 각 단계는 짧고 명확하게)"
}}

JSON 외 다른 텍스트는 절대 출력하지 마세요."""

    res = await get_llm_client().chat.completions.create(
        model="gpt-4o-mini",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
    )
    raw = res.choices[0].message.content.strip()
    guide = json.loads(raw)
    if isinstance(guide.get("detail"), list):
        guide["detail"] = "\n".join(guide["detail"])
    return guide

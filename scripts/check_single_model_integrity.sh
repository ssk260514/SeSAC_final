#!/usr/bin/env bash
# ============================================================
# 단일 통합 모델(30클래스) 정합성 자동 회귀 검증 — bash 판
#
# 영향 분석서 `명세서/계획 변경 내용.md` §검증 + plan file 작업 1-A 의
# 검증 항목을 자동 grep 으로 회귀 검증.
# 위반 0건이면 exit 0, 1건이라도 있으면 위반 위치 출력 + exit 1.
#
# Windows PowerShell 동등본: scripts/check_single_model_integrity.ps1
# ============================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

violations=()
add_violation() { violations+=("  [$1] $2"); }

# 제외 경로 (사용자 결정 §C: 명세서/tutorial 완전 제외 등)
EXCLUDES=(
  --exclude-dir=.venv
  --exclude-dir=.dart_tool
  --exclude-dir=node_modules
  --exclude-dir=build
  --exclude-dir=.gradle
  --exclude="check_single_model_integrity.*"
)
EXCLUDE_PATHS=(
  ":(exclude)명세서/tutorial/*"
  ":(exclude)명세서/계획 변경 내용.md"
  ":(exclude)backend/app/SINGLE_MODEL_GUIDE.md"
  ":(exclude).claude/plans/*"
)

# 인코딩 안전을 위해 grep -RIn (UTF-8 가정)
scan() {
  local pattern="$1"
  local label="$2"
  shift 2
  local allow_patterns=("$@")

  # grep 출력: file:line:content
  local raw
  raw=$(grep -RIn -E "${EXCLUDES[@]}" \
        --include='*.md' --include='*.py' --include='*.dart' --include='*.sql' \
        --include='*.yaml' --include='*.yml' --include='*.ts' --include='*.tsx' \
        --include='*.js' \
        -- "$pattern" . 2>/dev/null || true)

  if [[ -z "$raw" ]]; then return; fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # 제외 경로 필터링
    local skip=false
    for ep in "명세서/tutorial/" "명세서/계획 변경 내용.md" \
              "backend/app/SINGLE_MODEL_GUIDE.md" ".claude/plans/"; do
      if [[ "$line" == ./*"$ep"* ]]; then skip=true; break; fi
    done
    $skip && continue

    # 허용 패턴 확인
    local allowed=false
    for ap in "${allow_patterns[@]}"; do
      if [[ "$line" =~ $ap ]]; then allowed=true; break; fi
    done
    $allowed && continue

    # file:line 만 추출
    local pos="${line%%:*}"
    local rest="${line#*:}"
    local lnum="${rest%%:*}"
    add_violation "$label" "${pos#./}:$lnum"
  done <<<"$raw"
}

echo "🔍 Single Model Integrity Check"
echo "   Project root: $PROJECT_ROOT"
echo ""

# Check 1: surface_v1
scan 'surface_v1' 'surface_v1' \
  '전면 폐기' \
  '→ best_model_v5' \
  '\(구버전\)' \
  'surface_v1 → '

# Check 2: '표면양품-' 접두사 하드코딩
scan "\.startsWith\(['\"]표면양품-" "startsWith('표면양품-')"
scan "\.startswith\(['\"]표면양품-" "startswith('표면양품-')"

# Check 3: ?process_id / ?process=surface
scan '\?process_id=' '?process_id='
scan '\?process=surface' '?process=surface'

# Check 4: 6공정 모델 분기
scan '공정별로 6개 모델' '공정별로 6개 모델'
scan '6공정 × 30' '6공정 × 30+유형'
scan '나머지 5공정.*학습' '나머지 5공정 학습'

# Check 5: 30클래스 정합 — "29":"폼스프레이양품-우레탄폼" 4곳 모두 존재
LABEL='폼스프레이양품-우레탄폼'
for f in \
  "backend/sql/002_seed.sql" \
  "tutorial/02_백엔드_기반_구축.md" \
  "tutorial/09_화면5_카메라_촬영.md" \
  "tutorial/14_2주차_백엔드_RAG_정밀분석.md"
do
  if [[ ! -f "$f" ]]; then
    add_violation "30클래스 정합 누락" "$f (파일 없음)"
    continue
  fi
  if ! grep -q "$LABEL" "$f"; then
    add_violation "30클래스 정합 누락" "$f (29번 라벨 '$LABEL' 없음)"
  fi
done

# Check 6: best_model_v5_datamatch_full 등장 확인
for f in \
  "backend/sql/002_seed.sql" \
  "tutorial/02_백엔드_기반_구축.md" \
  "tutorial/13_2주차_TFLite_단말_추론.md" \
  "tutorial/14_2주차_백엔드_RAG_정밀분석.md" \
  "tutorial/16_3주차_모델OTA_Firebase.md" \
  "inspection_app/SINGLE_MODEL_GUIDE.md" \
  "명세서/제품_정의서.md"
do
  if [[ ! -f "$f" ]]; then
    add_violation "best_model 누락" "$f (파일 없음)"
    continue
  fi
  if ! grep -q 'best_model_v5_datamatch_full' "$f"; then
    add_violation "best_model 누락" "$f (모델 파일명 없음)"
  fi
done

# Check 7: RAG 매뉴얼.공정_ID 조건 유지
declare -A RAG_OK=(
  ["backend/sql/001_schema.sql"]='idx_manual_process'
  ["명세서/기능_명세서.md"]='매뉴얼.*공정_ID|공정_ID.*매뉴얼|FROM 매뉴얼'
  ["명세서/schema_diagram.md"]='매뉴얼.*공정_ID|공정_ID.*매뉴얼'
)
for f in "${!RAG_OK[@]}"; do
  if [[ ! -f "$f" ]]; then
    add_violation "RAG 공정_ID 누락" "$f (파일 없음)"
    continue
  fi
  if ! grep -qE "${RAG_OK[$f]}" "$f"; then
    add_violation "RAG 공정_ID 누락" "$f (매뉴얼 공정_ID 조건/인덱스 없음)"
  fi
done

echo ""
if [[ ${#violations[@]} -eq 0 ]]; then
  echo "✅ All checks passed (0 violations)"
  echo "   - surface_v1 잔재: 0건"
  echo "   - startsWith('표면양품-') 하드코딩: 0건"
  echo "   - ?process_id / ?process=surface: 0건"
  echo "   - 공정별 6모델 분기 표현: 0건"
  echo "   - 30클래스 4자 정합 (sql/002·tutorial/02·09·14): OK"
  echo "   - best_model_v5_datamatch_full 7개 파일 존재: OK"
  echo "   - RAG 매뉴얼.공정_ID 조건 유지: OK"
  exit 0
else
  echo "❌ FAIL: ${#violations[@]} violations found"
  for v in "${violations[@]}"; do echo "$v"; done
  echo ""
  echo "📖 참고: 명세서/계획 변경 내용.md §검증, plan file 작업 1-A"
  exit 1
fi

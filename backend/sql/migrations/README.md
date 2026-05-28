# 마이그레이션 (기존 운영 DB 전용)

이 폴더의 스크립트는 **이미 운영 중인 DB**에만 수동 적용합니다.
신규 설치는 `sql/001_schema.sql` + `sql/002_seed.sql` 만으로 최신 상태가 됩니다.

> Postgres `docker-entrypoint-initdb.d`는 하위 디렉터리를 재귀 실행하지 않으므로,
> 이 폴더는 docker 첫 기동 시 자동 실행되지 않습니다. (docker-compose 수정 불필요)

## 적용 순서

| 파일 | 내용 | 비고 |
|---|---|---|
| `003_fix_class_labels.sql` | 모델_레지스트리 `클래스_라벨` 순서 정합 | 002_seed가 이미 올바른 값이므로 구버전 DB에만 필요 |
| `004_add_manual_guides.sql` | 매뉴얼 `조치_요약`·`조치_상세` 컬럼 추가 | `IF NOT EXISTS` — 재실행 안전 |
| `005_default_action_guide.sql` | 과거 결과에 조치_권고 backfill (1회용) | **선행 조건:** `scripts/seed_manuals.py`로 매뉴얼 테이블이 채워져 있어야 함 |

```bash
psql "$DATABASE_URL" -f 003_fix_class_labels.sql
psql "$DATABASE_URL" -f 004_add_manual_guides.sql
# seed_manuals.py 실행 후
psql "$DATABASE_URL" -f 005_default_action_guide.sql
```

import asyncio
import asyncpg

async def check():
    conn = await asyncpg.connect(
        'postgresql://inspection_user:inspection_pass_change_me@localhost:5432/inspection_db'
    )

    # 전체 세션 조회
    sessions = await conn.fetch(
        "SELECT * FROM 검사_세션 ORDER BY 세션_ID DESC LIMIT 5"
    )
    print("=== 세션 목록 ===")
    for r in sessions:
        print(dict(r))

    # inspector 1의 진행중 세션
    active = await conn.fetchrow(
        "SELECT 세션_ID, 탱크_타입, 세션_상태 FROM 검사_세션 WHERE 검사원_ID = 1 AND 세션_상태 = '진행중' ORDER BY 시작_일시 DESC LIMIT 1"
    )
    print("\n=== inspector 1 진행중 세션 ===")
    print(active)

    # 검사원 목록
    inspectors = await conn.fetch("SELECT * FROM 검사원")
    print("\n=== 검사원 목록 ===")
    for r in inspectors:
        print(dict(r))

    await conn.close()

asyncio.run(check())

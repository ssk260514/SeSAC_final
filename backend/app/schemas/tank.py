from pydantic import BaseModel
from typing import Any


class ProcessInfo(BaseModel):
    process_id: int
    process_name: str
    confidence_threshold: float | None = None
    defect_types: list[str] | None = None


class TankTypeOut(BaseModel):
    tank_type: str
    sectors: dict[str, list[str]]   # JSONB nested
    description: str | None
    process: ProcessInfo


class CreateSessionRequest(BaseModel):
    tank_type: str
    selected_sector: str
    selected_subsector: str


class CreateSessionResponse(BaseModel):
    session_id: int
    status: str
    started_at: str
    tank_type: str
    selected_sector: str
    selected_subsector: str
    process: ProcessInfo


class DailySessionExistsError(BaseModel):
    error: str = "DAILY_SESSION_EXISTS"
    message: str
    existing_session_id: int

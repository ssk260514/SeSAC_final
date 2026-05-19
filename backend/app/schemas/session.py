from pydantic import BaseModel


class SessionSummary(BaseModel):
    session_id: int
    tank_type: str
    started_at: str
    ended_at: str | None = None
    last_modified_at: str | None = None
    has_defect: bool


class DashboardSummary(BaseModel):
    session_number: int
    today_images: int
    today_pass_rate: float
    active_session_id: int | None
    recent_sessions: list[SessionSummary]

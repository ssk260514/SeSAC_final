from pydantic import BaseModel


class LoginRequest(BaseModel):
    inspector_id: int
    name: str
    password: str


class InspectorOut(BaseModel):
    inspector_id: int
    name: str
    department: str | None


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    inspector: InspectorOut


class RefreshRequest(BaseModel):
    refresh_token: str


class RefreshResponse(BaseModel):
    access_token: str


class LogoutResponse(BaseModel):
    message: str
    logged_out_at: str

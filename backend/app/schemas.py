from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator

School = Literal["xorazm", "qashqadaryo", "surxondaryo", "qoraqalpogiston"]


class Body(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Login(Body):
    username: str = Field(min_length=3, max_length=120, pattern=r"^[a-zA-Z0-9_.@+-]+$")
    password: str = Field(min_length=1, max_length=128)
    otp: str = Field(default="", max_length=6)


class Register(Body):
    username: str = Field(min_length=3, max_length=120, pattern=r"^[a-zA-Z0-9_.@+-]+$")
    name: str = Field(min_length=2, max_length=160)
    password: str = Field(min_length=12, max_length=128)


class Refresh(Body):
    refresh_token: str = Field(min_length=20, max_length=200)


class UserPatch(Body):
    active: bool
    role: Literal["user", "teacher"]


class Upload(Body):
    recording_id: str = Field(min_length=8, max_length=100, pattern=r"^[a-zA-Z0-9_-]+$")
    size: int = Field(gt=44, le=120 * 1024 * 1024)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    mime: Literal["audio/wav", "audio/mp4"]


class Complete(Body):
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")


class Analyze(Body):
    asset_id: str
    school: School
    locale: Literal["uz", "kaa", "en"] = "uz"
    reference_id: str | None = None
    consent_version: Literal["analysis-v1"]


class Reference(Body):
    title: str = Field(min_length=2, max_length=200)
    master: str = Field(min_length=2, max_length=160)
    school: School
    asset_id: str
    license_note: str = Field(min_length=10, max_length=5000)
    license_until: int
    active: bool = False


class Content(Body):
    kind: Literal["lesson", "news", "event", "master", "gallery", "exercise"]
    title: str = Field(min_length=2, max_length=200)
    body: str = Field(min_length=1, max_length=20000)
    url: str | None = Field(default=None, max_length=2000)
    published: bool = False

    @field_validator("url")
    @classmethod
    def secure_url(cls, v):
        if v and not v.startswith("https://"):
            raise ValueError("HTTPS required")
        return v


class Policy(Body):
    version: int = Field(ge=1)
    registration: bool
    maintenance: bool
    banner: str = Field(max_length=1000)
    retention_days: int = Field(ge=1, le=365)
    daily_job_limit: int = Field(ge=1, le=200)
    minimum_app_version: str = Field(pattern=r"^\d+\.\d+\.\d+$")


class Review(Body):
    score: float = Field(ge=0, le=100, allow_inf_nan=False)
    note: str = Field(min_length=5, max_length=5000)


class Practice(Body):
    day: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    minutes: int = Field(ge=1, le=120)
    note: str = Field(default="", max_length=500)


class Group(Body):
    title: str = Field(min_length=2, max_length=160)
    teacher_id: str


class Member(Body):
    user_id: str


class Assignment(Body):
    title: str = Field(min_length=2, max_length=200)
    instructions: str = Field(min_length=2, max_length=5000)
    due: int


class Submit(Body):
    report_id: str


class Consent(Body):
    enabled: bool


class Password(Body):
    old_password: str = Field(max_length=128)
    new_password: str = Field(min_length=12, max_length=128)

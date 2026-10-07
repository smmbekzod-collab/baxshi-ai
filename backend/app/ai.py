"""Optional server-side AI coach. API keys are encrypted at rest; audio never leaves our worker."""
import hashlib
import json
import re
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import Field, field_validator, SecretStr
from cryptography.fernet import Fernet, InvalidToken
from .db import objects, one, add, audit
from .security import db, admin, current, limit
from .schemas import Body
from .media import require
from .learning import can_review

r = APIRouter(prefix="/v1")
CONFIG_ID = hashlib.sha256(b"baxshi-ai:ai-provider-config:v1").hexdigest()[:32]
PROVIDERS = {"xai", "gemini", "openai", "local"}
DEFAULT_MODEL = {"xai": "", "gemini": "", "openai": "", "local": ""}

class ProviderConfig(Body):
    provider: str = Field(min_length=3, max_length=12)
    model: str = Field(default="", max_length=120)
    enabled: bool = False
    api_key: SecretStr | None = Field(default=None, max_length=4096)
    clear_api_key: bool = False

    @field_validator("provider")
    @classmethod
    def valid_provider(cls, value):
        if value not in PROVIDERS: raise ValueError("unsupported_provider")
        return value
    @field_validator("api_key")
    @classmethod
    def valid_api_key(cls, value):
        raw = value.get_secret_value() if value is not None else None
        if raw is not None and (not raw.isascii() or any(ord(char) < 33 or ord(char) > 126 for char in raw)):
            raise ValueError("invalid_api_key_format")
        return value

    @field_validator("model", mode="before")
    @classmethod
    def trim_model(cls, value):
        value = value.strip() if isinstance(value, str) else value
        if value and not re.fullmatch(r"[A-Za-z0-9._:-]{1,120}", value): raise ValueError("invalid_model_id")
        return value


def _state(c):
    row = one(c, objects, objects.c.id == CONFIG_ID)
    return row["data"] if row and row["kind"] == "ai_provider_config" else {"provider":"local","model":"","enabled":False,"api_key_encrypted":None}

def _public(data):
    return {"provider":data["provider"],"model":data["model"],"enabled":data["enabled"],"key_configured":bool(data.get("api_key_encrypted"))}

def _key(data, settings):
    try: return Fernet(settings["key"].encode()).decrypt(data["api_key_encrypted"].encode()).decode() if data.get("api_key_encrypted") else None
    except (InvalidToken, ValueError): raise HTTPException(503,"ai_secret_unavailable")

def _prompt(report):
    metrics=[{"name":m.get("kind"),"score":m.get("score"),"reason":m.get("reason")} for m in report.get("metrics",[])]
    # Only anonymous acoustic estimates are shared. No audio, account ID, or profile information.
    return "O‘zbek tilida 3–5 aniq, muloyim mashq tavsiyasi yozing. Mavjud bo‘lmagan (null) metrikani baholamang va foiz to‘qimang. Bu avtomatik taxmin, ustoz bahosining o‘rnini bosmaydi. Faqat quyidagi akustik ma’lumotlardan foydalaning: " + json.dumps({"school":report.get("school"),"metrics":metrics,"quality":report.get("quality",{})},ensure_ascii=False,separators=(",",":"))

def _generate(provider, model, key, prompt, *, ping=False):
    model=model or DEFAULT_MODEL.get(provider,"")
    if provider in ("xai","openai"):
        base="https://api.x.ai/v1/chat/completions" if provider=="xai" else "https://api.openai.com/v1/chat/completions"
        body={"model":model,"messages":[{"role":"user","content":"Reply with exactly: OK" if ping else prompt}],"max_tokens":8 if ping else 320,"temperature":0.2}
        response=httpx.post(base,headers={"Authorization":"Bearer "+key,"Content-Type":"application/json"},json=body,timeout=15,follow_redirects=False)
        response.raise_for_status(); text=response.json()["choices"][0]["message"]["content"]
    elif provider=="gemini":
        if not model: raise ValueError("model_required")
        url="https://generativelanguage.googleapis.com/v1beta/models/"+model+":generateContent"
        body={"contents":[{"parts":[{"text":"Reply with exactly: OK" if ping else prompt}]}],"generationConfig":{"maxOutputTokens":8 if ping else 320,"temperature":0.2}}
        response=httpx.post(url,headers={"x-goog-api-key":key,"Content-Type":"application/json"},json=body,timeout=15,follow_redirects=False)
        response.raise_for_status(); text=response.json()["candidates"][0]["content"]["parts"][0]["text"]
    else: raise ValueError("provider_disabled")
    text=re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]","",str(text)).strip()
    if not text or len(text)>5000: raise ValueError("invalid_provider_response")
    return text

@r.get("/admin/ai-provider")
def get_config(_u=Depends(admin), c=Depends(db)):
    return _public(_state(c))

@r.put("/admin/ai-provider")
def set_config(b:ProviderConfig, request:Request, u=Depends(admin), c=Depends(db)):
    old=_state(c)
    encrypted=old.get("api_key_encrypted")
    value=b.api_key.get_secret_value().strip() if b.api_key else ""
    if b.provider != old["provider"] and not value:
        encrypted=None
    if value: encrypted=Fernet(request.app.state.settings["key"].encode()).encrypt(value.encode()).decode()
    if b.clear_api_key: encrypted=None
    if b.provider=="local":
        encrypted=None
        b.enabled=False
    if b.enabled and (not b.model or not encrypted): raise HTTPException(422,"ai_provider_requires_model_and_key")
    data={"provider":b.provider,"model":b.model,"enabled":b.enabled,"api_key_encrypted":encrypted}
    row=one(c,objects,objects.c.id==CONFIG_ID,True)
    if row:
        c.execute(objects.update().where(objects.c.id==CONFIG_ID).values(data=data,version=row["version"]+1))
    else: add(c,"ai_provider_config",u["id"],data,CONFIG_ID)
    audit(c,u["id"],"ai_provider_updated",b.provider,{"enabled":b.enabled,"key_changed":bool(value or b.clear_api_key)})
    return _public(data)

@r.post("/admin/ai-provider/test")
def test_config(request:Request, u=Depends(admin), c=Depends(db)):
    limit(c,"ai-provider-test:"+u["id"],5)
    data=_state(c); key=_key(data,request.app.state.settings)
    if not key or data["provider"]=="local" or not data.get("model"): raise HTTPException(409,"ai_provider_not_configured")
    try: text=_generate(data["provider"],data["model"],key,"",ping=True)
    except Exception: raise HTTPException(502,"ai_provider_connection_failed")
    return {"ok":True,"provider":data["provider"],"response":text[:80]}

@r.post("/reports/{report_id}/coach-ai")
def coach(report_id:str,request:Request,u=Depends(current),c=Depends(db)):
    row=require(one(c,objects,objects.c.id==report_id))
    if row["kind"]!="report" or (row["owner"]!=u["id"] and not can_review(c,u,row["owner"])): raise HTTPException(404,"not_found")
    report=row["data"]; data=_state(c)
    if not data.get("enabled") or data["provider"]=="local" or not data.get("api_key_encrypted"):
        return {"enhanced":False,"provider":"local","text":report.get("coach_text","Tahlil yakunlandi. Ustoz bilan muhokama qiling."),"notice":"AI API sozlanmagan; lokal tavsiya ko‘rsatildi."}
    limit(c,"ai-coach:"+u["id"],20)
    try: text=_generate(data["provider"],data["model"],_key(data,request.app.state.settings),_prompt(report))
    except Exception:
        return {"enhanced":False,"provider":"local","text":report.get("coach_text","Tahlil yakunlandi. Ustoz bilan muhokama qiling."),"notice":"AI API vaqtincha ishlamadi; lokal tavsiya ko‘rsatildi."}
    return {"enhanced":True,"provider":data["provider"],"text":text,"notice":"Avtomatik tavsiya. Akustik metrikalargina yuborildi; audio va shaxsiy ma’lumotlar yuborilmadi."}

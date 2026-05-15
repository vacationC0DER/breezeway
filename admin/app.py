"""
Breezeway Admin API — tenant + region provisioning for the vrgoals_V2 wizard.

Reference design: docs/plans/2026-05-15-breezeway-tenant-onboarding.md
Lives at: /root/Breezeway/admin/app.py on company-database
Runs as:  breezeway-admin.service on :8002 (FastAPI/uvicorn)

Endpoints
─────────
GET    /health
POST   /tenants                                     create/link tenant by id
POST   /tenants/{id}/regions                        provision region + creds
POST   /tenants/{id}/regions/{region_code}/launch   backfill + activate
GET    /tenants/{id}/status                         per-region etl_sync_log
"""

import logging
import os
import subprocess
from datetime import datetime
from typing import Optional

import psycopg2
import requests
from dotenv import dotenv_values
from fastapi import FastAPI, HTTPException, Request, status
from pydantic import BaseModel, Field

# ─── config ──────────────────────────────────────────────────────────────────
_ENV = dotenv_values(os.path.join(os.path.dirname(__file__), "..", ".env"))
DATABASE_URL = (
    f"postgresql://{_ENV.get('USER', 'breezeway')}:{_ENV.get('PASSWORD', '')}@"
    f"{_ENV.get('HOST', 'localhost')}:{_ENV.get('PORT', '5432')}/{_ENV.get('DB', 'breezeway')}"
    f"?sslmode=require&connect_timeout=10"
)
ADMIN_TOKEN = os.environ.get("BREEZEWAY_ADMIN_TOKEN", "").strip()
BREEZEWAY_AUTH_URL = "https://api.breezeway.io/public/auth/v1/"
ETL_RUNNER = "/root/Breezeway/etl/run_etl.py"
ETL_CWD = "/root/Breezeway"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("breezeway.admin")

if not ADMIN_TOKEN:
    log.warning("BREEZEWAY_ADMIN_TOKEN not set — admin endpoints will reject all requests")

app = FastAPI(title="Breezeway Admin API", version="1.0.0")


# ─── auth ────────────────────────────────────────────────────────────────────
@app.middleware("http")
async def require_admin_token(request: Request, call_next):
    if request.url.path == "/health" or request.method == "OPTIONS":
        return await call_next(request)
    provided = request.headers.get("X-Admin-Token", "")
    if not ADMIN_TOKEN or provided != ADMIN_TOKEN:
        log.warning("rejected %s %s from %s", request.method, request.url.path, request.client.host)
        return _json(401, {"error": "unauthorized"})
    return await call_next(request)


# ─── helpers ─────────────────────────────────────────────────────────────────
def _json(code: int, body: dict):
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=code, content=body)


def _db():
    return psycopg2.connect(DATABASE_URL)


def _mint_breezeway_token(client_id: str, client_secret: str) -> Optional[str]:
    """POST to Breezeway /auth/v1/. Returns access_token on success, None on failure."""
    try:
        r = requests.post(
            BREEZEWAY_AUTH_URL,
            headers={"accept": "application/json", "content-type": "application/json"},
            json={"client_id": client_id, "client_secret": client_secret},
            timeout=20,
        )
        if r.status_code == 200:
            return r.json().get("access_token")
        log.info("breezeway mint failed status=%s body=%s", r.status_code, r.text[:200])
        return None
    except requests.RequestException as e:
        log.warning("breezeway mint exception: %s", e)
        return None


# ─── schemas ─────────────────────────────────────────────────────────────────
class TenantCreate(BaseModel):
    id: int = Field(..., description="Supabase public.client.client_id integer")
    name: str
    status: str = "pending"


class RegionCreate(BaseModel):
    region_code: str = Field(..., pattern=r"^[a-z0-9_]+$", min_length=2, max_length=32)
    display_name: str
    breezeway_company_id: str
    breezeway_client_id: str
    breezeway_client_secret: str


# ─── routes ──────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "healthy", "service": "breezeway-admin", "timestamp": datetime.utcnow().isoformat()}


@app.post("/tenants", status_code=201)
def create_tenant(body: TenantCreate):
    """Idempotent on id. Returns the tenant row whether newly inserted or pre-existing."""
    with _db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO breezeway.tenants (id, name, status)
            VALUES (%s, %s, %s)
            ON CONFLICT (id) DO UPDATE
                SET name = EXCLUDED.name, updated_at = now()
            RETURNING id, name, status, created_at
            """,
            (body.id, body.name, body.status),
        )
        row = cur.fetchone()
    return {"id": row[0], "name": row[1], "status": row[2], "created_at": row[3].isoformat()}


@app.post("/tenants/{tenant_id}/regions", status_code=201)
def add_region(tenant_id: int, body: RegionCreate):
    """Validate Breezeway creds, then insert tenant_regions + api_tokens (active=false)."""
    # 1. validate creds before touching DB
    token = _mint_breezeway_token(body.breezeway_client_id, body.breezeway_client_secret)
    if not token:
        raise HTTPException(status_code=400, detail="Breezeway credentials failed validation")

    # 2. insert
    with _db() as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 FROM breezeway.tenants WHERE id = %s", (tenant_id,))
        if cur.fetchone() is None:
            raise HTTPException(status_code=404, detail=f"tenant {tenant_id} not found")

        cur.execute(
            """
            INSERT INTO breezeway.tenant_regions
                (region_code, tenant_id, display_name, breezeway_company_id, active)
            VALUES (%s, %s, %s, %s, false)
            ON CONFLICT (region_code) DO UPDATE
                SET tenant_id = EXCLUDED.tenant_id,
                    display_name = EXCLUDED.display_name,
                    breezeway_company_id = EXCLUDED.breezeway_company_id,
                    updated_at = now()
            RETURNING region_code, active
            """,
            (body.region_code, tenant_id, body.display_name, body.breezeway_company_id),
        )
        region_row = cur.fetchone()

        cur.execute(
            """
            INSERT INTO breezeway.api_tokens
                (region_code, client_id, client_secret, tenant_id, company_id, access_token, last_refreshed_at)
            VALUES (%s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (region_code) DO UPDATE
                SET client_id = EXCLUDED.client_id,
                    client_secret = EXCLUDED.client_secret,
                    tenant_id = EXCLUDED.tenant_id,
                    company_id = EXCLUDED.company_id,
                    access_token = EXCLUDED.access_token,
                    last_refreshed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP
            """,
            (
                body.region_code,
                body.breezeway_client_id,
                body.breezeway_client_secret,
                tenant_id,
                int(body.breezeway_company_id) if body.breezeway_company_id.isdigit() else None,
                token,
            ),
        )
    return {"region_code": region_row[0], "active": region_row[1], "validated": True}


@app.post("/tenants/{tenant_id}/regions/{region_code}/launch", status_code=202)
def launch_region(tenant_id: int, region_code: str):
    """Run `run_etl.py <region> all` in foreground; on success flip active=true.

    Synchronous: blocks for ~5–10 min while the backfill runs. Frontend should
    show a spinner + GET /tenants/{id}/status periodically.
    """
    with _db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT tr.region_code, tr.active, t.status
            FROM breezeway.tenant_regions tr
            JOIN breezeway.tenants t ON t.id = tr.tenant_id
            WHERE tr.region_code = %s AND tr.tenant_id = %s
            """,
            (region_code, tenant_id),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="region not found for this tenant")

    started = datetime.utcnow()
    proc = subprocess.run(
        ["python3", ETL_RUNNER, region_code, "all"],
        cwd=ETL_CWD,
        capture_output=True,
        text=True,
        timeout=20 * 60,
    )
    duration_s = (datetime.utcnow() - started).total_seconds()
    if proc.returncode != 0:
        log.error("launch failed region=%s rc=%s stderr=%s", region_code, proc.returncode, proc.stderr[-500:])
        raise HTTPException(
            status_code=500,
            detail={"ok": False, "rc": proc.returncode, "stderr_tail": proc.stderr[-500:]},
        )

    with _db() as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE breezeway.tenant_regions SET active = true, updated_at = now() WHERE region_code = %s",
            (region_code,),
        )
        cur.execute(
            "UPDATE breezeway.tenants SET status = 'active', updated_at = now() WHERE id = %s AND status != 'active'",
            (tenant_id,),
        )
    return {"ok": True, "region_code": region_code, "active": True, "duration_s": duration_s}


@app.get("/tenants/{tenant_id}/status")
def tenant_status(tenant_id: int):
    """Polling endpoint — returns 200 with tenant=null if tenant doesn't exist yet.

    This is called by the integrations index page on every load, so 404 would
    light up the browser console with a noisy network error before the user
    has even started the wizard.
    """
    with _db() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, name, status, created_at FROM breezeway.tenants WHERE id = %s",
            (tenant_id,),
        )
        t = cur.fetchone()
        if not t:
            return {"tenant": None, "regions": []}

        cur.execute(
            """
            SELECT tr.region_code, tr.display_name, tr.active, tr.breezeway_company_id,
                   esl.entity_type, esl.sync_status, esl.sync_completed_at,
                   esl.records_processed, esl.error_message
            FROM breezeway.tenant_regions tr
            LEFT JOIN breezeway.etl_sync_log esl ON esl.region_code = tr.region_code
            WHERE tr.tenant_id = %s
            ORDER BY tr.region_code, esl.entity_type
            """,
            (tenant_id,),
        )
        rows = cur.fetchall()

    regions: dict = {}
    for r in rows:
        rc = r[0]
        if rc not in regions:
            regions[rc] = {
                "region_code": rc,
                "display_name": r[1],
                "active": r[2],
                "breezeway_company_id": r[3],
                "entities": [],
            }
        if r[4]:
            regions[rc]["entities"].append({
                "entity_type": r[4],
                "sync_status": r[5],
                "sync_completed_at": r[6].isoformat() if r[6] else None,
                "records_processed": r[7],
                "error_message": r[8],
            })
    return {
        "tenant": {"id": t[0], "name": t[1], "status": t[2], "created_at": t[3].isoformat()},
        "regions": list(regions.values()),
    }

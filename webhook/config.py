"""
Configuration for Breezeway Webhook Receiver
"""

import os
from dotenv import dotenv_values

# Load environment from parent .env file
env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
envs = dict(dotenv_values(env_path))

# Server config
HOST = "0.0.0.0"
PORT = 8001

# Webhook authentication
WEBHOOK_SECRET = envs.get("WEBHOOK_SECRET", "").strip().strip('"')
if not WEBHOOK_SECRET:
    import logging as _log
    _log.getLogger(__name__).warning(
        "WEBHOOK_SECRET not configured - webhook endpoints are UNPROTECTED"
    )

# Database config
DATABASE_URL = (
    f"postgresql://{envs.get('USER', 'breezeway')}:{envs.get('PASSWORD', '')}@"
    f"{envs.get('HOST', 'localhost')}:{envs.get('PORT', '5432')}/{envs.get('DB', 'breezeway')}?sslmode=require&connect_timeout=10"
)

DB_SCHEMA = "breezeway"

# Company ID to region code mapping. Literal kept as fallback only.
# Source of truth is breezeway.tenant_regions (added 2026-05-15).
COMPANY_TO_REGION = {
    8558: "nashville",
    8561: "austin",
    8399: "smoky",
    12314: "hilton_head",
    10530: "breckenridge",
    14717: "sea_ranch",
    14720: "mammoth",
    8559: "hill_country"
}


# ----------------------------------------------------------------------------
# DB-driven webhook region lookup (added 2026-05-15)
# 60s in-process cache. Falls back to the literal above if DB unreachable.
# Returning "unknown" makes the handler skip processing safely (existing
# behavior for unknown company_ids — see handlers.py update_*_from_webhook).
# ----------------------------------------------------------------------------
import time as _time
import psycopg2 as _psycopg2

_COMPANY_CACHE: dict = {}
_COMPANY_CACHE_AT: float = 0.0
_COMPANY_CACHE_TTL_SEC = 60


def _load_company_to_region_from_db():
    try:
        with _psycopg2.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT breezeway_company_id, region_code "
                    "FROM breezeway.tenant_regions WHERE active = true"
                )
                return {int(row[0]): row[1] for row in cur.fetchall() if str(row[0]).isdigit()}
    except Exception as e:
        import logging as _logging
        _logging.getLogger(__name__).warning(f'tenant_regions lookup failed, using literal COMPANY_TO_REGION: {e}')
        return None


def get_region_by_company_id(company_id: int) -> str:
    """Get region code from company ID (DB-first, literal fallback)."""
    global _COMPANY_CACHE, _COMPANY_CACHE_AT
    now = _time.monotonic()
    if not _COMPANY_CACHE or (now - _COMPANY_CACHE_AT) >= _COMPANY_CACHE_TTL_SEC:
        db_map = _load_company_to_region_from_db()
        if db_map:
            _COMPANY_CACHE = db_map
            _COMPANY_CACHE_AT = now
    lookup = _COMPANY_CACHE if _COMPANY_CACHE else COMPANY_TO_REGION
    return lookup.get(company_id, "unknown")


# Thread-safe connection pool for webhook handlers
# (ThreadedConnectionPool required because uvicorn uses threads for sync handlers)
import logging
from psycopg2 import pool as pg_pool

_logger = logging.getLogger(__name__)

try:
    db_pool = pg_pool.ThreadedConnectionPool(
        minconn=2,
        maxconn=10,
        dsn=DATABASE_URL
    )
except Exception as e:
    _logger.error(f"Failed to initialize DB connection pool: {e}")
    db_pool = None

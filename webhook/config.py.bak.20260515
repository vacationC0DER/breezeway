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

# Company ID to region code mapping (reverse lookup)
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

def get_region_by_company_id(company_id: int) -> str:
    """Get region code from company ID"""
    return COMPANY_TO_REGION.get(company_id, "unknown")


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

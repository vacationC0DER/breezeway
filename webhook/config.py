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

# Database config
DATABASE_URL = (
    f"postgresql://{envs.get('USER', 'breezeway')}:{envs.get('PASSWORD', '')}@"
    f"{envs.get('HOST', 'localhost')}:{envs.get('PORT', '5432')}/{envs.get('DB', 'breezeway')}?sslmode=require"
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

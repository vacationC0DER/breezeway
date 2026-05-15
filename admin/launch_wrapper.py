#!/usr/bin/env python3
"""
Detached backfill wrapper. Spawned by admin/app.py via subprocess.Popen with
start_new_session=True so it outlives the API request.

On success: flips breezeway.tenant_regions.active = true + sets tenants.status = 'active'.
On failure: leaves active=false; the user can re-click Launch.

Usage: python3 launch_wrapper.py <region_code> <tenant_id>
"""

import os
import subprocess
import sys
from datetime import datetime

import psycopg2
from dotenv import dotenv_values

if len(sys.argv) != 3:
    print(f"usage: {sys.argv[0]} <region_code> <tenant_id>", file=sys.stderr)
    sys.exit(2)

REGION = sys.argv[1]
TENANT_ID = int(sys.argv[2])
ROOT = "/root/Breezeway"

env = dotenv_values(os.path.join(ROOT, ".env"))
DSN = (
    f"postgresql://{env['USER']}:{env['PASSWORD']}@"
    f"{env['HOST']}:{env['PORT']}/{env['DB']}?sslmode=require&connect_timeout=10"
)


def log(msg: str) -> None:
    ts = datetime.utcnow().isoformat()
    print(f"[{ts}] {REGION}: {msg}", flush=True)


log(f"backfill starting (tenant_id={TENANT_ID})")
proc = subprocess.run(
    ["python3", f"{ROOT}/etl/run_etl.py", REGION, "all"],
    cwd=ROOT,
    capture_output=False,
)
log(f"backfill exit rc={proc.returncode}")

if proc.returncode == 0:
    with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE breezeway.tenant_regions SET active = true, updated_at = now() "
            "WHERE region_code = %s",
            (REGION,),
        )
        cur.execute(
            "UPDATE breezeway.tenants SET status = 'active', updated_at = now() "
            "WHERE id = %s AND status != 'active'",
            (TENANT_ID,),
        )
    log("flipped active=true")
else:
    log("backfill failed — region remains active=false")

sys.exit(proc.returncode)

"""
Real-time push of Breezeway property-status events to the VR Goals Supabase
project (public.bz_property_status). Best-effort: every failure is logged and
swallowed so it can never block the webhook's 200 ack to Breezeway.

Activation: set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in /root/Breezeway/.env.
Until both are present, supabase_enabled() is False and push_property_status()
is a no-op (the webhook behaves exactly as before).

The service_role key bypasses RLS; client_id is resolved server-side by the
bz_set_client_id_from_region trigger (region_code -> bz_region_client_map).
"""

import os
import logging
from datetime import datetime, timezone

import requests
from dotenv import dotenv_values

logger = logging.getLogger(__name__)

_ENV = dotenv_values(os.path.join(os.path.dirname(__file__), '..', '.env'))
SUPABASE_URL = (_ENV.get('SUPABASE_URL') or os.environ.get('SUPABASE_URL') or '').rstrip('/')
SUPABASE_SERVICE_ROLE_KEY = (_ENV.get('SUPABASE_SERVICE_ROLE_KEY')
                             or os.environ.get('SUPABASE_SERVICE_ROLE_KEY') or '')

_SCHEMA = 'tasks'          # bz_property_status lives in the Supabase `tasks` schema
_TABLE = 'bz_property_status'
_CONFLICT = 'region_code,breezeway_property_id'
_TIMEOUT = 8


def supabase_enabled() -> bool:
    return bool(SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY)


def _count_blocking(sub_statuses) -> int:
    """Count blocking sub-statuses and blocking tasks in the payload."""
    blocking = 0
    if isinstance(sub_statuses, list):
        for s in sub_statuses:
            if not isinstance(s, dict):
                continue
            if s.get('is_blocking'):
                blocking += 1
            for t in (s.get('tasks') or []):
                if isinstance(t, dict) and t.get('is_blocking'):
                    blocking += 1
    return blocking


def push_property_status(payload: dict, region_code: str, event_id=None) -> bool:
    """UPSERT one property-status event into Supabase. Returns True on success."""
    if not supabase_enabled():
        logger.debug('Supabase sync disabled (SUPABASE_URL/SERVICE_ROLE_KEY unset)')
        return False

    property_id = str(payload.get('property_id', payload.get('id', '')) or '')
    if not property_id or region_code in (None, '', 'unknown'):
        logger.warning(
            f'Supabase push skipped: unresolved property/region '
            f'(property_id={property_id!r}, region={region_code!r})'
        )
        return False

    sub_statuses = payload.get('sub_statuses')
    blocking_count = _count_blocking(sub_statuses)
    now_iso = datetime.now(timezone.utc).isoformat()

    row = {
        'region_code': region_code,
        'breezeway_property_id': property_id,
        'external_property_id': payload.get('external_property_id'),
        'status': payload.get('status'),
        'is_blocking': blocking_count > 0,
        'blocking_count': blocking_count,
        'sub_statuses': sub_statuses,
        'status_changed_at': now_iso,
        'event_id': str(event_id) if event_id is not None else None,
        'raw_payload': payload,
        'received_at': now_iso,
    }

    url = f"{SUPABASE_URL}/rest/v1/{_TABLE}?on_conflict={_CONFLICT}"
    headers = {
        'apikey': SUPABASE_SERVICE_ROLE_KEY,
        'Authorization': f'Bearer {SUPABASE_SERVICE_ROLE_KEY}',
        'Content-Type': 'application/json',
        'Content-Profile': _SCHEMA,   # target the `tasks` schema, not public
        'Prefer': 'resolution=merge-duplicates,return=minimal',
    }

    try:
        resp = requests.post(url, json=row, headers=headers, timeout=_TIMEOUT)
        if resp.status_code >= 300:
            logger.error(f'Supabase push failed [{resp.status_code}]: {resp.text[:300]}')
            return False
        logger.info(f'Supabase push ok: {region_code}/{property_id} -> {payload.get("status")}')
        return True
    except Exception as e:  # noqa: BLE001 - never propagate
        logger.error(f'Supabase push error: {e}')
        return False

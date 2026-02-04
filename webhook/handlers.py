"""
Webhook event handlers for Breezeway
"""

import logging
from datetime import datetime
from typing import Dict, Any, Optional
import psycopg2
from psycopg2.extras import Json

from .config import DATABASE_URL, DB_SCHEMA, get_region_by_company_id

logger = logging.getLogger(__name__)


def get_db_connection():
    """Get database connection"""
    return psycopg2.connect(DATABASE_URL)


def log_webhook_event(
    webhook_type: str,
    payload: Dict[str, Any],
    company_id: Optional[int] = None,
    entity_id: Optional[str] = None,
    event_action: Optional[str] = None
) -> int:
    """
    Log webhook event to database
    
    Returns:
        Event ID
    """
    region_code = get_region_by_company_id(company_id) if company_id else None
    
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                INSERT INTO {DB_SCHEMA}.webhook_events 
                    (webhook_type, region_code, company_id, payload, entity_id, event_action, received_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id
            """, (
                webhook_type,
                region_code,
                company_id,
                Json(payload),
                entity_id,
                event_action,
                datetime.now()
            ))
            event_id = cur.fetchone()[0]
            conn.commit()
            logger.info(f"Logged webhook event {event_id}: {webhook_type} for {region_code or 'unknown'}")
            return event_id
    finally:
        conn.close()


def mark_event_processed(event_id: int, error_message: Optional[str] = None):
    """Mark event as processed (or failed)"""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                UPDATE {DB_SCHEMA}.webhook_events
                SET processed = TRUE,
                    processed_at = %s,
                    error_message = %s
                WHERE id = %s
            """, (datetime.now(), error_message, event_id))
            conn.commit()
    finally:
        conn.close()


def process_property_status_event(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process property-status webhook event
    
    Expected payload structure (based on Breezeway docs):
    {
        "event": "property_status_changed",
        "company_id": 8558,
        "property_id": "12345",
        "status": "clean",
        "previous_status": "dirty",
        ...
    }
    """
    # Handle test event
    if payload.get("event") == "test_webhook_event":
        logger.info("Received test webhook event")
        return {"status": "ok", "message": "Test event received"}
    
    # Extract key fields
    company_id = payload.get("company_id")
    property_id = str(payload.get("property_id", payload.get("id", "")))
    event_action = payload.get("event", "property_status_changed")
    
    # Log the event
    event_id = log_webhook_event(
        webhook_type="property-status",
        payload=payload,
        company_id=company_id,
        entity_id=property_id,
        event_action=event_action
    )
    
    # Try to update the property in the database
    error_message = None
    try:
        update_property_from_webhook(payload)
    except Exception as e:
        error_message = str(e)
        logger.error(f"Failed to update property from webhook: {e}")
    
    mark_event_processed(event_id, error_message)
    
    return {"status": "ok", "event_id": event_id}


def process_task_event(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process task webhook event
    
    Expected payload structure:
    {
        "event": "task_created" | "task_updated" | "task_completed" | etc,
        "company_id": 8558,
        "task_id": "456",
        "task": { ... full task object ... }
    }
    """
    # Handle test event
    if payload.get("event") == "test_webhook_event":
        logger.info("Received test webhook event")
        return {"status": "ok", "message": "Test event received"}
    
    # Extract key fields
    company_id = payload.get("company_id")
    task_id = str(payload.get("task_id", payload.get("id", "")))
    event_action = payload.get("event", "task_updated")
    
    # Log the event
    event_id = log_webhook_event(
        webhook_type="task",
        payload=payload,
        company_id=company_id,
        entity_id=task_id,
        event_action=event_action
    )
    
    # Try to update the task in the database
    error_message = None
    try:
        update_task_from_webhook(payload)
    except Exception as e:
        error_message = str(e)
        logger.error(f"Failed to update task from webhook: {e}")
    
    mark_event_processed(event_id, error_message)
    
    return {"status": "ok", "event_id": event_id}


def update_property_from_webhook(payload: Dict[str, Any]):
    """Update property record from webhook payload"""
    company_id = payload.get("company_id")
    property_id = str(payload.get("property_id", payload.get("id", "")))
    region_code = get_region_by_company_id(company_id)
    
    if not property_id or region_code == "unknown":
        logger.warning(f"Cannot update property: missing property_id or unknown company_id {company_id}")
        return
    
    # Extract status if present
    new_status = payload.get("status")
    if not new_status:
        logger.info(f"No status in payload for property {property_id}, skipping update")
        return
    
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                UPDATE {DB_SCHEMA}.properties
                SET property_status = %s,
                    synced_at = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE property_id = %s AND region_code = %s
            """, (new_status, datetime.now(), property_id, region_code))
            
            if cur.rowcount > 0:
                logger.info(f"Updated property {property_id} status to {new_status}")
            else:
                logger.warning(f"Property {property_id} not found in region {region_code}")
            
            conn.commit()
    finally:
        conn.close()


def update_task_from_webhook(payload: Dict[str, Any]):
    """Update task record from webhook payload"""
    company_id = payload.get("company_id")
    task_id = str(payload.get("task_id", payload.get("id", "")))
    region_code = get_region_by_company_id(company_id)
    
    if not task_id or region_code == "unknown":
        logger.warning(f"Cannot update task: missing task_id or unknown company_id {company_id}")
        return
    
    # Get task data (might be nested under "task" key or at root)
    task_data = payload.get("task", payload)
    
    # Extract key fields to update
    new_status = task_data.get("status")
    finished_at = task_data.get("finished_at")
    started_at = task_data.get("started_at")
    
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            # Build dynamic update
            updates = ["synced_at = %s", "updated_at = CURRENT_TIMESTAMP"]
            values = [datetime.now()]
            
            if new_status:
                updates.append("task_status = %s")
                values.append(new_status)
            if finished_at:
                updates.append("finished_at = %s")
                values.append(finished_at)
            if started_at:
                updates.append("started_at = %s")
                values.append(started_at)
            
            values.extend([task_id, region_code])
            
            cur.execute(f"""
                UPDATE {DB_SCHEMA}.tasks
                SET {", ".join(updates)}
                WHERE task_id = %s AND region_code = %s
            """, values)
            
            if cur.rowcount > 0:
                logger.info(f"Updated task {task_id} in region {region_code}")
            else:
                logger.warning(f"Task {task_id} not found in region {region_code}")
            
            conn.commit()
    finally:
        conn.close()

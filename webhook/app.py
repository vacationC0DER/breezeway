"""
Breezeway Webhook Receiver - FastAPI Application

Receives webhook events from Breezeway API for:
- property-status: Property status changes
- task: Task updates (created, updated, completed, etc.)
"""

import logging
from datetime import datetime
from typing import Dict, Any

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse

from .config import HOST, PORT
from .handlers import process_property_status_event, process_task_event

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Breezeway Webhook Receiver",
    description="Receives and processes webhook events from Breezeway API",
    version="1.0.0"
)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "breezeway-webhook-receiver",
        "timestamp": datetime.now().isoformat()
    }


@app.post("/webhook/property-status")
async def webhook_property_status(request: Request):
    """
    Receive property-status webhook events from Breezeway
    
    Expected to be called by Breezeway when property status changes.
    Must respond within 10 seconds with HTTP 2XX.
    """
    try:
        payload = await request.json()
        logger.info(f"Received property-status webhook: {payload.get('event', 'unknown')}")
        
        result = process_property_status_event(payload)
        return JSONResponse(content=result, status_code=200)
        
    except Exception as e:
        logger.error(f"Error processing property-status webhook: {e}", exc_info=True)
        # Still return 200 to acknowledge receipt (log the error internally)
        return JSONResponse(
            content={"status": "error", "message": str(e)},
            status_code=200
        )


@app.post("/webhook/task")
async def webhook_task(request: Request):
    """
    Receive task webhook events from Breezeway
    
    Expected to be called by Breezeway when tasks are created, updated, or completed.
    Must respond within 10 seconds with HTTP 2XX.
    """
    try:
        payload = await request.json()
        logger.info(f"Received task webhook: {payload.get('event', 'unknown')}")
        
        result = process_task_event(payload)
        return JSONResponse(content=result, status_code=200)
        
    except Exception as e:
        logger.error(f"Error processing task webhook: {e}", exc_info=True)
        # Still return 200 to acknowledge receipt
        return JSONResponse(
            content={"status": "error", "message": str(e)},
            status_code=200
        )


@app.get("/webhook/events")
async def list_recent_events(limit: int = 50):
    """List recent webhook events (for debugging/monitoring)"""
    from .handlers import get_db_connection
    from .config import DB_SCHEMA
    
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT id, event_id, webhook_type, region_code, entity_id, 
                       event_action, processed, received_at
                FROM {DB_SCHEMA}.webhook_events
                ORDER BY received_at DESC
                LIMIT %s
            """, (limit,))
            
            columns = [desc[0] for desc in cur.description]
            events = [dict(zip(columns, row)) for row in cur.fetchall()]
            
            # Convert datetime to string for JSON serialization
            for event in events:
                if event.get("received_at"):
                    event["received_at"] = event["received_at"].isoformat()
                if event.get("event_id"):
                    event["event_id"] = str(event["event_id"])
            
            return {"events": events, "count": len(events)}
    finally:
        conn.close()


# Entry point for running directly
if __name__ == "__main__":
    import uvicorn
    logger.info(f"Starting Breezeway Webhook Receiver on {HOST}:{PORT}")
    uvicorn.run(app, host=HOST, port=PORT)

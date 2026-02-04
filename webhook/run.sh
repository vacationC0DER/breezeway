#!/bin/bash
# Start Breezeway Webhook Receiver

cd /root/Breezeway

# Activate virtual environment if exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Start the webhook receiver
exec python3 -m uvicorn webhook.app:app --host 0.0.0.0 --port 8001 --log-level info

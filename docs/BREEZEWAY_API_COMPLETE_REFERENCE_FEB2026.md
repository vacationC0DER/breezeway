# Breezeway API Documentation - Complete GET Endpoints Reference

**Base URL:** `https://api.breezeway.io`

**Last Updated:** February 2026

---

## Table of Contents

1. [Authentication](#authentication)
2. [Property API - GET Endpoints](#property-api---get-endpoints)
3. [Reservation API - GET Endpoints](#reservation-api---get-endpoints)
4. [Task API - GET Endpoints](#task-api---get-endpoints)
5. [Supporting APIs - GET Endpoints](#supporting-apis---get-endpoints)
6. [Webhook Schemas](#webhook-schemas)
7. [Rate Limits & Best Practices](#rate-limits--best-practices)

---

## Key Discovery: Task Response Includes linked_reservation

The task response directly includes:
```json
"linked_reservation": {
  "id": "number",
  "external_reservation_id": "string (max 50, nullable)"
}
```

This means we can get task-reservation linkage directly from the task endpoint without needing to call /reservation/{id}/tasks separately.

---

## Full Documentation

[See original document for complete reference]

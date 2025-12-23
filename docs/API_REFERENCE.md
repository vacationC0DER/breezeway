# Breezeway API Documentation for Development

## Overview
The Breezeway API provides programmatic access to property management operations including properties, reservations, tasks, and company management. This documentation is optimized for development with Python.

## Base Configuration

### Base URLs
```
Auth API:      https://api.breezeway.io/public/auth/v1
Inventory API: https://api.breezeway.io/public/inventory/v1
```

### Authentication

#### Obtaining Client Credentials
See the [Breezeway docs on obtaining credentials](https://support.breezeway.com/hc/en-us/articles/360056442271) to provision required credentials. The provided client ID and client secret will be used to retrieve an access token for authorizing requests to the Breezeway platform.

#### Generating Access and Refresh Tokens
To generate your access and refresh token, perform a POST call to the auth endpoint with your client credentials:

```python
import requests

def get_tokens(client_id: str, client_secret: str) -> dict:
    """Generate access and refresh tokens from client credentials"""
    url = "https://api.breezeway.io/public/auth/v1/"
    headers = {
        "accept": "application/json",
        "content-type": "application/json"
    }
    data = {
        "client_id": client_id,
        "client_secret": client_secret
    }

    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()

    return response.json()
    # Returns: {"access_token": "...", "refresh_token": "..."}
```

**Important Notes:**
- Access tokens have a **24-hour lifetime**
- Refresh tokens have a **30-day lifetime**
- Tokens are JSON Web Tokens (JWTs)
- You can make as many requests as needed with one access token during its lifetime

#### Request Authentication
All API requests must include the access token in the Authorization header with the `JWT` scheme prefix:

```python
headers = {
    "accept": "application/json",
    "Authorization": f"JWT {access_token}"
}
```

#### Refreshing Access Tokens
Access tokens expire after 24 hours and must be refreshed. Use the refresh token to obtain new tokens:

```python
def refresh_tokens(refresh_token: str) -> dict:
    """Refresh access token using refresh token"""
    url = "https://api.breezeway.io/public/auth/v1/refresh"
    headers = {
        "accept": "application/json",
        "Authorization": f"JWT {refresh_token}"
    }

    response = requests.post(url, headers=headers)
    response.raise_for_status()

    return response.json()
    # Returns: {"access_token": "...", "refresh_token": "..."}
```

**Note:** Each call to refresh an access token provides a new refresh token. If your refresh token expires (after 30 days), you must generate new tokens using your client credentials.

### Rate Limits

**Authentication Endpoints:**
- `/auth/v1/` (generate tokens): **1 request per minute**
- `/auth/v1/refresh` (refresh tokens): **1 request per minute**

**Rate Limit Response:**
When the rate limit is hit, the API returns:
- HTTP Status: `429 Too Many Requests`
- Headers include rate limit expiration information
- Response body includes when the limit expires

```python
# Example rate limit response
{
    "error": "Rate limit exceeded",
    "retry_after": 60  # seconds until limit resets
}
```

**Best Practices:**
- Store tokens securely and reuse them for their full lifetime
- Do NOT request new tokens for each API call
- Implement token refresh logic before expiration (e.g., refresh after 23 hours)
- Handle 429 responses with exponential backoff

### Python Setup
```bash
python -m pip install requests python-dotenv
```

### Complete Authentication Client
```python
import requests
from datetime import datetime, timedelta
from typing import Optional
import time

class BreezewayAuth:
    def __init__(self, client_id: str, client_secret: str):
        self.client_id = client_id
        self.client_secret = client_secret
        self.access_token: Optional[str] = None
        self.refresh_token: Optional[str] = None
        self.token_expires_at: Optional[datetime] = None
        self.auth_base_url = "https://api.breezeway.io/public/auth/v1"

    def get_access_token(self) -> str:
        """Get valid access token, refreshing if necessary"""
        # Check if we have a valid token
        if self.access_token and self.token_expires_at:
            if datetime.now() < self.token_expires_at - timedelta(minutes=5):
                return self.access_token

        # Need to refresh or generate new token
        if self.refresh_token:
            try:
                self._refresh_tokens()
                return self.access_token
            except requests.exceptions.HTTPError:
                # Refresh failed, generate new tokens
                pass

        # Generate new tokens
        self._generate_tokens()
        return self.access_token

    def _generate_tokens(self):
        """Generate new access and refresh tokens"""
        url = f"{self.auth_base_url}/"
        headers = {
            "accept": "application/json",
            "content-type": "application/json"
        }
        data = {
            "client_id": self.client_id,
            "client_secret": self.client_secret
        }

        response = requests.post(url, headers=headers, json=data)

        # Handle rate limiting
        if response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
            response = requests.post(url, headers=headers, json=data)

        response.raise_for_status()

        tokens = response.json()
        self.access_token = tokens['access_token']
        self.refresh_token = tokens['refresh_token']
        self.token_expires_at = datetime.now() + timedelta(hours=24)

    def _refresh_tokens(self):
        """Refresh access token using refresh token"""
        url = f"{self.auth_base_url}/refresh"
        headers = {
            "accept": "application/json",
            "Authorization": f"JWT {self.refresh_token}"
        }

        response = requests.post(url, headers=headers)

        # Handle rate limiting
        if response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
            response = requests.post(url, headers=headers)

        response.raise_for_status()

        tokens = response.json()
        self.access_token = tokens['access_token']
        self.refresh_token = tokens['refresh_token']
        self.token_expires_at = datetime.now() + timedelta(hours=24)

# Usage
auth = BreezewayAuth(client_id="your_client_id", client_secret="your_client_secret")
access_token = auth.get_access_token()  # Automatically handles refresh
```

### Basic Request Template
```python
import requests

class BreezewayAPIClient:
    def __init__(self, auth: BreezewayAuth):
        self.auth = auth
        self.base_url = "https://api.breezeway.io/public/inventory/v1"

    def make_request(self, endpoint: str, params=None):
        """Make authenticated request to Breezeway API"""
        url = f"{self.base_url}/{endpoint}"
        headers = {
            "accept": "application/json",
            "Authorization": f"JWT {self.auth.get_access_token()}"
        }

        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        return response.json()

# Usage
auth = BreezewayAuth(client_id="your_client_id", client_secret="your_client_secret")
client = BreezewayAPIClient(auth)
properties = client.make_request("property", {"limit": 100})
```

---

## Properties API

### 1. List Properties
**Endpoint:** `GET /property`

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| company_id | int32 | - | Fetch properties for specific company (cross-company access required) |
| limit | int32 | 100 | Number of records per page |
| page | int32 | 1 | Page number to return |
| sort_by | string | created_at | Field to sort results by |
| sort_order | string | desc | Sort order: 'asc' or 'desc' |

**Python Implementation:**
```python
def list_properties(company_id=None, limit=100, page=1):
    params = {
        "limit": limit,
        "page": page,
        "sort_by": "created_at",
        "sort_order": "desc"
    }
    if company_id:
        params["company_id"] = company_id
    
    return make_request("property", params)
```

**Response Structure:**
```json
{
  "limit": 100,
  "page": 1,
  "total_pages": 1,
  "total_results": 2,
  "results": [
    {
      "id": 328858,
      "name": "Example property",
      "address1": "Example Address 123",
      "address2": "Unit 1",
      "building": null,
      "city": "example city",
      "state": "AL",
      "zipcode": "14100",
      "country": "us",
      "latitude": 32.3182314,
      "longitude": -86.902298,
      "company_id": 4,
      "status": "active",
      "display": "",
      "notes": {},
      "groups": [],
      "photos": [
        {
          "id": 1,
          "url": "http://breezeway.com/image.jpg",
          "default": true,
          "caption": "Kitchen doors",
          "original_url": ""
        }
      ],
      "reference_company_id": null,
      "reference_external_property_id": null,
      "reference_property_id": null
    }
  ]
}
```

---

## Reservations API

### 2. List Reservations
**Endpoint:** `GET /reservation`

**Default Behavior:** If no filters applied, returns reservations where `checkout_date >= today`

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| property_id | array[int32] | Filter by Breezeway property IDs |
| company_id | array[int32] | Filter by company IDs (cross-company access required) |
| checkin_date_lt | date | Check-in date less than specified date |
| checkin_date_le | date | Check-in date less than or equal to specified date |
| checkin_date_gt | date | Check-in date greater than specified date |
| checkin_date_ge | date | Check-in date greater than or equal to specified date |
| checkout_date_lt | date | Checkout date less than specified date |
| checkout_date_le | date | Checkout date less than or equal to specified date |
| checkout_date_gt | date | Checkout date greater than specified date |
| checkout_date_ge | date | Checkout date greater than or equal to specified date |
| created_at_lt | date | Creation date less than specified date-time |
| created_at_le | date | Creation date less than or equal to specified date-time |
| created_at_gt | date | Creation date greater than specified date-time |
| created_at_ge | date | Creation date greater than or equal to specified date-time |
| updated_at_lt | date | Last updated less than specified date-time |
| updated_at_le | date | Last updated less than or equal to specified date-time |
| updated_at_gt | date | Last updated greater than specified date-time |
| updated_at_ge | date | Last updated greater than or equal to specified date-time |
| limit | int32 | Number of records per page (default: 100) |
| page | int32 | Page to return (default: 1) |
| sort_by | string | Field to sort by (default: created_at) |
| sort_order | string | Sort order: 'asc' or 'desc' (default: desc) |

**Python Implementation:**
```python
def list_reservations(property_ids=None, checkin_date_ge=None, checkout_date_le=None, limit=100, page=1):
    params = {
        "limit": limit,
        "page": page,
        "sort_by": "created_at",
        "sort_order": "desc"
    }
    
    if property_ids:
        params["property_id"] = property_ids
    if checkin_date_ge:
        params["checkin_date_ge"] = checkin_date_ge
    if checkout_date_le:
        params["checkout_date_le"] = checkout_date_le
    
    return make_request("reservation", params)
```

**Response Structure:**
```json
{
  "limit": 100,
  "page": 1,
  "results": [
    {
      "id": 15486273,
      "property_id": 8542,
      "checkin_date": "2023-05-20",
      "checkin_time": "15:30:00",
      "checkin_early": null,
      "checkout_date": "2023-05-27",
      "checkout_time": "11:00:00",
      "checkout_late": null,
      "access_code": "8675309",
      "guide_url": "https://guide.breezeway.io/szwer",
      "guests": [
        {
          "first_name": "John",
          "last_name": "Doe",
          "emails": [],
          "phone_numbers": []
        }
      ],
      "note": null,
      "status": "active",
      "tags": [],
      "type_guest": {
        "code": "owner",
        "name": "Owner"
      },
      "type_stay": {
        "code": "owner",
        "name": "Owner"
      },
      "reference_external_property_id": null,
      "reference_property_id": null,
      "reference_reservation_id": null
    }
  ]
}
```

### 3. List Reservations by External ID
**Endpoint:** `GET /reservation/external-id`

**Note:** External ID is the listing_id from Guesty API

**Required Parameters:**
- `reference_property_id` (string): Property ID from external system

**Optional Parameters:**
- `reference_company_id` (string): Company ID from external system (required for cross-company access)
- All date filters from regular reservation listing

**Python Implementation:**
```python
def list_reservations_by_external_id(reference_property_id, reference_company_id=None):
    params = {"reference_property_id": reference_property_id}
    if reference_company_id:
        params["reference_company_id"] = reference_company_id
    
    return make_request("reservation/external-id", params)
```

### 4. Get Tasks for Reservation
**Endpoint:** `GET /reservation/{id}/tasks`

**Path Parameters:**
- `id` (int32): Reservation ID from Breezeway system

**Python Implementation:**
```python
def get_reservation_tasks(reservation_id):
    return make_request(f"reservation/{reservation_id}/tasks")
```

**Response Structure:**
```json
[
  {
    "id": 19078902,
    "name": "Departure Clean",
    "description": "Standard departure clean for guests",
    "type_department": "housekeeping",
    "type_priority": "normal",
    "type_task_status": {
      "code": "created",
      "name": "Created",
      "stage": "new"
    },
    "scheduled_date": "2022-06-25",
    "scheduled_time": null,
    "home_id": 16052,
    "template_id": 23027,
    "assignments": [],
    "supplies": [
      {
        "id": 1900498,
        "name": "8x14x1 Air Filters",
        "description": "1 inch air filter",
        "quantity": 3,
        "size": "6 7/8 x 15 7/8 x 1",
        "unit_cost": 50.7,
        "billable": false
      }
    ],
    "costs": [],
    "tags": [],
    "task_tags": [],
    "created_at": "2022-06-11T00:28:25",
    "updated_at": "2022-06-11T00:28:25+00:00",
    "started_at": null,
    "finished_at": null,
    "paused": false,
    "report_url": "https://portal.breezeway.io/task/report/71dd8dc8-2c04-4cdd-9aba-08d87d31cb08",
    "reference_property_id": ""
  }
]
```

---

## Tasks API

### 5. List Tasks
**Endpoint:** `GET /task/`

**Required Parameters (one of):**
- `home_id` (int32): Property ID from Breezeway system
- `reference_property_id` (string): Property ID from external system

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| reference_company_id | string | Company ID from external system (cross-company access) |
| type_department | string | Filter by department: 'maintenance', 'housekeeping', 'inspection' |
| scheduled_date | string | Date range (YYYY-MM-DD,YYYY-MM-DD) |
| created_at | string | Date range (YYYY-MM-DD,YYYY-MM-DD) |
| finished_at | string | Date range (YYYY-MM-DD,YYYY-MM-DD) |
| updated_at | string | Date range (YYYY-MM-DD,YYYY-MM-DD) |
| assignee_ids | array[int32] | Assignee IDs (comma-separated) |
| limit | int32 | Records per page (default: 100) |
| page | int32 | Page number (default: 1) |
| sort_by | string | Sort field (default: created_at) |
| sort_order | string | Sort order: 'asc' or 'desc' (default: desc) |

**Python Implementation:**
```python
def list_tasks(home_id=None, reference_property_id=None, type_department=None, 
               scheduled_date_range=None, assignee_ids=None, limit=100, page=1):
    params = {
        "limit": limit,
        "page": page,
        "sort_by": "created_at",
        "sort_order": "desc"
    }
    
    if home_id:
        params["home_id"] = home_id
    elif reference_property_id:
        params["reference_property_id"] = reference_property_id
    else:
        raise ValueError("Either home_id or reference_property_id is required")
    
    if type_department:
        params["type_department"] = type_department
    if scheduled_date_range:
        params["scheduled_date"] = scheduled_date_range
    if assignee_ids:
        params["assignee_ids"] = ",".join(map(str, assignee_ids))
    
    return make_request("task/", params)
```

### 6. Get Task Comments
**Endpoint:** `GET /task/{id}/comments`

**Path Parameters:**
- `id` (int32): Task ID from Breezeway system

**Python Implementation:**
```python
def get_task_comments(task_id):
    return make_request(f"task/{task_id}/comments")
```

**Response Structure:**
```json
[
  {
    "id": 7,
    "comment": "Window on the top floor in the bathroom is broken",
    "created_at": "2022-05-04T13:12:18"
  }
]
```

### 7. Get Task Requirements
**Endpoint:** `GET /task/{id}/requirements`

Retrieves user responses to completed tasks.

**Python Implementation:**
```python
def get_task_requirements(task_id):
    return make_request(f"task/{task_id}/requirements")
```

**Response Structure:**
```json
[
  {
    "section_name": "Interior",
    "action": [
      "Fold the towels a certain way",
      "Fold clean linens a certain way"
    ],
    "response": "check",
    "type_requirement": "checklist",
    "photo_required": false,
    "photos": [],
    "note": null,
    "home_element_name": null
  }
]
```

### 8. List Available Task Tags
**Endpoint:** `GET /task/tags`

**Query Parameters:**
- `company_id` (int32): Company ID (cross-company access)

**Python Implementation:**
```python
def list_task_tags(company_id=None):
    params = {"company_id": company_id} if company_id else None
    return make_request("task/tags", params)
```

### 9. Get Task Tags
**Endpoint:** `GET /task/{id}/tags`

**Python Implementation:**
```python
def get_task_tags(task_id):
    return make_request(f"task/{task_id}/tags")
```

---

## People API

### 10. List People
**Endpoint:** `GET /people`

**Query Parameters:**
- `status` (string): Filter by status: 'active', 'invited', 'inactive'

**Python Implementation:**
```python
def list_people(status=None):
    params = {"status": status} if status else None
    return make_request("people", params)
```

**Response Structure:**
```json
[
  {
    "id": 12345,
    "name": "Jennifer Brooks",
    "active": true,
    "accept_decline_tasks": true,
    "availability": {
      "monday": [
        {"start": "09:00:49", "end": "12:00:51"},
        {"start": "13:00:00", "end": "18:00:03"}
      ],
      "tuesday": [
        {"start": "09:00:00", "end": "16:00:57"}
      ],
      "wednesday": [],
      "thursday": [],
      "friday": [],
      "saturday": [],
      "sunday": []
    }
  }
]
```

---

## Companies API

### 11. List Companies
**Endpoint:** `GET /companies`

Returns active companies with paid status (trial and test accounts excluded).
Used for cross-company accounts only.

**Python Implementation:**
```python
def list_companies():
    return make_request("companies")
```

**Response Structure:**
```json
[
  {
    "id": 1,
    "name": "Breezeway Homes",
    "reference_company_id": "external-company-id"
  }
]
```

### 12. List Subdepartments
**Endpoint:** `GET /companies/subdepartments`

**Required Parameters (one of):**
- `reference_company_id` (string): Company ID from PMS System
- `company_id` (string): Company ID from Breezeway System

**Python Implementation:**
```python
def list_subdepartments(reference_company_id=None, company_id=None):
    if not reference_company_id and not company_id:
        raise ValueError("Either reference_company_id or company_id is required")
    
    params = {}
    if reference_company_id:
        params["reference_company_id"] = reference_company_id
    if company_id:
        params["company_id"] = company_id
    
    return make_request("companies/subdepartments", params)
```

---

## Supplies API

### 13. List Available Supplies
**Endpoint:** `GET /supplies`

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| company_id | int32 | - | Company ID (cross-company access) |
| limit | int32 | 100 | Records per page |
| page | int32 | 1 | Page number |
| sort_by | string | created_at | Sort field |
| sort_order | string | desc | Sort order: 'asc' or 'desc' |

**Python Implementation:**
```python
def list_supplies(company_id=None, limit=100, page=1):
    params = {
        "limit": limit,
        "page": page,
        "sort_by": "created_at",
        "sort_order": "desc"
    }
    if company_id:
        params["company_id"] = company_id
    
    return make_request("supplies", params)
```

**Response Structure:**
```json
{
  "limit": 100,
  "page": 1,
  "results": [
    {
      "id": 54471,
      "company_id": 4,
      "name": "Batteries",
      "description": "",
      "size": "AA",
      "internal_id": "",
      "unit_cost": 7,
      "stock_count": 9983,
      "low_stock_alert": true,
      "low_stock_count": 50,
      "supply_category_id": 236,
      "type_stock_status": {
        "code": "in_stock",
        "name": "In Stock"
      },
      "created_at": "2022-06-23T13:17:12",
      "updated_at": "2022-06-28T11:52:27"
    }
  ]
}
```

---

## Complete Python Client Implementation

```python
import requests
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any

class BreezewayAPIClient:
    def __init__(self, jwt_token: str):
        self.base_url = "https://api.breezeway.io/public/inventory/v1"
        self.headers = {
            "accept": "application/json",
            "Authorization": f"JWT {jwt_token}"
        }
    
    def _make_request(self, endpoint: str, params: Optional[Dict] = None) -> Dict[str, Any]:
        """Make GET request to Breezeway API"""
        url = f"{self.base_url}/{endpoint}"
        response = requests.get(url, headers=self.headers, params=params)
        response.raise_for_status()
        return response.json()
    
    # Properties
    def list_properties(self, company_id: Optional[int] = None, 
                       limit: int = 100, page: int = 1) -> Dict[str, Any]:
        """List all properties with optional filters"""
        params = {
            "limit": limit,
            "page": page,
            "sort_by": "created_at",
            "sort_order": "desc"
        }
        if company_id:
            params["company_id"] = company_id
        return self._make_request("property", params)
    
    # Reservations
    def list_reservations(self, property_ids: Optional[List[int]] = None,
                         checkin_date_ge: Optional[str] = None,
                         checkout_date_le: Optional[str] = None,
                         limit: int = 100, page: int = 1) -> Dict[str, Any]:
        """List reservations with filters"""
        params = {
            "limit": limit,
            "page": page,
            "sort_by": "created_at",
            "sort_order": "desc"
        }
        if property_ids:
            params["property_id"] = property_ids
        if checkin_date_ge:
            params["checkin_date_ge"] = checkin_date_ge
        if checkout_date_le:
            params["checkout_date_le"] = checkout_date_le
        return self._make_request("reservation", params)
    
    def list_reservations_by_external_id(self, reference_property_id: str,
                                        reference_company_id: Optional[str] = None) -> List[Dict]:
        """List reservations by external property ID (Guesty listing_id)"""
        params = {"reference_property_id": reference_property_id}
        if reference_company_id:
            params["reference_company_id"] = reference_company_id
        return self._make_request("reservation/external-id", params)
    
    def get_reservation_tasks(self, reservation_id: int) -> List[Dict]:
        """Get all tasks linked to a reservation"""
        return self._make_request(f"reservation/{reservation_id}/tasks")
    
    # Tasks
    def list_tasks(self, home_id: Optional[int] = None,
                  reference_property_id: Optional[str] = None,
                  type_department: Optional[str] = None,
                  scheduled_date_range: Optional[tuple] = None,
                  assignee_ids: Optional[List[int]] = None,
                  limit: int = 100, page: int = 1) -> Dict[str, Any]:
        """List tasks with filters"""
        if not home_id and not reference_property_id:
            raise ValueError("Either home_id or reference_property_id is required")
        
        params = {
            "limit": limit,
            "page": page,
            "sort_by": "created_at",
            "sort_order": "desc"
        }
        
        if home_id:
            params["home_id"] = home_id
        if reference_property_id:
            params["reference_property_id"] = reference_property_id
        if type_department:
            params["type_department"] = type_department
        if scheduled_date_range:
            params["scheduled_date"] = f"{scheduled_date_range[0]},{scheduled_date_range[1]}"
        if assignee_ids:
            params["assignee_ids"] = ",".join(map(str, assignee_ids))
        
        return self._make_request("task/", params)
    
    def get_task_comments(self, task_id: int) -> List[Dict]:
        """Get comments for a specific task"""
        return self._make_request(f"task/{task_id}/comments")
    
    def get_task_requirements(self, task_id: int) -> List[Dict]:
        """Get requirements/responses for completed task"""
        return self._make_request(f"task/{task_id}/requirements")
    
    def list_task_tags(self, company_id: Optional[int] = None) -> List[Dict]:
        """List available task tags"""
        params = {"company_id": company_id} if company_id else None
        return self._make_request("task/tags", params)
    
    def get_task_tags(self, task_id: int) -> List[Dict]:
        """Get tags for a specific task"""
        return self._make_request(f"task/{task_id}/tags")
    
    # People
    def list_people(self, status: Optional[str] = None) -> List[Dict]:
        """List people with optional status filter"""
        params = {"status": status} if status else None
        return self._make_request("people", params)
    
    # Companies
    def list_companies(self) -> List[Dict]:
        """List accessible companies (cross-company accounts only)"""
        return self._make_request("companies")
    
    def list_subdepartments(self, reference_company_id: Optional[str] = None,
                           company_id: Optional[str] = None) -> List[Dict]:
        """List subdepartments for a company"""
        if not reference_company_id and not company_id:
            raise ValueError("Either reference_company_id or company_id is required")
        
        params = {}
        if reference_company_id:
            params["reference_company_id"] = reference_company_id
        if company_id:
            params["company_id"] = company_id
        
        return self._make_request("companies/subdepartments", params)
    
    # Supplies
    def list_supplies(self, company_id: Optional[int] = None,
                     limit: int = 100, page: int = 1) -> Dict[str, Any]:
        """List available supplies"""
        params = {
            "limit": limit,
            "page": page,
            "sort_by": "created_at",
            "sort_order": "desc"
        }
        if company_id:
            params["company_id"] = company_id
        
        return self._make_request("supplies", params)
    
    # Utility methods
    def get_all_pages(self, method, **kwargs) -> List[Dict]:
        """Fetch all pages of results from a paginated endpoint"""
        all_results = []
        page = 1
        
        while True:
            kwargs['page'] = page
            response = method(**kwargs)
            
            if 'results' in response:
                all_results.extend(response['results'])
                if page >= response.get('total_pages', 1):
                    break
            else:
                # Non-paginated response
                return response
            
            page += 1
        
        return all_results
```

---

## Usage Examples

### Basic Setup and Authentication
```python
# Initialize client
client = BreezewayAPIClient("your_jwt_token_here")

# Test connection by listing companies
companies = client.list_companies()
print(f"Found {len(companies)} companies")
```

### Working with Properties
```python
# Get all properties
properties = client.list_properties()
print(f"Total properties: {properties['total_results']}")

# Get first property details
if properties['results']:
    property_data = properties['results'][0]
    print(f"Property: {property_data['name']} at {property_data['address1']}")
```

### Managing Reservations
```python
from datetime import datetime, timedelta

# Get upcoming reservations
today = datetime.now().strftime("%Y-%m-%d")
future_date = (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")

reservations = client.list_reservations(
    checkin_date_ge=today,
    checkout_date_le=future_date
)

# Process each reservation
for reservation in reservations['results']:
    print(f"Reservation {reservation['id']}: {reservation['checkin_date']} to {reservation['checkout_date']}")
    
    # Get tasks for this reservation
    tasks = client.get_reservation_tasks(reservation['id'])
    print(f"  - {len(tasks)} tasks associated")
```

### Working with Tasks
```python
# Get all housekeeping tasks for a property
tasks = client.list_tasks(
    home_id=16052,
    type_department="housekeeping"
)

# Check task details
for task in tasks['results']:
    print(f"Task: {task['name']} - Status: {task['type_task_status']['name']}")
    
    # Get task comments if needed
    if task['id']:
        comments = client.get_task_comments(task['id'])
        if comments:
            print(f"  Comments: {len(comments)}")
```

### Integration with Guesty
```python
# Use Guesty listing_id to find reservations in Breezeway
guesty_listing_id = "your_guesty_listing_id"
reservations = client.list_reservations_by_external_id(
    reference_property_id=guesty_listing_id
)

print(f"Found {len(reservations)} reservations for Guesty listing {guesty_listing_id}")
```

### Pagination Handling
```python
# Get all properties across all pages
all_properties = client.get_all_pages(
    client.list_properties,
    limit=100
)
print(f"Retrieved {len(all_properties)} total properties")
```

### Error Handling
```python
from requests.exceptions import RequestException

def safe_api_call(func, *args, **kwargs):
    try:
        return func(*args, **kwargs)
    except RequestException as e:
        print(f"API Error: {e}")
        return None

# Usage
properties = safe_api_call(client.list_properties)
if properties:
    print(f"Successfully retrieved {properties['total_results']} properties")
```

---

## Important Notes

1. **Authentication**: Store JWT tokens securely, never hardcode in production
2. **Rate Limiting**: Implement appropriate delays between requests to avoid rate limits
3. **Pagination**: Always check `total_pages` when fetching large datasets
4. **Date Formats**: Use YYYY-MM-DD format for all date parameters
5. **Cross-Company Access**: Some endpoints require special permissions for cross-company operations
6. **External IDs**: When integrating with Guesty, use the listing_id as reference_property_id

## Common Integration Patterns

### Daily Sync Pattern
```python
def daily_sync():
    # Get all properties
    properties = client.get_all_pages(client.list_properties)
    
    # For each property, get upcoming reservations
    for property in properties:
        reservations = client.list_reservations(
            property_ids=[property['id']],
            checkin_date_ge=datetime.now().strftime("%Y-%m-%d"),
            checkout_date_le=(datetime.now() + timedelta(days=90)).strftime("%Y-%m-%d")
        )
        
        # Process reservations and their tasks
        for reservation in reservations['results']:
            tasks = client.get_reservation_tasks(reservation['id'])
            # Store or process as needed
```

### Task Management Pattern
```python
def manage_property_tasks(property_id, date_range):
    # Get all tasks for date range
    tasks = client.list_tasks(
        home_id=property_id,
        scheduled_date_range=date_range
    )
    
    # Group by department
    by_department = {}
    for task in tasks['results']:
        dept = task['type_department']
        if dept not in by_department:
            by_department[dept] = []
        by_department[dept].append(task)
    
    return by_department
```

This documentation provides a complete reference for developing with the Breezeway API using Claude Code.
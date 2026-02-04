"""
Pytest configuration and fixtures for Breezeway ETL tests
"""

import pytest
import sys
import os

# Add project root to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))


# ============================================================================
# SAMPLE API RESPONSE FIXTURES
# ============================================================================

@pytest.fixture
def sample_property():
    """Sample property API response"""
    return {
        "id": "12345",
        "company_id": 8558,
        "name": "Beach House 101",
        "status": "active",
        "reference_company_id": "REF001",
        "reference_external_property_id": "EXT001",
        "reference_property_id": "PROP001",
        "address1": "123 Beach Road",
        "address2": "Suite 1",
        "city": "Nashville",
        "state": "TN",
        "zipcode": "37201",
        "country": "US",
        "building": "Main",
        "latitude": "36.1627",
        "longitude": "-86.7816",
        "display": True,
        "wifi_name": "BeachHouse_WiFi",
        "wifi_password": "welcome123",
        "bedrooms": 3,
        "bathrooms": 2,
        "living_area": 1500,
        "year_built": 2015,
        "notes": {
            "about": "Beautiful beach property",
            "access": "Front door code: 1234",
            "guest_access": "Check-in after 3pm",
            "direction": "Take I-65 South",
            "trash_info": "Pickup on Tuesdays",
            "wifi": "Router in living room"
        },
        "photos": [
            {
                "id": "photo1",
                "caption": "Living room",
                "default": True,
                "original_url": "https://example.com/photo1_orig.jpg",
                "url": "https://example.com/photo1.jpg"
            },
            {
                "id": "photo2",
                "caption": "Bedroom",
                "default": False,
                "original_url": "https://example.com/photo2_orig.jpg",
                "url": "https://example.com/photo2.jpg"
            }
        ]
    }


@pytest.fixture
def sample_reservation():
    """Sample reservation API response"""
    return {
        "id": "res123",
        "property_id": "12345",
        "status": "confirmed",
        "access_code": "5678",
        "checkin_date": "2026-03-01",
        "checkin_time": "15:00",
        "checkin_early": False,
        "checkout_date": "2026-03-05",
        "checkout_time": "11:00",
        "checkout_late": False,
        "note": "VIP guest",
        "guide_url": "https://guide.example.com/res123",
        "reference_reservation_id": "REF_RES123",
        "reference_property_id": "PROP001",
        "reference_external_property_id": "EXT001",
        "adults": 2,
        "children": 1,
        "pets": 0,
        "source": "direct",
        "guests": [
            {
                "name": "John Doe",
                "email": "john@example.com",
                "phone": "+1-555-1234",
                "primary": True
            },
            {
                "name": "Jane Doe",
                "email": "jane@example.com",
                "phone": "+1-555-5678",
                "primary": False
            }
        ]
    }


@pytest.fixture
def sample_task():
    """Sample task API response"""
    return {
        "id": "task456",
        "home_id": "12345",
        "name": "Cleaning",
        "description": "Full property cleaning",
        "status": "scheduled",
        "paused": False,
        "bill_to": "owner",
        "rate_type": "hourly",
        "rate_paid": "50.00 USD",
        "created_at": "2026-02-01T10:00:00Z",
        "finished_at": None,
        "started_at": None,
        "template_id": "tpl001",
        "type_department": "housekeeping",
        "type_priority": "high",
        "scheduled_date": "2026-03-01",
        "scheduled_time": "10:00",
        "checkin_date": "2026-03-01",
        "checkout_date": "2026-03-05",
        "report_url": "https://report.example.com/task456",
        "reference_property_id": "PROP001",
        "total_cost": 150.00,
        "total_time": 180,
        "estimated_time": 120,
        "estimated_rate": 25.00,
        "billable": True,
        "itemized_cost": False,
        "task_series_id": None,
        "parent_task_id": None,
        "created_by": {
            "id": "user001",
            "name": "Admin User"
        },
        "finished_by": None,
        "type_task_status": {
            "code": "SCHED",
            "name": "Scheduled",
            "stage": "pending"
        },
        "subdepartment": {
            "id": "sub001",
            "name": "Deep Clean"
        },
        "template": {
            "name": "Standard Cleaning"
        },
        "requested_by": {
            "id": "user002",
            "name": "Property Manager"
        },
        "summary": {
            "note": "Check extra attention needed in kitchen"
        },
        "linked_reservation": {
            "id": "res123",
            "external_reservation_id": "EXT_RES123"
        },
        "assignments": [
            {
                "assignee": {
                    "id": "cleaner001",
                    "name": "Maria Garcia"
                },
                "assigned_at": "2026-02-01T12:00:00Z"
            }
        ],
        "photos": [],
        "task_tags": [
            {"id": "tag1"},
            {"id": "tag2"}
        ],
        "supplies": [
            {
                "id": "sup_usage_001",
                "supply_id": "supply001",
                "name": "Cleaning Solution",
                "description": "All-purpose cleaner",
                "size": "1L",
                "quantity": 2,
                "unit_cost": 5.00,
                "total_price": 10.00,
                "bill_to": "owner",
                "billable": True,
                "markup_pricing_type": "percentage",
                "markup_rate": 0.1
            }
        ],
        "costs": [
            {
                "id": "cost001",
                "cost": 25.00,
                "description": "Extra cleaning supplies",
                "bill_to": "owner",
                "created_at": "2026-02-01T14:00:00Z",
                "updated_at": "2026-02-01T14:00:00Z",
                "type_cost": {
                    "id": "tc001",
                    "code": "SUPPLIES",
                    "name": "Supplies Cost"
                }
            }
        ]
    }


@pytest.fixture
def sample_task_with_null_values():
    """Sample task with various null/missing values for edge case testing"""
    return {
        "id": "task789",
        "home_id": "12345",
        "name": "Inspection",
        "description": None,
        "status": "pending",
        "paused": None,
        "bill_to": None,
        "rate_type": None,
        "rate_paid": None,
        "created_at": "2026-02-01T10:00:00Z",
        "finished_at": None,
        "started_at": None,
        "template_id": None,
        "type_department": None,
        "type_priority": None,
        "scheduled_date": None,
        "scheduled_time": None,
        "checkin_date": None,
        "checkout_date": None,
        "report_url": None,
        "reference_property_id": None,
        "total_cost": None,
        "total_time": None,
        "estimated_time": None,
        "estimated_rate": None,
        "billable": None,
        "itemized_cost": None,
        "task_series_id": None,
        "parent_task_id": None,
        "created_by": None,
        "finished_by": None,
        "type_task_status": None,
        "subdepartment": None,
        "template": None,
        "requested_by": None,
        "summary": None,
        "linked_reservation": None,
        "assignments": [],
        "photos": [],
        "task_tags": [],
        "supplies": [],
        "costs": []
    }


@pytest.fixture  
def sample_property_inactive():
    """Sample inactive property for filter testing"""
    return {
        "id": "99999",
        "company_id": 8558,
        "name": "Inactive Property",
        "status": "inactive",
        "address1": "999 Gone Road",
        "city": "Nashville",
        "state": "TN",
        "zipcode": "37201",
        "photos": []
    }


# ============================================================================
# MOCK DATABASE CONNECTION
# ============================================================================

class MockCursor:
    """Mock database cursor for testing"""
    def __init__(self):
        self.queries = []
        self.results = []
        self.rowcount = 0
        
    def execute(self, query, params=None):
        self.queries.append((query, params))
        
    def fetchone(self):
        return self.results[0] if self.results else None
        
    def fetchall(self):
        return self.results
        
    def close(self):
        pass


class MockConnection:
    """Mock database connection for testing"""
    def __init__(self):
        self._cursor = MockCursor()
        
    def cursor(self, cursor_factory=None):
        return self._cursor
        
    def commit(self):
        pass
        
    def rollback(self):
        pass
        
    def close(self):
        pass


@pytest.fixture
def mock_db_conn():
    """Provide a mock database connection"""
    return MockConnection()

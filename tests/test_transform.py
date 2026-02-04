"""
Tests for ETL transformation logic
"""

import pytest
from datetime import datetime
from etl.config import get_entity_config


class TestTransformParent:
    """Tests for parent record transformation"""
    
    def test_property_basic_fields(self, sample_property):
        """Test basic property field mapping"""
        from etl.etl_base import BreezewayETL
        
        # Create minimal ETL instance just for transform testing
        class MockETL:
            region_code = "nashville"
            entity_type = "properties"
            entity_config = get_entity_config("properties")
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        
        result = etl._transform_parent(sample_property)
        
        assert result["region_code"] == "nashville"
        assert result["property_id"] == "12345"
        assert result["company_id"] == 8558
        assert result["property_name"] == "Beach House 101"
        assert result["property_status"] == "active"
        assert result["property_city"] == "Nashville"
        assert result["property_state"] == "TN"
        assert result["wifi_name"] == "BeachHouse_WiFi"
        assert result["bedrooms"] == 3
        assert result["bathrooms"] == 2
        
    def test_property_nested_fields(self, sample_property):
        """Test nested field mapping (notes)"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "properties"
            entity_config = get_entity_config("properties")
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        
        result = etl._transform_parent(sample_property)
        
        assert result["property_notes_general"] == "Beautiful beach property"
        assert result["property_notes_access"] == "Front door code: 1234"
        assert result["property_notes_wifi"] == "Router in living room"
        
    def test_property_coordinate_conversion(self, sample_property):
        """Test latitude/longitude string to float conversion"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "properties"
            entity_config = get_entity_config("properties")
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        
        result = etl._transform_parent(sample_property)
        
        assert isinstance(result["latitude_numeric"], float)
        assert isinstance(result["longitude_numeric"], float)
        assert result["latitude_numeric"] == pytest.approx(36.1627, 0.001)
        assert result["longitude_numeric"] == pytest.approx(-86.7816, 0.001)
        
    def test_task_rate_paid_currency_strip(self, sample_task):
        """Test rate_paid currency suffix stripping"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        
        result = etl._transform_parent(sample_task)
        
        assert result["rate_paid"] == 50.00
        assert isinstance(result["rate_paid"], float)
        
    def test_task_nested_fields(self, sample_task):
        """Test task nested field mapping"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        
        result = etl._transform_parent(sample_task)
        
        assert result["created_by_id"] == "user001"
        assert result["created_by_name"] == "Admin User"
        assert result["task_status_code"] == "SCHED"
        assert result["subdepartment_name"] == "Deep Clean"
        assert result["linked_reservation_id"] == "res123"
        
    def test_null_value_handling(self, sample_task_with_null_values):
        """Test handling of null/None values"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        
        result = etl._transform_parent(sample_task_with_null_values)
        
        # Should not raise and should have None values
        assert result["task_description"] is None
        assert result["rate_paid"] is None
        assert result.get("created_by_id") is None


class TestTransformChildren:
    """Tests for child record transformation"""
    
    def test_property_photos(self, sample_property):
        """Test property photo transformation"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "properties"
            entity_config = get_entity_config("properties")
            
        etl = MockETL()
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        
        child_config = etl.entity_config["child_tables"]["photos"]
        parent_transformed = {"property_id": "12345"}
        
        result = etl._transform_children(sample_property, "photos", child_config, parent_transformed)
        
        assert len(result) == 2
        assert result[0]["photo_id"] == "photo1"
        assert result[0]["is_default"] == True
        assert result[0]["url"] == "https://example.com/photo1.jpg"
        assert result[1]["photo_id"] == "photo2"
        assert result[1]["is_default"] == False
        
    def test_reservation_guests(self, sample_reservation):
        """Test reservation guest transformation"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "reservations"
            entity_config = get_entity_config("reservations")
            
        etl = MockETL()
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        
        child_config = etl.entity_config["child_tables"]["guests"]
        parent_transformed = {"reservation_id": "res123"}
        
        result = etl._transform_children(sample_reservation, "guests", child_config, parent_transformed)
        
        assert len(result) == 2
        assert result[0]["guest_name"] == "John Doe"
        assert result[0]["guest_email"] == "john@example.com"
        assert result[0]["is_primary"] == True
        assert result[1]["guest_name"] == "Jane Doe"
        assert result[1]["is_primary"] == False
        
    def test_task_assignments(self, sample_task):
        """Test task assignment transformation"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        
        child_config = etl.entity_config["child_tables"]["assignments"]
        parent_transformed = {"task_id": "task456"}
        
        result = etl._transform_children(sample_task, "assignments", child_config, parent_transformed)
        
        assert len(result) == 1
        assert result[0]["assignee_id"] == "cleaner001"
        assert result[0]["assignee_name"] == "Maria Garcia"
        
    def test_task_supplies(self, sample_task):
        """Test task supplies transformation"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        
        child_config = etl.entity_config["child_tables"]["supplies"]
        parent_transformed = {"task_id": "task456"}
        
        result = etl._transform_children(sample_task, "supplies", child_config, parent_transformed)
        
        assert len(result) == 1
        assert result[0]["supply_usage_id"] == "sup_usage_001"
        assert result[0]["supply_id"] == "supply001"
        assert result[0]["name"] == "Cleaning Solution"
        assert result[0]["quantity"] == 2.0
        assert result[0]["unit_cost"] == 5.0
        assert result[0]["total_price"] == 10.0
        
    def test_task_costs(self, sample_task):
        """Test task costs transformation with nested type_cost"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        
        child_config = etl.entity_config["child_tables"]["costs"]
        parent_transformed = {"task_id": "task456"}
        
        result = etl._transform_children(sample_task, "costs", child_config, parent_transformed)
        
        assert len(result) == 1
        assert result[0]["cost_id"] == "cost001"
        assert result[0]["cost"] == 25.0
        assert result[0]["description"] == "Extra cleaning supplies"
        assert result[0]["type_cost_code"] == "SUPPLIES"
        assert result[0]["type_cost_name"] == "Supplies Cost"
        
    def test_empty_child_array(self, sample_task_with_null_values):
        """Test handling of empty child arrays"""
        from etl.etl_base import BreezewayETL
        
        class MockETL:
            region_code = "nashville"
            entity_type = "tasks"
            entity_config = get_entity_config("tasks")
            
        etl = MockETL()
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        
        child_config = etl.entity_config["child_tables"]["supplies"]
        parent_transformed = {"task_id": "task789"}
        
        result = etl._transform_children(sample_task_with_null_values, "supplies", child_config, parent_transformed)
        
        assert result == []


class TestStatusFiltering:
    """Tests for status-based filtering"""
    
    def test_filter_inactive_properties(self, sample_property, sample_property_inactive):
        """Test that inactive properties are filtered out"""
        from etl.etl_base import BreezewayETL
        from etl.config import get_entity_config
        
        class MockETL:
            region_code = "nashville"
            entity_type = "properties"
            entity_config = get_entity_config("properties")
            stats = {"errors": 0}
            
            class logger:
                @staticmethod
                def info(msg): pass
                @staticmethod
                def warning(msg): pass
                @staticmethod
                def error(msg): pass
            
        etl = MockETL()
        etl._transform_parent = BreezewayETL._transform_parent.__get__(etl)
        etl._transform_children = BreezewayETL._transform_children.__get__(etl)
        etl.transform = BreezewayETL.transform.__get__(etl)
        
        records = [sample_property, sample_property_inactive]
        parent_records, child_records = etl.transform(records)
        
        # Only active property should remain
        assert len(parent_records) == 1
        assert parent_records[0]["property_id"] == "12345"

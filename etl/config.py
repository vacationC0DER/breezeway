"""
Configuration module for Breezeway ETL Framework - V3
Centralized configuration for all regions and entity types
Updated with improved table naming conventions

SECURITY NOTE: API credentials (client_id, client_secret) are stored in
the database table breezeway.api_tokens, NOT in this config file.
"""

# ============================================================================
# REGION CONFIGURATIONS
# ============================================================================
# NOTE: Credentials removed for security. They are stored in breezeway.api_tokens table.
# Only non-sensitive metadata is stored here.

REGIONS = {
    'nashville': {
        'name': 'Nashville',
        'company_id': 8558,
        'breezeway_company_id': '8558'
    },
    'austin': {
        'name': 'Austin',
        'company_id': 8561,
        'breezeway_company_id': '8561'
    },
    'smoky': {
        'name': 'Smoky Mountains',
        'company_id': 8399,
        'breezeway_company_id': '8399'
    },
    'hilton_head': {
        'name': 'Hilton Head',
        'company_id': 12314,
        'breezeway_company_id': '12314'
    },
    'breckenridge': {
        'name': 'Breckenridge',
        'company_id': 10530,
        'breezeway_company_id': '10530'
    },
    'sea_ranch': {
        'name': 'Sea Ranch',
        'company_id': 14717,
        'breezeway_company_id': '14717'
    },
    'mammoth': {
        'name': 'Mammoth',
        'company_id': 14720,
        'breezeway_company_id': '14720'
    },
    'hill_country': {
        'name': 'Hill Country',
        'company_id': 8559,
        'breezeway_company_id': '8559'
    }
}

# ============================================================================
# ENTITY CONFIGURATIONS
# ============================================================================

ENTITY_CONFIGS = {
    'properties': {
        'endpoint': '/property',
        'api_id_field': 'id',
        'table_name': 'properties',
        'natural_key': ['property_id', 'region_code'],
        'supports_incremental': False,
        'filter_by_company': True,
        'filter_by_status': None,
        'transform_filter_status': 'active',
        'child_tables': {
            'photos': {
                'table_name': 'property_photos',
                'api_field': 'photos',
                'parent_fk': 'property_pk',
                'natural_key': ['photo_id', 'property_pk']
            }
        },
        'fields_mapping': {
            'id': 'property_id',
            'company_id': 'company_id',
            'name': 'property_name',
            'status': 'property_status',
            'reference_company_id': 'reference_company_id',
            'reference_external_property_id': 'reference_external_property_id',
            'reference_property_id': 'reference_property_id',
            'address1': 'property_address1',
            'address2': 'property_address2',
            'city': 'property_city',
            'state': 'property_state',
            'zipcode': 'property_zipcode',
            'country': 'property_country',
            'building': 'property_building',
            'latitude': 'latitude_numeric',
            'longitude': 'longitude_numeric',
            'display': 'property_display',
            'wifi_name': 'wifi_name',
            'wifi_password': 'wifi_password',
            'bedrooms': 'bedrooms',
            'bathrooms': 'bathrooms',
            'living_area': 'living_area',
            'year_built': 'year_built'
        },
        'nested_fields': {
            'notes': {
                'about': 'property_notes_general',
                'access': 'property_notes_access',
                'guest_access': 'property_notes_guest_access',
                'direction': 'property_notes_direction',
                'trash_info': 'property_notes_trash_info',
                'wifi': 'property_notes_wifi'
            }
        }
    },

    'reservations': {
        'endpoint': '/reservation',
        'api_id_field': 'id',
        'table_name': 'reservations',
        'natural_key': ['reservation_id', 'region_code'],
        'supports_incremental': False,
        'parent_fk': 'property_id',
        'child_tables': {
            'guests': {
                'table_name': 'reservation_guests',
                'api_field': 'guests',
                'parent_fk': 'reservation_pk',
                'natural_key': ['reservation_pk', 'guest_name', 'guest_email']
            }
        },
        'fields_mapping': {
            'id': 'reservation_id',
            'property_id': 'property_id',
            'status': 'reservation_status',
            'access_code': 'access_code',
            'checkin_date': 'checkin_date',
            'checkin_time': 'checkin_time',
            'checkin_early': 'checkin_early',
            'checkout_date': 'checkout_date',
            'checkout_time': 'checkout_time',
            'checkout_late': 'checkout_late',
            'note': 'reservation_note',
            'guide_url': 'guide_url',
            'reference_reservation_id': 'reference_reservation_id',
            'reference_property_id': 'reference_property_id',
            'reference_external_property_id': 'reference_external_property_id',
            'adults': 'adults',
            'children': 'children',
            'pets': 'pets',
            'source': 'source'
        }
    },

    'tasks': {
        'endpoint': '/task',
        'api_id_field': 'id',
        'table_name': 'tasks',
        'natural_key': ['task_id', 'region_code'],
        'supports_incremental': False,
        'parent_fk': 'home_id',
        'requires_property_filter': True,
        'child_tables': {
            'assignments': {
                'table_name': 'task_assignments',
                'api_field': 'assignments',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'assignee_id']
            },
            'photos': {
                'table_name': 'task_photos',
                'api_field': 'photos',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'photo_id']
            },
            'comments': {
                'table_name': 'task_comments',
                'requires_api_call': True,
                'endpoint_template': '/task/{task_id}/comments',
                'parent_fk': 'task_pk',
                'parent_id_field': 'task_id',
                'natural_key': ['comment_id', 'region_code']
            },
            'requirements': {
                'table_name': 'task_requirements',
                'requires_api_call': True,
                'endpoint_template': '/task/{task_id}/requirements',
                'parent_fk': 'task_pk',
                'parent_id_field': 'task_id',
                'natural_key': ['task_pk', 'requirement_id'],
                'fields_mapping': {
                    'id': 'requirement_id',
                    'section_name': 'section_name',
                    'action': 'action',
                    'response': 'response',
                    'type': 'type_requirement',
                    'photo_required': 'photo_required',
                    'photos': 'photos',
                    'note': 'note',
                    'home_element_name': 'home_element_name'
                }
            },
            'task_tags': {
                'table_name': 'task_tags',
                'api_field': 'task_tags',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'tag_pk']
            },
            'supplies': {
                'table_name': 'task_supplies',
                'api_field': 'supplies',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'supply_usage_id'],
                'fields_mapping': {
                    'id': 'supply_usage_id',
                    'supply_id': 'supply_id',
                    'name': 'name',
                    'description': 'description',
                    'size': 'size',
                    'quantity': 'quantity',
                    'unit_cost': 'unit_cost',
                    'total_price': 'total_price',
                    'bill_to': 'bill_to',
                    'billable': 'billable',
                    'markup_pricing_type': 'markup_pricing_type',
                    'markup_rate': 'markup_rate'
                }
            },
            'costs': {
                'table_name': 'task_costs',
                'api_field': 'costs',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'cost_id'],
                'fields_mapping': {
                    'id': 'cost_id',
                    'cost': 'cost',
                    'description': 'description',
                    'bill_to': 'bill_to',
                    'created_at': 'created_at',
                    'updated_at': 'updated_at'
                },
                'nested_fields': {
                    'type_cost': {
                        'id': 'type_cost_id',
                        'code': 'type_cost_code',
                        'name': 'type_cost_name'
                    }
                }
            }
        },
        'fields_mapping': {
            'id': 'task_id',
            'home_id': 'home_id',
            'name': 'task_name',
            'description': 'task_description',
            'status': 'task_status',
            'paused': 'task_paused',
            'bill_to': 'bill_to',
            'rate_type': 'rate_type',
            'rate_paid': 'rate_paid',
            'created_at': 'created_at',
            'finished_at': 'finished_at',
            'started_at': 'started_at',
            'template_id': 'template_task_id',
            'type_department': 'type_department',
            'type_priority': 'type_priority',
            'scheduled_date': 'scheduled_date',
            'scheduled_time': 'scheduled_time',
            'checkin_date': 'checkin_date',
            'checkout_date': 'checkout_date',
            'report_url': 'report_url',
            'reference_property_id': 'reference_property_id',
            'total_cost': 'total_cost',
            'total_time': 'total_time',
            'estimated_time': 'estimated_time',
            'estimated_rate': 'estimated_rate',
            'billable': 'billable',
            'itemized_cost': 'itemized_cost',
            'task_series_id': 'task_series_id',
            'parent_task_id': 'parent_task_id'
        },
        'nested_fields': {
            'created_by': {
                'id': 'created_by_id',
                'name': 'created_by_name'
            },
            'finished_by': {
                'id': 'finished_by_id',
                'name': 'finished_by_name'
            },
            'type_task_status': {
                'code': 'task_status_code',
                'name': 'task_status_name',
                'stage': 'task_status_stage'
            },
            'subdepartment': {
                'id': 'subdepartment_id',
                'name': 'subdepartment_name'
            },
            'template': {
                'name': 'template_name'
            },
            'requested_by': {
                'id': 'requested_by_id',
                'name': 'requested_by_name'
            },
            'summary': {
                'note': 'summary_note'
            },
            'linked_reservation': {
                'id': 'linked_reservation_id',
                'external_reservation_id': 'linked_reservation_external_id'
            }
        }
    },

    'people': {
        'endpoint': '/people',
        'api_id_field': 'id',
        'table_name': 'people',
        'natural_key': ['person_id', 'region_code'],
        'supports_incremental': False,
        'fields_mapping': {
            'id': 'person_id',
            'name': 'person_name',
            'active': 'active',
            'accept_decline_tasks': 'accept_decline_tasks'
        },
        'nested_fields': {
            'availability': {
                'monday': 'availability_monday',
                'tuesday': 'availability_tuesday',
                'wednesday': 'availability_wednesday',
                'thursday': 'availability_thursday',
                'friday': 'availability_friday',
                'saturday': 'availability_saturday',
                'sunday': 'availability_sunday'
            }
        }
    },

    'supplies': {
        'endpoint': '/supplies',
        'api_id_field': 'id',
        'table_name': 'supplies',
        'natural_key': ['supply_id', 'region_code'],
        'supports_incremental': False,
        'fields_mapping': {
            'id': 'supply_id',
            'company_id': 'company_id',
            'name': 'supply_name',
            'description': 'description',
            'size': 'size',
            'internal_id': 'internal_id',
            'unit_cost': 'unit_cost',
            'stock_count': 'stock_count',
            'low_stock_alert': 'low_stock_alert',
            'low_stock_count': 'low_stock_count',
            'supply_category_id': 'supply_category_id'
        },
        'nested_fields': {
            'type_stock_status': {
                'code': 'stock_status_code',
                'name': 'stock_status_name'
            }
        }
    },

    'tags': {
        'endpoint': '/task/tags',
        'api_id_field': 'id',
        'table_name': 'tags',
        'natural_key': ['tag_id', 'region_code'],
        'supports_incremental': False,
        'fields_mapping': {
            'id': 'tag_id',
            'name': 'tag_name',
            'description': 'tag_description'
        }
    }
}

# ============================================================================
# API CONFIGURATION
# ============================================================================

API_CONFIG = {
    'base_url': 'https://api.breezeway.io/public/inventory/v1',
    'auth_url': 'https://api.breezeway.io/public/auth/v1',
    'page_size': 100,
    'timeout': 30,
    'max_retries': 3,
    'retry_delay': 5
}

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================

DATABASE_CONFIG = {
    'schema': 'breezeway',
    'batch_size': 500,
    'use_transactions': True
}

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

LOGGING_CONFIG = {
    'level': 'INFO',
    'format': '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    'date_format': '%Y-%m-%d %H:%M:%S'
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def get_region_config(region_code: str) -> dict:
    """Get configuration for a specific region"""
    if region_code not in REGIONS:
        raise ValueError(f"Unknown region: {region_code}. Valid regions: {list(REGIONS.keys())}")
    return REGIONS[region_code]

def get_entity_config(entity_type: str) -> dict:
    """Get configuration for a specific entity type"""
    if entity_type not in ENTITY_CONFIGS:
        raise ValueError(f"Unknown entity: {entity_type}. Valid entities: {list(ENTITY_CONFIGS.keys())}")
    return ENTITY_CONFIGS[entity_type]

def get_all_regions() -> list:
    """Get list of all region codes"""
    return list(REGIONS.keys())

def get_all_entities() -> list:
    """Get list of all entity types"""
    return list(ENTITY_CONFIGS.keys())

"""
Configuration module for Breezeway ETL Framework - V3
Centralized configuration for all regions and entity types
Updated with improved table naming conventions
"""

# ============================================================================
# REGION CONFIGURATIONS
# ============================================================================

REGIONS = {
    'nashville': {
        'name': 'Nashville',
        'company_id': 8558,
        'breezeway_company_id': '8558',
        'client_id': 'qe1o2a524r9o9e0trtebfnzpa7uwqucx',
        'client_secret': '0ql63kbubut6bm7l6mi5qefjctpiyn2q'
    },
    'austin': {
        'name': 'Austin',
        'company_id': 8561,
        'breezeway_company_id': '8561',
        'client_id': 'djjj6choxfhl5155jiydsk1armvevsw6',
        'client_secret': 'jvw9sh8466w3131wy6unawyt92pvr9wp'
    },
    'smoky': {
        'name': 'Smoky Mountains',
        'company_id': 8399,
        'breezeway_company_id': '8399',
        'client_id': 'nh7ofae9o8f7okn1s60ti1vg58300jjh',
        'client_secret': 'fdr2gislvj7v87xhcfrk3so7lo3yv3s8'
    },
    'hilton_head': {
        'name': 'Hilton Head',
        'company_id': 12314,
        'breezeway_company_id': '12314',
        'client_id': 'flezehkxv3066hfwiumbkzixpwgfsnae',
        'client_secret': '8xwj46lgthwfu2uvn9rywabvxs0ln1e4'
    },
    'breckenridge': {
        'name': 'Breckenridge',
        'company_id': 10530,
        'breezeway_company_id': '10530',
        'client_id': 'ihf2zhveusojbaokzvc5uawliagzx5s4',
        'client_secret': '0bnl0v5wzemyf89oojyobt0d78emyx0z'
    },
    'sea_ranch': {
        'name': 'Sea Ranch',
        'company_id': 14717,
        'breezeway_company_id': '14717',
        'client_id': '5j9yelwgpzk2ug6i4zxmypngg8m18enx',
        'client_secret': 'ix3gm16d0h95pm19sh1s3gmjnk3pa6a6'
    },
    'mammoth': {
        'name': 'Mammoth',
        'company_id': 14720,
        'breezeway_company_id': '14720',
        'client_id': 'wwx7ntu758g8756c0o2liv8r1htk42ak',
        'client_secret': 'qsthrkvonhttbr2sgrss4vwmd34f5g15'
    },
    'hill_country': {
        'name': 'Hill Country',
        'company_id': 8559,
        'breezeway_company_id': '8559',
        'client_id': 'kcxxpq9js3f0dyjp6nin9wm4aq77j72n',
        'client_secret': 'ua10myrj9nq6mvtosbm3xpjk3pxghhv6'
    }
}

# ============================================================================
# ENTITY CONFIGURATIONS
# ============================================================================

ENTITY_CONFIGS = {
    'properties': {
        'endpoint': '/property',
        'api_id_field': 'id',
        'table_name': 'properties',  # Updated: was breezeaway_properties_gw
        'natural_key': ['property_id', 'region_code'],
        'supports_incremental': False,  # API doesn't filter reliably yet
        'filter_by_company': True,  # Filter by company_id from api_tokens
        'filter_by_status': None,  # API doesn't support status param - filter in transformation instead
        'transform_filter_status': 'active',  # Filter during transform: None (all), 'active', or 'inactive'
        'child_tables': {
            'photos': {
                'table_name': 'property_photos',  # Updated: was breezeaway_properties_gw_photos
                'api_field': 'photos',
                'parent_fk': 'property_pk',
                'natural_key': ['photo_id', 'property_pk']
            }
        },
        'fields_mapping': {
            # API field → Database column
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
            'wifi_password': 'wifi_password'
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
        'table_name': 'reservations',  # Updated: was breezeaway_reservations_gw
        'natural_key': ['reservation_id', 'region_code'],
        'supports_incremental': False,
        'parent_fk': 'property_id',
        'child_tables': {
            'guests': {
                'table_name': 'reservation_guests',  # Updated: was breezeaway_reservation_gw_guests
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
            'reference_external_property_id': 'reference_external_property_id'
        }
    },

    'tasks': {
        'endpoint': '/task',
        'api_id_field': 'id',
        'table_name': 'tasks',  # Updated: was breezeaway_tasks_gw
        'natural_key': ['task_id', 'region_code'],
        'supports_incremental': False,
        'parent_fk': 'home_id',
        'requires_property_filter': True,  # Tasks require home_id parameter
        'child_tables': {
            'assignments': {
                'table_name': 'task_assignments',  # Updated: was breezeaway_tasks_gw_assignments
                'api_field': 'assignments',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'assignee_id']
            },
            'photos': {
                'table_name': 'task_photos',  # Updated: was breezeaway_tasks_gw_photos
                'api_field': 'photos',
                'parent_fk': 'task_pk',
                'natural_key': ['task_pk', 'photo_id']
            },
            'comments': {
                'table_name': 'task_comments',
                'requires_api_call': True,  # Needs separate API call per task
                'endpoint_template': '/task/{task_id}/comments',
                'parent_fk': 'task_pk',
                'parent_id_field': 'task_id',  # Field in parent to use for API call
                'natural_key': ['comment_id', 'region_code']  # Matches DB constraint uq_task_comment_natural_key
            },
            'requirements': {
                'table_name': 'task_requirements',
                'requires_api_call': True,  # Needs separate API call per task
                'endpoint_template': '/task/{task_id}/requirements',
                'parent_fk': 'task_pk',
                'parent_id_field': 'task_id',
                'natural_key': ['task_pk', 'requirement_id'],  # FIXED: Added natural key for UPSERT
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
                'natural_key': ['task_pk', 'tag_pk']  # Matches DB constraint; tag_id resolved to tag_pk in ETL
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
            'template_id': 'template_task_id',  # FIXED: API field is template_id not template_task_id
            'type_department': 'type_department',
            'type_priority': 'type_priority',
            'scheduled_date': 'scheduled_date',
            'scheduled_time': 'scheduled_time',
            'checkin_date': 'checkin_date',  # For linking to reservations
            'checkout_date': 'checkout_date',  # For linking to reservations
            'report_url': 'report_url',
            'reference_property_id': 'reference_property_id'
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
    'schema': 'breezeway',  # Updated: was api_integrations
    'batch_size': 500,  # Records per batch for UPSERT
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

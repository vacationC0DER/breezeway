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
            'template_task_id': 'template_task_id'
        },
        'nested_fields': {
            'created_by': {
                'id': 'created_by_id',
                'name': 'created_by_name'
            },
            'finished_by': {
                'id': 'finished_by_id',
                'name': 'finished_by_name'
            }
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

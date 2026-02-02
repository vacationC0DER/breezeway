"""
Base ETL Framework for Breezeway API
Handles extraction, transformation, and loading with proper error handling
"""

import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

import requests
import psycopg2
from psycopg2.extras import RealDictCursor, execute_values
from typing import List, Dict, Optional, Any, Tuple
from datetime import datetime
import logging
import time

from auth_manager import TokenManager
from sync_tracker import SyncTracker
from etl.config import (
    get_region_config,
    get_entity_config,
    API_CONFIG,
    DATABASE_CONFIG
)


class BreezewayETL:
    """
    Base ETL class for Breezeway API integration

    Features:
    - Automatic token management
    - Pagination handling
    - Batch UPSERT operations
    - Transaction management
    - Error handling and retry logic
    - Comprehensive logging
    - Sync tracking
    """

    def __init__(self, region_code: str, entity_type: str, db_conn):
        """
        Initialize ETL processor

        Args:
            region_code: Region identifier (e.g., 'nashville')
            entity_type: Entity type (e.g., 'properties')
            db_conn: Database connection object
        """
        self.region_code = region_code
        self.entity_type = entity_type
        self.conn = db_conn

        # Load configurations
        self.region_config = get_region_config(region_code)
        self.entity_config = get_entity_config(entity_type)

        # Initialize managers
        self.token_mgr = TokenManager(region_code)
        self.tracker = SyncTracker(region_code, entity_type)

        # Setup logging
        self.logger = logging.getLogger(f"ETL.{region_code}.{entity_type}")

        # Statistics
        self.stats = {
            'api_calls': 0,
            'records_fetched': 0,
            'records_inserted': 0,
            'records_updated': 0,
            'errors': 0
        }

    # ========================================================================
    # EXTRACT
    # ========================================================================

    def extract(self) -> List[Dict[str, Any]]:
        """
        Extract data from Breezeway API with pagination

        Returns:
            List of records from API
        """
        self.logger.info(f"Starting extraction for {self.entity_type}")

        token = self.token_mgr.get_valid_token()
        headers = {
            "accept": "application/json",
            "Authorization": f"JWT {token}"
        }

        all_records = []
        page = 1

        # Build base URL
        endpoint = self.entity_config['endpoint']
        base_url = f"{API_CONFIG['base_url']}{endpoint}"

        # Special handling for tasks (requires property filter)
        if self.entity_config.get('requires_property_filter'):
            all_records = self._extract_tasks()
        else:
            all_records = self._extract_standard(base_url, headers)

        self.stats['records_fetched'] = len(all_records)
        self.logger.info(f"Extracted {len(all_records)} {self.entity_type} records")

        return all_records

    def _extract_standard(self, base_url: str, headers: dict) -> List[Dict]:
        """Extract using standard pagination with optional filtering"""
        all_records = []
        page = 1

        # Build query parameters
        params = {
            'limit': API_CONFIG['page_size'],
            'page': page
        }

        # Add company_id filter if configured
        if self.entity_config.get('filter_by_company'):
            try:
                company_id = self.token_mgr.get_company_id()
                params['company_id'] = company_id
                self.logger.info(f"Filtering by company_id: {company_id}")
            except Exception as e:
                self.logger.warning(f"Could not get company_id for filtering: {e}")

        # Add status filter if configured
        status_filter = self.entity_config.get('filter_by_status')
        if status_filter:
            params['status'] = status_filter
            self.logger.info(f"Filtering by status: {status_filter}")

        while True:
            params['page'] = page

            # Build URL with query parameters
            query_string = '&'.join([f"{k}={v}" for k, v in params.items()])
            url = f"{base_url}?{query_string}"

            self.logger.debug(f"Fetching page {page}: {url}")

            try:
                response = requests.get(url, headers=headers, timeout=API_CONFIG['timeout'])
                response.raise_for_status()

                self.stats['api_calls'] += 1
                self.tracker.increment_api_calls()

                data = response.json()

                # Handle both response formats: direct list or dict with 'results' key
                if isinstance(data, list):
                    results = data
                elif isinstance(data, dict):
                    results = data.get('results', [])
                else:
                    results = []

                if not results:
                    self.logger.debug(f"No more results at page {page}")
                    break

                all_records.extend(results)

                # For direct list responses, pagination typically not supported
                if isinstance(data, list):
                    break

                page += 1

            except requests.exceptions.RequestException as e:
                self.logger.error(f"API request failed: {e}")
                raise

        return all_records

    def _extract_tasks(self) -> List[Dict]:
        """Extract tasks (requires property_id filter)"""
        self.logger.info("Extracting tasks (requires property list)")

        # Get all properties for this region
        schema = DATABASE_CONFIG['schema']
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(f"""
                SELECT id, property_id, reference_external_property_id
                FROM {schema}.properties
                WHERE region_code = %s
            """, (self.region_code,))
            properties = cur.fetchall()

        self.logger.info(f"Found {len(properties)} properties, fetching tasks for each")

        token = self.token_mgr.get_valid_token()
        headers = {
            "accept": "application/json",
            "Authorization": f"JWT {token}"
        }

        all_tasks = []

        for prop in properties:
            home_id = prop['property_id']
            ref_prop_id = prop['reference_external_property_id'] or ''

            # Fetch tasks for this property
            url = f"{API_CONFIG['base_url']}/task?limit=100&page=1&home_id={home_id}&reference_property_id={ref_prop_id}"

            try:
                response = requests.get(url, headers=headers, timeout=API_CONFIG['timeout'])
                response.raise_for_status()

                self.stats['api_calls'] += 1
                self.tracker.increment_api_calls()

                data = response.json()
                tasks = data.get('results', [])
                all_tasks.extend(tasks)

            except requests.exceptions.RequestException as e:
                self.logger.warning(f"Failed to fetch tasks for property {home_id}: {e}")
                continue

        return all_tasks

    # ========================================================================
    # TRANSFORM
    # ========================================================================

    def transform(self, records: List[Dict]) -> Tuple[List[Dict], Dict[str, List[Dict]]]:
        """
        Transform API records to database schema

        Args:
            records: Raw API records

        Returns:
            Tuple of (parent_records, child_records_by_table)
        """
        self.logger.info(f"Transforming {len(records)} records")

        # Apply status filtering if configured (for properties entity)
        status_filter = self.entity_config.get('transform_filter_status')
        if status_filter:
            original_count = len(records)
            records = [r for r in records if r.get('status') == status_filter]
            filtered_out = original_count - len(records)
            if filtered_out > 0:
                self.logger.info(f"Filtered out {filtered_out} records (status != '{status_filter}')")

        parent_records = []
        child_records = {
            table: []
            for table in self.entity_config.get('child_tables', {}).keys()
        }

        for record in records:
            try:
                # Transform parent record
                parent = self._transform_parent(record)
                parent_records.append(parent)

                # Transform child records
                for child_name, child_config in self.entity_config.get('child_tables', {}).items():
                    children = self._transform_children(record, child_name, child_config, parent)
                    child_records[child_name].extend(children)

            except Exception as e:
                self.logger.error(f"Transform error for record {record.get('id')}: {e}")
                self.stats['errors'] += 1
                continue

        # Deduplicate parent records based on natural key
        natural_keys = self.entity_config['natural_key']
        seen = set()
        deduplicated_parents = []
        duplicates_found = 0

        for record in parent_records:
            # Create a tuple of natural key values
            key_tuple = tuple(record.get(k) for k in natural_keys)
            if key_tuple not in seen:
                seen.add(key_tuple)
                deduplicated_parents.append(record)
            else:
                duplicates_found += 1

        if duplicates_found > 0:
            self.logger.warning(f"Found and removed {duplicates_found} duplicate records based on natural key")

        self.logger.info(f"Transformed {len(deduplicated_parents)} parent records")
        return deduplicated_parents, child_records

    def _transform_parent(self, record: Dict) -> Dict:
        """Transform single parent record"""
        transformed = {
            'region_code': self.region_code
        }

        # Map direct fields
        for api_field, db_column in self.entity_config.get('fields_mapping', {}).items():
            value = record.get(api_field)

            # Type conversions
            if value is not None:
                # Convert numeric strings to proper types
                if db_column in ['latitude_numeric', 'longitude_numeric']:
                    try:
                        value = float(value) if value else None
                    except (ValueError, TypeError):
                        value = None
                elif db_column == 'company_id':
                    try:
                        value = int(value) if value else None
                    except (ValueError, TypeError):
                        value = None
                elif db_column == 'rate_paid':
                    # Handle currency values like "120.00 USD"
                    try:
                        if isinstance(value, str):
                            # Strip currency suffixes (USD, EUR, etc.)
                            value = value.split()[0]  # Take first part before space
                        value = float(value) if value else None
                    except (ValueError, TypeError, IndexError):
                        value = None

            transformed[db_column] = value

        # Map nested fields
        for parent_field, nested_mapping in self.entity_config.get('nested_fields', {}).items():
            parent_value = record.get(parent_field, {})
            if isinstance(parent_value, dict):
                for nested_field, db_column in nested_mapping.items():
                    transformed[db_column] = parent_value.get(nested_field)

        # Add timestamps
        transformed['synced_at'] = datetime.now()

        return transformed

    def _transform_children(self, parent_record: Dict, child_name: str,
                           child_config: Dict, parent_transformed: Dict) -> List[Dict]:
        """Transform child records"""
        # Skip children that require separate API calls (handled by fetch_api_children)
        if child_config.get('requires_api_call', False):
            return []

        api_field = child_config.get('api_field')
        if not api_field:
            return []

        child_records = parent_record.get(api_field, [])

        if not isinstance(child_records, list):
            return []

        transformed_children = []

        for child in child_records:
            transformed_child = {
                'region_code': self.region_code
            }

            # For task photos (check this BEFORE general photos)
            if child_name == 'photos' and self.entity_type == 'tasks':
                transformed_child.update({
                    'task_id': str(parent_record.get('id', '')),
                    'photo_id': str(child.get('id', '')),
                    'url': child.get('url'),
                    'caption': child.get('caption'),
                    'uploaded_at': child.get('uploaded_at')
                })

            # For property photos
            elif child_name == 'photos':
                transformed_child.update({
                    'photo_id': str(child.get('id', '')),
                    'caption': child.get('caption'),
                    'is_default': child.get('default', False),
                    'original_url': child.get('original_url'),
                    'url': child.get('url')
                })

            # For guests
            elif child_name == 'guests':
                transformed_child.update({
                    'guest_name': child.get('name'),
                    'guest_email': child.get('email'),
                    'guest_phone': child.get('phone'),
                    'is_primary': child.get('primary', False)
                })

            # For assignments
            elif child_name == 'assignments':
                assignee = child.get('assignee', {})
                transformed_child.update({
                    'task_id': str(parent_record.get('id', '')),
                    'assignee_id': str(assignee.get('id', '')),
                    'assignee_name': assignee.get('name'),
                    'assigned_at': child.get('assigned_at')
                })

            # For comments
            elif child_name == 'comments':
                transformed_child.update({
                    'comment_id': str(child.get('id', '')),
                    'comment': child.get('comment'),
                    'author_name': child.get('author', {}).get('name'),
                    'author_id': str(child.get('author', {}).get('id', '')),
                    'created_at': child.get('created_at'),
                    'updated_at': child.get('updated_at')
                })

            # For requirements
            elif child_name == 'requirements':
                import json
                transformed_child.update({
                    'requirement_id': str(child.get('id', '')),
                    'section_name': child.get('section_name'),
                    'action': json.dumps(child.get('action')) if child.get('action') else None,
                    'response': child.get('response'),
                    'type_requirement': child.get('type_requirement'),
                    'photo_required': child.get('photo_required'),
                    'photos': json.dumps(child.get('photos')) if child.get('photos') else None,
                    'note': child.get('note'),
                    'home_element_name': child.get('home_element_name')
                })

            # For task_tags (bridge table - needs tag_pk lookup)
            elif child_name == 'task_tags':
                tag_id = str(child.get('id', ''))
                if tag_id:
                    # Store tag_id for later FK resolution to tag_pk
                    transformed_child.update({
                        'tag_id': tag_id  # Will be resolved to tag_pk during load
                    })

            # Store parent natural key for later FK resolution
            api_id_field = self.entity_config['api_id_field']
            transformed_child['_parent_api_id'] = str(parent_record.get(api_id_field, ''))

            transformed_children.append(transformed_child)

        return transformed_children

    def fetch_api_children(self, parent_records: List[Dict], child_records: Dict[str, List[Dict]]) -> Dict[str, List[Dict]]:
        """
        Fetch child records that require separate API calls

        Args:
            parent_records: Transformed parent records
            child_records: Existing child records dict from transform

        Returns:
            Updated child_records dict with API-fetched children
        """
        # Find child tables that require API calls
        api_child_tables = {
            name: config
            for name, config in self.entity_config.get('child_tables', {}).items()
            if config.get('requires_api_call', False)
        }

        if not api_child_tables:
            return child_records

        self.logger.info(f"Fetching API-based children: {list(api_child_tables.keys())}")

        for child_name, child_config in api_child_tables.items():
            endpoint_template = child_config.get('endpoint_template')
            parent_id_field = child_config.get('parent_id_field')

            if not endpoint_template or not parent_id_field:
                self.logger.warning(f"Skipping {child_name}: missing endpoint_template or parent_id_field")
                continue

            child_records_list = []

            for parent_record in parent_records:
                parent_id = parent_record.get(parent_id_field)

                if not parent_id:
                    continue

                # Build endpoint URL
                endpoint = endpoint_template.format(task_id=parent_id)

                try:
                    # Get token and build headers
                    token = self.token_mgr.get_valid_token()
                    headers = {
                        "accept": "application/json",
                        "Authorization": f"JWT {token}"
                    }

                    # Build full URL
                    url = f"{API_CONFIG['base_url']}{endpoint}"

                    # Fetch from API
                    response = requests.get(url, headers=headers, timeout=API_CONFIG['timeout'])
                    response.raise_for_status()

                    self.stats['api_calls'] += 1
                    self.tracker.increment_api_calls()

                    # Parse response - handle both formats (direct list or dict with 'data' key)
                    response_data = response.json()
                    if isinstance(response_data, list):
                        api_children = response_data
                    elif isinstance(response_data, dict):
                        api_children = response_data.get('data', [])
                    else:
                        api_children = []

                    if not isinstance(api_children, list):
                        api_children = []

                    # Transform each child record
                    for child in api_children:
                        transformed_child = {
                            'region_code': self.region_code
                        }

                        # Use the same transformation logic
                        if child_name == 'comments':
                            transformed_child.update({
                                'comment_id': str(child.get('id', '')),
                                'comment': child.get('comment'),
                                'author_name': child.get('author', {}).get('name'),
                                'author_id': str(child.get('author', {}).get('id', '')),
                                'created_at': child.get('created_at'),
                                'updated_at': child.get('updated_at')
                            })

                        elif child_name == 'requirements':
                            # Use fields_mapping from config if available
                            fields_mapping = child_config.get('fields_mapping', {})
                            if fields_mapping:
                                for api_field, db_column in fields_mapping.items():
                                    value = child.get(api_field)
                                    # Convert to JSON for complex fields
                                    if api_field in ['action', 'photos'] and value is not None:
                                        import json
                                        value = json.dumps(value) if value else None
                                    transformed_child[db_column] = value
                            else:
                                # Fallback to manual mapping if no fields_mapping
                                transformed_child.update({
                                    'requirement_id': str(child.get('id', '')),
                                    'section_name': child.get('section_name'),
                                    'action': json.dumps(child.get('action')) if child.get('action') else None,
                                    'response': child.get('response'),
                                    'type_requirement': child.get('type'),
                                    'photo_required': child.get('photo_required'),
                                    'photos': json.dumps(child.get('photos')) if child.get('photos') else None,
                                    'note': child.get('note'),
                                    'home_element_name': child.get('home_element_name')
                                })

                        # Store parent API ID for FK resolution
                        transformed_child['_parent_api_id'] = str(parent_id)
                        child_records_list.append(transformed_child)

                except Exception as e:
                    self.logger.warning(f"Failed to fetch {child_name} for {parent_id_field}={parent_id}: {e}")
                    continue

            # Add to child_records dict
            if child_name in child_records:
                child_records[child_name].extend(child_records_list)
            else:
                child_records[child_name] = child_records_list

            self.logger.info(f"Fetched {len(child_records_list)} {child_name} records via API")

        return child_records

    # ========================================================================
    # LOAD
    # ========================================================================

    def load(self, parent_records: List[Dict], child_records: Dict[str, List[Dict]]):
        """
        Load data to database with transaction management

        Args:
            parent_records: Parent entity records
            child_records: Dict of child records by table name
        """
        self.logger.info(f"Loading {len(parent_records)} parent records")

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                if DATABASE_CONFIG['use_transactions']:
                    cur.execute("BEGIN")

                # Load parent records
                inserted, updated = self._upsert_parents(cur, parent_records)
                self.stats['records_inserted'] += inserted
                self.stats['records_updated'] += updated

                # Resolve parent-to-parent FKs (e.g., reservations→properties, tasks→properties)
                self._resolve_parent_fks(cur)

                # Load child records (if any)
                for child_type, records in child_records.items():
                    if records:
                        self._upsert_children(cur, child_type, records)

                if DATABASE_CONFIG['use_transactions']:
                    cur.execute("COMMIT")

                self.logger.info(f"Load complete: {inserted} inserted, {updated} updated")

        except Exception as e:
            if DATABASE_CONFIG['use_transactions']:
                self.conn.rollback()
            self.logger.error(f"Load failed: {e}")
            raise

    def _upsert_parents(self, cur, records: List[Dict]) -> Tuple[int, int]:
        """UPSERT parent records using batch operation"""
        if not records:
            return 0, 0

        table_name = self.entity_config['table_name']
        natural_keys = self.entity_config['natural_key']

        # Get columns (excluding internal fields)
        columns = [k for k in records[0].keys() if not k.startswith('_')]

        # Build conflict target
        conflict_target = ', '.join(natural_keys)

        # Build update clause (all columns except natural keys and created_at)
        update_columns = [
            c for c in columns
            if c not in natural_keys and c != 'created_at'
        ]
        update_clause = ', '.join([
            f"{col} = EXCLUDED.{col}"
            for col in update_columns
        ])

        # Prepare data
        values = [
            tuple(record.get(col) for col in columns)
            for record in records
        ]

        # Build query
        columns_str = ', '.join(columns)
        placeholders = ', '.join(['%s'] * len(columns))

        schema = DATABASE_CONFIG['schema']
        query = f"""
            INSERT INTO {schema}.{table_name} ({columns_str})
            VALUES %s
            ON CONFLICT ({conflict_target}) DO UPDATE SET
                {update_clause},
                updated_at = CURRENT_TIMESTAMP
            RETURNING (xmax = 0) AS inserted
        """

        # Execute batch UPSERT
        execute_values(cur, query, values, page_size=DATABASE_CONFIG['batch_size'])

        # Count inserted vs updated
        results = cur.fetchall()
        inserted = sum(1 for r in results if r['inserted'])
        updated = len(results) - inserted

        return inserted, updated

    def _resolve_parent_fks(self, cur):
        """Resolve parent-to-parent foreign key relationships"""
        schema = DATABASE_CONFIG['schema']
        table_name = self.entity_config['table_name']

        # Reservations: resolve property_pk from property_id
        if self.entity_type == 'reservations':
            self.logger.info("Resolving property_pk for reservations")
            cur.execute(f"""
                UPDATE {schema}.{table_name} r
                SET property_pk = p.id
                FROM {schema}.properties p
                WHERE r.property_id = p.property_id
                  AND r.region_code = p.region_code
                  AND r.region_code = %s
                  AND r.property_pk IS NULL
            """, (self.region_code,))
            rows_updated = cur.rowcount
            self.logger.info(f"Resolved property_pk for {rows_updated} reservations")

        # Tasks: resolve property_pk from home_id
        elif self.entity_type == 'tasks':
            self.logger.info("Resolving property_pk for tasks")
            cur.execute(f"""
                UPDATE {schema}.{table_name} t
                SET property_pk = p.id
                FROM {schema}.properties p
                WHERE t.home_id = p.property_id
                  AND t.region_code = p.region_code
                  AND t.region_code = %s
                  AND t.property_pk IS NULL
            """, (self.region_code,))
            rows_updated = cur.rowcount
            self.logger.info(f"Resolved property_pk for {rows_updated} tasks")

            # Resolve reservation_pk using linked_reservation_id from API response
            self.logger.info("Resolving reservation_pk from linked_reservation_id")
            cur.execute(f"""
                UPDATE {schema}.{table_name} t
                SET reservation_pk = r.id
                FROM {schema}.reservations r
                WHERE t.linked_reservation_id = r.reservation_id
                  AND t.region_code = r.region_code
                  AND t.region_code = %s
                  AND t.reservation_pk IS NULL
                  AND t.linked_reservation_id IS NOT NULL
            """, (self.region_code,))
            rows_updated = cur.rowcount
            self.logger.info(f"Resolved reservation_pk for {rows_updated} tasks via linked_reservation_id")

    def _upsert_children(self, cur, child_type: str, records: List[Dict]):
        """UPSERT child records"""
        if not records:
            return

        # Get child table configuration
        child_config = self.entity_config['child_tables'][child_type]
        table_name = child_config['table_name']

        self.logger.info(f"Loading {len(records)} {table_name} records")

        # First, resolve parent FKs
        parent_table = self.entity_config['table_name']
        parent_fk = child_config['parent_fk']

        # Get parent ID mapping (API ID → Database PK)
        schema = DATABASE_CONFIG['schema']
        parent_api_id_field = self.entity_config['api_id_field']
        parent_db_id_field = self.entity_config['fields_mapping'][parent_api_id_field]

        cur.execute(f"""
            SELECT id, {parent_db_id_field}
            FROM {schema}.{parent_table}
            WHERE region_code = %s
        """, (self.region_code,))

        parent_mapping = {
            str(row[parent_db_id_field]): row['id']
            for row in cur.fetchall()
        }

        # Add parent FK to child records
        for record in records:
            parent_api_id = record.pop('_parent_api_id', None)
            if parent_api_id and parent_api_id in parent_mapping:
                record[parent_fk] = parent_mapping[parent_api_id]
            else:
                self.logger.warning(f"Could not resolve parent FK for {parent_api_id}")

        # Filter out records without parent FK
        records = [r for r in records if parent_fk in r]

        if not records:
            return

        # Special handling for task_tags: resolve tag_id to tag_pk
        if child_type == 'task_tags' and records:
            # Get tag mapping (tag_id → tag_pk)
            cur.execute(f"""
                SELECT id, tag_id
                FROM {schema}.tags
                WHERE region_code = %s
            """, (self.region_code,))

            tag_mapping = {
                str(row['tag_id']): row['id']
                for row in cur.fetchall()
            }

            # Resolve tag_id to tag_pk
            for record in records:
                tag_id = record.pop('tag_id', None)
                if tag_id and tag_id in tag_mapping:
                    record['tag_pk'] = tag_mapping[tag_id]
                else:
                    self.logger.warning(f"Could not resolve tag_id {tag_id} to tag_pk")

            # Filter out records without tag_pk
            records = [r for r in records if 'tag_pk' in r]

            if not records:
                self.logger.warning("No task_tags records after tag resolution")
                return

        # Get natural key for conflict detection
        natural_key = child_config.get('natural_key', [])

        # Deduplicate records within batch based on natural key
        # This prevents "ON CONFLICT DO UPDATE cannot affect row a second time" error
        if natural_key:
            seen_keys = set()
            deduplicated_records = []
            duplicates_in_batch = 0
            for record in records:
                key_tuple = tuple(record.get(k) for k in natural_key)
                if key_tuple not in seen_keys:
                    seen_keys.add(key_tuple)
                    deduplicated_records.append(record)
                else:
                    duplicates_in_batch += 1
            if duplicates_in_batch > 0:
                self.logger.info(f"Removed {duplicates_in_batch} duplicate records within batch for {table_name}")
            records = deduplicated_records

        if not records:
            self.logger.info(f"No records to load for {table_name} after deduplication")
            return

        # Get columns
        columns = list(records[0].keys())
        columns_str = ', '.join(columns)
        placeholders = ', '.join(['%s'] * len(columns))

        # Prepare data
        values = [
            tuple(record.get(col) for col in columns)
            for record in records
        ]

        # Apply UPSERT (ON CONFLICT) for all child tables with natural keys
        # This prevents duplicate key errors on re-sync and enables idempotent ETL
        if natural_key:
            # Build conflict target from natural key
            conflict_columns = ', '.join(natural_key)

            # Build UPDATE clause to update all non-key columns
            update_columns = [col for col in columns if col not in natural_key and col not in ['id', 'created_at']]
            if update_columns:
                update_set = ', '.join([f"{col} = EXCLUDED.{col}" for col in update_columns])
                query = f"""
                    INSERT INTO {schema}.{table_name} ({columns_str})
                    VALUES %s
                    ON CONFLICT ({conflict_columns})
                    DO UPDATE SET {update_set}
                """
            else:
                # No columns to update, just ignore conflicts
                query = f"""
                    INSERT INTO {schema}.{table_name} ({columns_str})
                    VALUES %s
                    ON CONFLICT ({conflict_columns}) DO NOTHING
                """
        else:
            # For tables without natural keys: use simple INSERT
            # (Should be rare - most child tables should have natural keys defined)
            self.logger.warning(f"No natural key defined for {table_name}, using simple INSERT")
            query = f"""
                INSERT INTO {schema}.{table_name} ({columns_str})
                VALUES %s
            """

        execute_values(cur, query, values, page_size=DATABASE_CONFIG['batch_size'])

        self.logger.info(f"Loaded {len(records)} {table_name} records")

    # ========================================================================
    # ORCHESTRATION
    # ========================================================================

    def run(self):
        """Execute complete ETL process"""
        start_time = datetime.now()

        try:
            self.logger.info(f"="*60)
            self.logger.info(f"Starting ETL: {self.region_code} / {self.entity_type}")
            self.logger.info(f"="*60)

            # Start tracking
            self.tracker.start()

            # Extract
            records = self.extract()

            if not records:
                self.logger.info("No records to process")
                self.tracker.complete()
                return

            # Transform
            parent_records, child_records = self.transform(records)

            # Fetch API-based children (e.g., task comments)
            child_records = self.fetch_api_children(parent_records, child_records)

            # Load
            self.load(parent_records, child_records)

            # Update tracker
            for _ in parent_records:
                self.tracker.increment_processed()
            self.tracker.stats['new'] = self.stats['records_inserted']
            self.tracker.stats['updated'] = self.stats['records_updated']

            # Complete
            self.tracker.complete()

            duration = (datetime.now() - start_time).total_seconds()

            self.logger.info(f"="*60)
            self.logger.info(f"ETL Complete")
            self.logger.info(f"="*60)
            self.logger.info(f"Duration: {duration:.1f} seconds")
            self.logger.info(f"Records fetched: {self.stats['records_fetched']}")
            self.logger.info(f"Records inserted: {self.stats['records_inserted']}")
            self.logger.info(f"Records updated: {self.stats['records_updated']}")
            self.logger.info(f"API calls: {self.stats['api_calls']}")
            self.logger.info(f"Errors: {self.stats['errors']}")
            self.logger.info(f"="*60)

        except Exception as e:
            self.tracker.fail(str(e))
            self.logger.error(f"ETL failed: {e}", exc_info=True)
            raise

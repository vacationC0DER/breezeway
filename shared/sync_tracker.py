"""
Sync Tracker for ETL Pipeline

Manages sync status tracking and provides incremental loading capabilities.

Usage:
    from shared.sync_tracker import SyncTracker

    tracker = SyncTracker('nashville', 'properties')
    tracker.start()

    last_sync = tracker.get_last_sync_time()
    # ... do sync work ...

    tracker.increment_processed(count=10)
    tracker.complete()
"""

import psycopg2
from datetime import datetime
from dotenv import dotenv_values
import os
from typing import Optional, Dict


class SyncTracker:
    """Tracks ETL sync operations and enables incremental loading"""

    def __init__(self, region_code: str, entity_type: str):
        """
        Initialize SyncTracker.

        Args:
            region_code: Region identifier (e.g., 'nashville')
            entity_type: Entity being synced (e.g., 'properties', 'reservations', 'tasks')
        """
        self.region_code = region_code
        self.entity_type = entity_type
        self.stats = {
            'processed': 0,
            'new': 0,
            'updated': 0,
            'deleted': 0,
            'api_calls': 0
        }
        self.conn = None
        self.cur = None
        self._connect_db()

    def _connect_db(self):
        """Establish database connection"""
        try:
            env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
            envs = dict(dotenv_values(env_path))

            if not envs:
                raise ValueError("Could not load .env file")

            url = (f"postgresql://{envs['USER']}:{envs['PASSWORD']}"
                   f"@{envs['HOST']}:{envs['PORT']}/{envs['DB']}?sslmode=require")

            self.conn = psycopg2.connect(url)
            self.cur = self.conn.cursor()

        except Exception as e:
            raise Exception(f"Failed to connect to database: {e}")

    def get_last_sync_time(self) -> Optional[datetime]:
        """
        Get timestamp of last successful sync for incremental loading.

        Returns:
            datetime or None: Last successful sync timestamp, or None if never synced
        """
        self.cur.execute("""
            SELECT last_successful_sync_at
            FROM breezeway.etl_sync_log
            WHERE region_code = %s
              AND entity_type = %s
              AND last_successful_sync_at IS NOT NULL
            ORDER BY last_successful_sync_at DESC
            LIMIT 1
        """, (self.region_code, self.entity_type))

        result = self.cur.fetchone()
        return result[0] if result else None

    def start(self):
        """Mark sync as started"""
        self.cur.execute("""
            INSERT INTO breezeway.etl_sync_log
                (region_code, entity_type, sync_status, sync_started_at)
            VALUES
                (%s, %s, 'running', CURRENT_TIMESTAMP)
            ON CONFLICT (region_code, entity_type)
            DO UPDATE SET
                sync_started_at = CURRENT_TIMESTAMP,
                sync_completed_at = NULL,
                sync_status = 'running',
                records_processed = 0,
                records_new = 0,
                records_updated = 0,
                records_deleted = 0,
                api_calls_made = 0,
                error_message = NULL,
                updated_at = CURRENT_TIMESTAMP
        """, (self.region_code, self.entity_type))
        self.conn.commit()

        print(f"⚡ Starting sync: {self.region_code} / {self.entity_type}")

    def increment_processed(self, count: int = 1):
        """Increment processed record count"""
        self.stats['processed'] += count

    def increment_new(self, count: int = 1):
        """Increment new record count"""
        self.stats['new'] += count

    def increment_updated(self, count: int = 1):
        """Increment updated record count"""
        self.stats['updated'] += count

    def increment_deleted(self, count: int = 1):
        """Increment deleted record count"""
        self.stats['deleted'] += count

    def increment_api_calls(self, count: int = 1):
        """Increment API call count"""
        self.stats['api_calls'] += count

    def get_stats(self) -> Dict[str, int]:
        """Get current statistics"""
        return self.stats.copy()

    def complete(self):
        """Mark sync as successfully completed"""
        self.cur.execute("""
            UPDATE breezeway.etl_sync_log SET
                sync_completed_at = CURRENT_TIMESTAMP,
                sync_status = 'success',
                last_successful_sync_at = CURRENT_TIMESTAMP,
                records_processed = %s,
                records_new = %s,
                records_updated = %s,
                records_deleted = %s,
                api_calls_made = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE region_code = %s
              AND entity_type = %s
        """, (
            self.stats['processed'],
            self.stats['new'],
            self.stats['updated'],
            self.stats['deleted'],
            self.stats['api_calls'],
            self.region_code,
            self.entity_type
        ))
        self.conn.commit()

        print(f"✓ Sync completed: {self.region_code} / {self.entity_type}")
        print(f"  Processed: {self.stats['processed']} "
              f"(New: {self.stats['new']}, Updated: {self.stats['updated']}) "
              f"API calls: {self.stats['api_calls']}")

    def fail(self, error_message: str):
        """Mark sync as failed with error message"""
        self.cur.execute("""
            UPDATE breezeway.etl_sync_log SET
                sync_completed_at = CURRENT_TIMESTAMP,
                sync_status = 'failed',
                error_message = %s,
                records_processed = %s,
                records_new = %s,
                records_updated = %s,
                records_deleted = %s,
                api_calls_made = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE region_code = %s
              AND entity_type = %s
        """, (
            error_message,
            self.stats['processed'],
            self.stats['new'],
            self.stats['updated'],
            self.stats['deleted'],
            self.stats['api_calls'],
            self.region_code,
            self.entity_type
        ))
        self.conn.commit()

        print(f"✗ Sync failed: {self.region_code} / {self.entity_type}")
        print(f"  Error: {error_message}")

    def __del__(self):
        """Clean up database connection"""
        if self.cur:
            self.cur.close()
        if self.conn:
            self.conn.close()


# Context manager for automatic cleanup
class SyncContext:
    """Context manager for sync tracking with automatic error handling"""

    def __init__(self, region_code: str, entity_type: str):
        self.tracker = SyncTracker(region_code, entity_type)

    def __enter__(self):
        self.tracker.start()
        return self.tracker

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            # No exception, mark as complete
            self.tracker.complete()
        else:
            # Exception occurred, mark as failed
            error_msg = f"{exc_type.__name__}: {exc_val}"
            self.tracker.fail(error_msg)
        return False  # Don't suppress exception


if __name__ == "__main__":
    # Test sync tracker
    import sys
    import time

    if len(sys.argv) < 3:
        print("Usage: python sync_tracker.py <region_code> <entity_type>")
        print("Example: python sync_tracker.py nashville properties")
        sys.exit(1)

    region = sys.argv[1]
    entity = sys.argv[2]

    print(f"\n=== Testing SyncTracker ===")
    print(f"Region: {region}, Entity: {entity}\n")

    try:
        # Test basic usage
        tracker = SyncTracker(region, entity)

        # Check last sync
        last_sync = tracker.get_last_sync_time()
        if last_sync:
            print(f"Last successful sync: {last_sync}")
        else:
            print("No previous sync found (first run)")

        # Start sync
        tracker.start()

        # Simulate work
        print("\nSimulating sync work...")
        time.sleep(1)

        tracker.increment_api_calls()
        tracker.increment_processed(5)
        tracker.increment_new(3)
        tracker.increment_updated(2)

        # Complete
        tracker.complete()

        print(f"\n✓ Test completed successfully")
        print(f"Stats: {tracker.get_stats()}")

    except Exception as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)

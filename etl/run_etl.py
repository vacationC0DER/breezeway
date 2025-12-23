#!/usr/bin/env python3
"""
Breezeway ETL CLI Runner
Run ETL for any region and entity type

Usage:
    python run_etl.py nashville properties
    python run_etl.py austin reservations
    python run_etl.py all properties        # Run for all regions
    python run_etl.py nashville all         # Run all entities for region
"""

import sys
import os

# Add paths for imports
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)
sys.path.insert(0, os.path.join(parent_dir, 'shared'))

import argparse
import logging
from datetime import datetime

from etl.etl_base import BreezewayETL
from etl.config import get_all_regions, get_all_entities, LOGGING_CONFIG
from database import DatabaseManager
from alerting import AlertManager


def setup_logging(level: str = 'INFO'):
    """Setup logging configuration"""
    logging.basicConfig(
        level=getattr(logging, level),
        format=LOGGING_CONFIG['format'],
        datefmt=LOGGING_CONFIG['date_format']
    )


def run_single_etl(region: str, entity: str, db_conn, alert_mgr: AlertManager) -> tuple[bool, dict]:
    """
    Run ETL for single region/entity combination

    Returns:
        (success: bool, metrics: dict)
    """
    logger = logging.getLogger(f"Runner.{region}.{entity}")
    start_time = datetime.now()
    metrics = {
        'duration': 0,
        'records_processed': 0,
        'api_calls': 0,
        'error': None
    }

    try:
        etl = BreezewayETL(region, entity, db_conn)
        etl.run()

        metrics['duration'] = (datetime.now() - start_time).total_seconds()
        metrics['records_processed'] = etl.stats.get('records_fetched', 0)
        metrics['api_calls'] = etl.stats.get('api_calls', 0)

        return True, metrics

    except Exception as e:
        metrics['duration'] = (datetime.now() - start_time).total_seconds()
        metrics['error'] = str(e)

        logger.error(f"ETL failed for {region}/{entity}: {e}")

        # Send failure alert
        alert_mgr.send_failure_alert(
            region=region,
            entity=entity,
            error_msg=str(e),
            duration=metrics['duration'],
            records_processed=metrics['records_processed'],
            api_calls=metrics['api_calls']
        )

        return False, metrics


def run_etl(region: str, entity: str, db_conn, alert_mgr: AlertManager, job_type: str = "ETL Batch"):
    """
    Run ETL with support for 'all' keyword

    Args:
        region: Region code or 'all'
        entity: Entity type or 'all'
        db_conn: Database connection
        alert_mgr: Alert manager instance
        job_type: Type of job for alert subject (e.g., "Hourly ETL", "Daily ETL")
    """
    regions = get_all_regions() if region == 'all' else [region]
    entities = get_all_entities() if entity == 'all' else [entity]

    logger = logging.getLogger("Runner")

    total = len(regions) * len(entities)
    current = 0
    success = 0
    failed = 0

    logger.info(f"Starting ETL for {len(regions)} region(s) × {len(entities)} entity(ies) = {total} jobs")
    logger.info("="*70)

    start_time = datetime.now()

    for reg in regions:
        for ent in entities:
            current += 1
            logger.info(f"[{current}/{total}] Running: {reg} / {ent}")

            success_flag, metrics = run_single_etl(reg, ent, db_conn, alert_mgr)

            if success_flag:
                success += 1
            else:
                failed += 1

            logger.info("-"*70)

    duration = (datetime.now() - start_time).total_seconds()

    logger.info("="*70)
    logger.info(f"ETL Batch Complete")
    logger.info(f"="*70)
    logger.info(f"Total jobs: {total}")
    logger.info(f"Successful: {success}")
    logger.info(f"Failed: {failed}")
    logger.info(f"Duration: {duration:.1f} seconds ({duration/60:.1f} minutes)")
    logger.info("="*70)

    # Send summary alert if there were failures
    alert_mgr.send_success_summary(
        total_jobs=total,
        successful=success,
        failed=failed,
        total_duration=duration,
        job_type=job_type
    )

    # Return failure count for exit code determination
    return failed


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description='Breezeway ETL Runner',
        epilog="""
Examples:
  %(prog)s nashville properties          # Run properties for Nashville
  %(prog)s austin reservations           # Run reservations for Austin
  %(prog)s all properties                # Run properties for all regions
  %(prog)s nashville all                 # Run all entities for Nashville
  %(prog)s all all                       # Run everything (caution!)
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        'region',
        help='Region code or "all" for all regions'
    )
    parser.add_argument(
        'entity',
        help='Entity type (properties, reservations, tasks) or "all"'
    )
    parser.add_argument(
        '--log-level',
        default='INFO',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        help='Logging level (default: INFO)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Dry run mode (validate but don\'t execute)'
    )

    args = parser.parse_args()

    # Setup logging
    setup_logging(args.log_level)
    logger = logging.getLogger("Main")

    # Validate inputs
    if args.region != 'all':
        valid_regions = get_all_regions()
        if args.region not in valid_regions:
            logger.error(f"Invalid region: {args.region}")
            logger.error(f"Valid regions: {', '.join(valid_regions)}, all")
            sys.exit(1)

    if args.entity != 'all':
        valid_entities = get_all_entities()
        if args.entity not in valid_entities:
            logger.error(f"Invalid entity: {args.entity}")
            logger.error(f"Valid entities: {', '.join(valid_entities)}, all")
            sys.exit(1)

    if args.dry_run:
        logger.info("DRY RUN MODE - No data will be modified")
        logger.info(f"Would run: {args.region} / {args.entity}")
        sys.exit(0)

    # Initialize alert manager
    alert_mgr = AlertManager()

    # Get database connection
    try:
        logger.info("Connecting to database...")
        db_conn = DatabaseManager.get_connection()
        logger.info(f"Connected to database: {db_conn.info.dbname}")
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        sys.exit(1)

    # Run ETL
    failed_count = 0
    try:
        failed_count = run_etl(args.region, args.entity, db_conn, alert_mgr, job_type="ETL Run")
    except KeyboardInterrupt:
        logger.warning("ETL interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"ETL failed: {e}", exc_info=True)
        sys.exit(1)
    finally:
        db_conn.close()
        logger.info("Database connection closed")

    # Exit with non-zero code if any jobs failed
    if failed_count > 0:
        logger.error(f"ETL completed with {failed_count} failure(s)")
        sys.exit(1)


if __name__ == '__main__':
    main()

"""
Alert Management for Breezeway ETL

Sends alerts for ETL failures via multiple channels:
- Email (via sendmail)
- Log file
- Database status updates

Usage:
    from shared.alerting import AlertManager

    alert_mgr = AlertManager()
    alert_mgr.send_failure_alert(
        region='nashville',
        entity='properties',
        error_msg='Connection timeout',
        duration=120.5,
        records_processed=1500
    )
"""

import os
import logging
from datetime import datetime
from typing import Optional
import subprocess


class AlertManager:
    """Manages alerts for ETL failures and warnings"""

    def __init__(self, email_recipients: Optional[list] = None):
        """
        Initialize AlertManager

        Args:
            email_recipients: List of email addresses for alerts
                             If None, reads from ALERT_EMAIL env var
        """
        self.logger = logging.getLogger("AlertManager")

        # Get email recipients from env or parameter
        if email_recipients:
            self.recipients = email_recipients
        else:
            email_env = os.getenv('ALERT_EMAIL', '')
            self.recipients = [e.strip() for e in email_env.split(',') if e.strip()]

        # Alert thresholds
        self.duration_threshold = 300  # 5 minutes
        self.error_count_threshold = 10

    def send_failure_alert(
        self,
        region: str,
        entity: str,
        error_msg: str,
        duration: float = 0,
        records_processed: int = 0,
        api_calls: int = 0
    ):
        """
        Send alert for ETL failure

        Args:
            region: Region code (e.g., 'nashville')
            entity: Entity type (e.g., 'properties')
            error_msg: Error message
            duration: Execution duration in seconds
            records_processed: Number of records processed before failure
            api_calls: Number of API calls made
        """
        subject = f"🚨 ETL FAILURE: {region}/{entity}"

        body = f"""
Breezeway ETL Failure Alert
============================

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Region: {region}
Entity: {entity}

Error:
{error_msg}

Metrics:
- Duration: {duration:.1f} seconds
- Records Processed: {records_processed}
- API Calls: {api_calls}

Action Required:
1. Check logs: /root/Breezeway/logs/
2. Verify API connectivity
3. Check database connectivity
4. Review sync status:
   psql -c "SELECT * FROM breezeway.etl_sync_log WHERE sync_status='failed' ORDER BY sync_started_at DESC LIMIT 5;"

Logs:
- Hourly: /root/Breezeway/logs/hourly_etl_$(date +%Y%m%d).log
- Daily: /root/Breezeway/logs/daily_etl_$(date +%Y%m%d).log

To retry manually:
cd /root/Breezeway
python3 etl/run_etl.py {region} {entity}
"""

        # Log the alert
        self.logger.error(f"ETL FAILURE ALERT: {region}/{entity} - {error_msg}")

        # Send email alerts
        for recipient in self.recipients:
            try:
                self._send_email(recipient, subject, body)
                self.logger.info(f"Alert sent to {recipient}")
            except Exception as e:
                self.logger.error(f"Failed to send alert to {recipient}: {e}")

        # Write to alert log file
        self._write_alert_log(subject, body)

    def send_warning_alert(
        self,
        region: str,
        entity: str,
        warning_msg: str,
        duration: float = 0
    ):
        """
        Send warning alert for performance issues or data quality concerns

        Args:
            region: Region code
            entity: Entity type
            warning_msg: Warning message
            duration: Execution duration in seconds
        """
        subject = f"⚠️  ETL WARNING: {region}/{entity}"

        body = f"""
Breezeway ETL Warning Alert
===========================

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Region: {region}
Entity: {entity}

Warning:
{warning_msg}

Metrics:
- Duration: {duration:.1f} seconds

This may require attention but the ETL completed.

Review:
cd /root/Breezeway
tail -100 logs/hourly_etl_$(date +%Y%m%d).log
"""

        # Log the warning
        self.logger.warning(f"ETL WARNING: {region}/{entity} - {warning_msg}")

        # Send email alerts
        for recipient in self.recipients:
            try:
                self._send_email(recipient, subject, body)
            except Exception as e:
                self.logger.error(f"Failed to send warning to {recipient}: {e}")

        # Write to alert log file
        self._write_alert_log(subject, body)

    def send_success_summary(
        self,
        total_jobs: int,
        successful: int,
        failed: int,
        total_duration: float,
        job_type: str = "ETL Batch"
    ):
        """
        Send summary for completed ETL batch (only if there were failures)

        Args:
            total_jobs: Total number of jobs run
            successful: Number of successful jobs
            failed: Number of failed jobs
            total_duration: Total duration in seconds
            job_type: Type of job (e.g., "Hourly ETL", "Daily ETL")
        """
        if failed == 0:
            return  # No alert needed for all-success runs

        subject = f"📊 {job_type} Summary: {failed} failures"

        body = f"""
Breezeway {job_type} Summary
{'='*50}

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Results:
- Total Jobs: {total_jobs}
- Successful: {successful} ✓
- Failed: {failed} ✗
- Duration: {total_duration:.1f} seconds ({total_duration/60:.1f} minutes)

Check logs for details:
cd /root/Breezeway/logs
tail -200 hourly_etl_$(date +%Y%m%d).log | grep -A 5 "FAILED"

Review failed syncs:
psql -h localhost -U breezeway -d breezeway -c "
SELECT region_code, entity_type, error_message, sync_started_at
FROM breezeway.etl_sync_log
WHERE sync_status='failed'
  AND sync_started_at > NOW() - INTERVAL '1 hour'
ORDER BY sync_started_at DESC;
"
"""

        # Log the summary
        self.logger.info(f"{job_type} Summary: {successful}/{total_jobs} successful")

        # Send email alerts
        for recipient in self.recipients:
            try:
                self._send_email(recipient, subject, body)
            except Exception as e:
                self.logger.error(f"Failed to send summary to {recipient}: {e}")

        # Write to alert log file
        self._write_alert_log(subject, body)

    def _send_email(self, recipient: str, subject: str, body: str):
        """
        Send email using sendmail

        Args:
            recipient: Email address
            subject: Email subject
            body: Email body
        """
        if not recipient:
            return

        # Construct email
        email_content = f"""To: {recipient}
Subject: {subject}
From: breezeway-etl@system.local

{body}
"""

        # Send via sendmail
        try:
            process = subprocess.Popen(
                ['/usr/sbin/sendmail', '-t', '-oi'],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            stdout, stderr = process.communicate(email_content.encode('utf-8'))

            if process.returncode != 0:
                raise Exception(f"sendmail failed: {stderr.decode('utf-8')}")

        except FileNotFoundError:
            # sendmail not installed, log instead
            self.logger.warning("sendmail not found - alert logged only")
            self.logger.info(f"Would have sent to {recipient}: {subject}")
        except Exception as e:
            raise Exception(f"Email send failed: {e}")

    def _write_alert_log(self, subject: str, body: str):
        """
        Write alert to dedicated alert log file

        Args:
            subject: Alert subject
            body: Alert body
        """
        log_dir = "/root/Breezeway/logs"
        os.makedirs(log_dir, exist_ok=True)

        alert_log = os.path.join(log_dir, "alerts.log")

        with open(alert_log, 'a') as f:
            f.write(f"\n{'='*80}\n")
            f.write(f"{datetime.now().isoformat()}\n")
            f.write(f"{subject}\n")
            f.write(f"{'='*80}\n")
            f.write(f"{body}\n")


# Convenience function for quick alerts
def send_etl_failure_alert(region: str, entity: str, error: Exception, **kwargs):
    """
    Quick helper to send ETL failure alert

    Args:
        region: Region code
        entity: Entity type
        error: Exception that caused the failure
        **kwargs: Additional metrics (duration, records_processed, api_calls)
    """
    alert_mgr = AlertManager()
    alert_mgr.send_failure_alert(
        region=region,
        entity=entity,
        error_msg=str(error),
        **kwargs
    )


if __name__ == "__main__":
    # Test alert system
    print("Testing Alert System...")
    print("="*60)

    alert_mgr = AlertManager(email_recipients=["admin@example.com"])

    # Test failure alert
    print("\n1. Testing failure alert...")
    alert_mgr.send_failure_alert(
        region="test_region",
        entity="test_entity",
        error_msg="Test error: Connection timeout",
        duration=125.5,
        records_processed=1500,
        api_calls=25
    )

    # Test warning alert
    print("\n2. Testing warning alert...")
    alert_mgr.send_warning_alert(
        region="test_region",
        entity="test_entity",
        warning_msg="ETL took longer than expected (>5 minutes)",
        duration=350.2
    )

    # Test summary
    print("\n3. Testing summary alert...")
    alert_mgr.send_success_summary(
        total_jobs=16,
        successful=14,
        failed=2,
        total_duration=245.8,
        job_type="Hourly ETL"
    )

    print("\n✓ Test complete. Check /root/Breezeway/logs/alerts.log")

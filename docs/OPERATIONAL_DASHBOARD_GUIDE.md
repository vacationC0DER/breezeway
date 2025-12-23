# Breezeway Operational Dashboard Guide

## Executive Summary

This document describes 20 materialized views created to power operational dashboards for the Breezeway vacation rental portfolio. These views provide insights into task completion, worker performance, property health, and data quality across 8 regions and 524 properties.

---

## Quick Reference: View Categories

| Category | Views | Purpose |
|----------|-------|---------|
| **Executive** | 1 | Portfolio-wide KPIs |
| **Regional** | 2 | Cross-region comparison |
| **Worker Performance** | 4 | Leaderboards by department |
| **Task Analytics** | 4 | Completion, backlog, priorities |
| **Property Health** | 3 | Property-level operational status |
| **Trending** | 3 | Time-based analysis |
| **Data Quality** | 2 | Quality monitoring & alerts |
| **Specialized** | 1 | Tag analysis |

---

## The 20 Materialized Views

### 1. `mv_portfolio_executive_summary`
**Purpose:** C-level dashboard with portfolio-wide KPIs

**Key Metrics:**
- Total properties: 524
- Total active workers: 300
- Current backlog: 1,651 tasks
- 30-day completion rate: 75%
- Average turnaround: 448.5 hours

**Sample Output:**
```
total_properties         | 524
total_regions            | 8
tasks_last_30_days       | 1,711
completed_last_30_days   | 1,284
current_backlog          | 1,651
completion_rate_30d_pct  | 75.0%
housekeeping_backlog     | 607
inspection_backlog       | 706
maintenance_backlog      | 338
```

---

### 2. `mv_regional_performance_scorecard`
**Purpose:** Compare operational metrics across all 8 regions

**Key Metrics per Region:**
- Property count
- 90-day task volume
- Completion rate
- Average turnaround time
- Active workers

**Regional Ranking (by 90-day volume):**
| Region | Properties | Tasks 90d | Completion % | Backlog |
|--------|-----------|-----------|--------------|---------|
| Smoky | 75 | 936 | 69.0% | 285 |
| Austin | 59 | 767 | 66.1% | 259 |
| Mammoth | 112 | 718 | 52.6% | 338 |
| Nashville | 104 | 639 | 83.7% | 103 |
| Hilton Head | 49 | 391 | 74.7% | 98 |
| Sea Ranch | 54 | 369 | 84.0% | 58 |
| Breckenridge | 37 | 345 | 59.7% | 136 |
| Hill Country | 34 | 280 | 77.9% | 59 |

---

### 3. `mv_worker_leaderboard_housekeeping`
**Purpose:** Rank housekeeping staff (cleaners) by performance

**Key Metrics:**
- Tasks completed (90d, 30d, 7d)
- Average active work time
- Consistency (std deviation)
- Tasks per day
- Regional and global rank

**Top 5 Cleaners (Last 90 Days):**
| Worker | Region | Tasks | Avg Minutes |
|--------|--------|-------|-------------|
| Zen Cleaning Services | austin | 166 | 92.7 |
| Amy Franklin | breckenridge | 93 | 190.5 |
| Tammy Gibbs | smoky | 71 | 0.7 |
| A&P Property Cleaning | austin | 61 | 292.4 |
| Rosa Contreras | nashville | 55 | 1171.8 |

---

### 4. `mv_worker_leaderboard_inspection`
**Purpose:** Rank inspection staff by performance

**Top 5 Inspectors (Last 90 Days):**
| Worker | Region | Tasks | Avg Minutes |
|--------|--------|-------|-------------|
| Shannon Kubiak | hilton_head | 100 | 203.5 |
| Ginger McDonald | hill_country | 63 | 72.0 |
| Norma Gomez | sea_ranch | 60 | 66.7 |
| Aimee Carrion | breckenridge | 57 | 177.9 |
| Clara Adongo Pedro | austin | 54 | 77.9 |

---

### 5. `mv_worker_leaderboard_maintenance`
**Purpose:** Rank maintenance staff with urgency handling metrics

**Key Additional Metrics:**
- Urgent tasks completed
- High priority tasks completed
- Average urgent response time (hours)

**Top Maintenance Workers by Region:**
- Nashville: Keedance Lowrey (67 tasks, 7 urgent, 42.6h avg response)
- Sea Ranch: Ryan Zettler (76 tasks, 0 urgent)
- Hill Country: Ginger McDonald (69 tasks)

---

### 6. `mv_task_completion_metrics`
**Purpose:** Detailed completion statistics by department

**Key Metrics:**
- Volume (total, completed, pending, in-progress)
- Completion rate percentage
- Timing (average, median, P90 hours)
- Same-day completion rate
- Unique workers

---

### 7. `mv_task_backlog_aging`
**Purpose:** Identify stale tasks and aging distribution

**Aging Buckets:**
- 0-1 days
- 2-3 days
- 4-7 days
- 8-14 days
- 15-30 days
- Over 30 days

**Critical Finding:** High priority maintenance tasks aging:
- Nashville: 1 high-priority task aging 42 days
- Mammoth: 4 high-priority tasks avg 25 days, 5 urgent avg 19 days

---

### 8. `mv_property_task_density`
**Purpose:** Identify high-volume properties (potential problem properties)

**Key Metrics:**
- Total tasks (all time, 90d, 30d, 7d)
- Department breakdown
- Urgent/high tasks
- Current backlog
- Regional and global rank

---

### 9. `mv_property_operational_health`
**Purpose:** Composite health score for each property (0-100)

**Health Score Components:**
- Backlog Score (25%): Lower backlog = higher score
- Completion Score (35%): Higher completion rate = higher score
- Urgency Score (25%): No urgent backlog = higher score
- Turnaround Score (15%): Faster than average = higher score

**Health Status Categories:**
- Excellent: 80+
- Good: 65-79
- Fair: 50-64
- Needs Attention: <50

**Properties Needing Immediate Attention:**
| Property | Region | Score | Backlog | Issue |
|----------|--------|-------|---------|-------|
| Bear Family Manor | smoky | 37.5 | 8 | 0% completion |
| SRV04 - Ski Run Villa #4 | mammoth | 39.5 | 28 | High volume |
| 5E Mountaintop Mansion | smoky | 40.0 | 4 | 2 urgent |
| Walden Pond | hilton_head | 41.5 | 7 | 0% completion |

---

### 10. `mv_reservation_turnaround_analysis`
**Purpose:** Analyze task performance around check-in/check-out

**Key Metrics per Week:**
- Reservation count
- Linked tasks (housekeeping, inspection)
- Task completion rate
- Average turnaround

---

### 11. `mv_monthly_trend_analysis`
**Purpose:** Track operational trends over 12 months

**Key Metrics per Month:**
- Tasks created
- Tasks completed
- Completion rate
- Average turnaround
- Priority distribution
- Month-over-month change

---

### 12. `mv_weekly_operational_snapshot`
**Purpose:** Quick weekly summary for standup meetings

**Key Metrics:**
- This week vs. last week comparison
- Current backlog
- Urgent/high priority backlog
- Department breakdown
- Active workers

---

### 13. `mv_priority_response_times`
**Purpose:** Track response times by priority level

**Key Metrics:**
- Average/median hours to start
- Average/median/P90 hours to resolve
- Resolved within 24h
- Resolved within 48h

---

### 14. `mv_task_tags_analysis`
**Purpose:** Understand task categorization patterns

**Top Tags:**
| Tag | Tasks | Completion % |
|-----|-------|--------------|
| Bill to Owner | 1,752 | - |
| Trash Haul | 180 | - |
| Recurring | 173 | - |
| Thank You Note | 150 | - |
| Lawn Maintenance | 129 | - |

---

### 15. `mv_worker_efficiency_ranking`
**Purpose:** Cross-department worker comparison

**Key Metrics:**
- Departments worked (versatility)
- Total tasks
- Speed metrics
- Consistency score
- Efficiency score
- Volume and speed ranks

---

### 16. `mv_regional_workload_distribution`
**Purpose:** Balance workload insights across regions

**Key Metrics:**
- Average daily tasks
- Peak daily volume
- Variability (std dev)
- Tasks per property per day
- Tasks per worker per day

---

### 17. `mv_seasonal_demand_patterns`
**Purpose:** Seasonal trends for capacity planning

**Dimensions:**
- Month
- Day of week
- Region
- Department

---

### 18. `mv_property_maintenance_burden`
**Purpose:** Identify properties with recurring maintenance issues

**Key Metrics:**
- Maintenance task volume (all time, 90d, 30d)
- Priority breakdown
- Current backlog
- Recency ratio (30d vs 90d normalized)
- Total cost paid

---

### 19. `mv_data_quality_scorecard`
**Purpose:** Track data completeness and quality

**Current Quality Status:**
| Entity | Records | Key Issue |
|--------|---------|-----------|
| tasks | 43,412 | 81.4% have completer info |
| properties | 524 | 82.4% have coordinates |
| reservations | 5,998 | Only 10.8% have access codes |
| task_assignments | 41,846 | **0% have assignee names** |
| people | 308 | **0% have availability data** |

---

### 20. `mv_operational_alerts`
**Purpose:** Real-time operational issue detection

**Alert Types:**
| Alert | Severity | Count |
|-------|----------|-------|
| CHECKOUT_NO_CLEANING | Critical | 28 |
| URGENT_NOT_STARTED | Critical | 6 |
| STALE_TASK | High | 1,421 |
| HIGH_BACKLOG_PROPERTY | Medium | 125 |

---

## Data Quality Issues Identified

### Critical Issues

1. **task_assignments.assignee_name is 100% NULL**
   - Impact: Cannot track pre-assignment vs post-completion
   - Root cause: API not returning assignment data OR ETL not capturing it
   - Recommendation: Investigate Breezeway API `/task/{id}/assignments` endpoint

2. **people.availability_* fields are 100% NULL**
   - Impact: Cannot do capacity planning or scheduling optimization
   - Root cause: Availability data not in API response OR not being extracted
   - Recommendation: Check if availability endpoint exists separately

3. **reservations.access_code is 89.2% NULL**
   - Impact: Guest access codes not available for operational use
   - Current: Only 648 of 5,998 reservations have access codes
   - Note: Some regions (Nashville, Smoky, Breckenridge) have partial coverage

### Moderate Issues

4. **tasks.started_at is 15% NULL for finished tasks**
   - Impact: Cannot calculate accurate active work time for all tasks
   - Likely cause: Workers not clicking "Start" before working

5. **properties.latitude/longitude missing for 17.6%**
   - Impact: Cannot do geographic analysis for all properties
   - Affected regions: Nashville (25 missing), Smoky (28 missing)

6. **tasks.reservation_pk linked for only 4.2%**
   - Impact: Cannot correlate all tasks to specific guest stays
   - Note: Many tasks are maintenance/general, not reservation-specific

### Data Model Observations

7. **task_requirements.type_requirement is 100% NULL**
   - All 24.5M requirement records have no type classification
   - Limits ability to categorize checklist items

8. **High duplication in historical data**
   - task_requirements: 24.5M records (likely duplicates from repeated syncs)
   - Consider deduplication similar to property_photos cleanup

---

## Refresh Schedule Recommendations

```bash
# Critical alerts - every 15 minutes
*/15 * * * * psql -c "REFRESH MATERIALIZED VIEW breezeway.mv_operational_alerts;"

# Operational snapshots - hourly
0 * * * * psql -c "REFRESH MATERIALIZED VIEW breezeway.mv_weekly_operational_snapshot;"
0 * * * * psql -c "REFRESH MATERIALIZED VIEW breezeway.mv_portfolio_executive_summary;"

# All views - daily at midnight
0 0 * * * psql -c "SELECT breezeway.refresh_dashboard_views();"
```

---

## Usage Examples

### Get Top Performers
```sql
-- Top 10 cleaners globally
SELECT worker_name, region_code, tasks_completed_90d, avg_minutes_active
FROM breezeway.mv_worker_leaderboard_housekeeping
WHERE global_rank <= 10;

-- Top 3 inspectors per region
SELECT worker_name, region_code, tasks_completed_90d
FROM breezeway.mv_worker_leaderboard_inspection
WHERE regional_rank <= 3;
```

### Identify Problem Areas
```sql
-- Properties needing attention
SELECT property_name, region_code, health_score, backlog, urgent_backlog
FROM breezeway.mv_property_operational_health
WHERE health_status = 'Needs Attention'
ORDER BY health_score;

-- Critical alerts
SELECT alert_type, entity_name, alert_message
FROM breezeway.mv_operational_alerts
WHERE severity = 'Critical';
```

### Regional Analysis
```sql
-- Region comparison
SELECT region_code, properties, tasks_90d, completion_rate_pct, active_workers
FROM breezeway.mv_regional_performance_scorecard
ORDER BY completion_rate_pct DESC;
```

### Refresh All Views
```sql
SELECT breezeway.refresh_dashboard_views();
```

---

## Files Created

| File | Purpose |
|------|---------|
| `/root/Breezeway/sql/operational_dashboard_views.sql` | All 20 view definitions |
| `/root/Breezeway/docs/OPERATIONAL_DASHBOARD_GUIDE.md` | This documentation |

---

## Next Steps

1. **Fix Critical Data Issues:**
   - Investigate task_assignments API data
   - Check people availability endpoint
   - Audit access_code sync for all regions

2. **Dashboard Integration:**
   - Connect views to BI tool (Metabase, Grafana, etc.)
   - Create scheduled refresh jobs
   - Set up alerting for critical issues

3. **Data Deduplication:**
   - Apply similar dedup logic to task_requirements as was done for property_photos
   - Could reduce 24.5M records significantly

4. **Performance Optimization:**
   - Add CONCURRENTLY refresh for zero-downtime updates
   - Consider partitioning for seasonal_demand_patterns

---

*Document created: 2025-12-17*
*Views created by: Senior Data Analyst*

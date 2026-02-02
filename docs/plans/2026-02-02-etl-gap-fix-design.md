# Breezeway ETL Gap Fix - Comprehensive Design

**Date:** 2026-02-02
**Author:** Claude + Steven
**Status:** Ready for Implementation

---

## Executive Summary

Analysis of the Breezeway ETL pipeline revealed several data gaps where API fields are not being captured. This design addresses all gaps to achieve full data completeness and accurate task-reservation linkage.

### Key Findings from API Verification

| Finding | Impact |
|---------|--------|
| `linked_reservation` field exists in bulk task endpoint but not extracted | Task-reservation linkage at ~4% instead of 50%+ |
| `supplies[]` and `costs[]` arrays populated but not captured | Missing financial/inventory data |
| Additional task fields (subdepartment, totals, billable) not mapped | Incomplete task records |
| Property contacts endpoint not synced | Missing contact information |

### Verified API Response Structures

**linked_reservation (from GET /task/?home_id=...):**
```json
{
  "id": 89388376,
  "external_reservation_id": "6980bf2ef58c18003fbc044e"
}
```

**supplies (from task response):**
```json
{
  "id": 24337223,
  "supply_id": 180585,
  "name": "Styrofoam Faucet Cover",
  "quantity": 2,
  "unit_cost": 4.75,
  "total_price": 4.75,
  "bill_to": "owner",
  "billable": true,
  "markup_pricing_type": "percent",
  "markup_rate": 0.0
}
```

**costs (from task response):**
```json
{
  "id": 4044672,
  "cost": 27.5,
  "description": null,
  "bill_to": "owner",
  "type_cost": {"id": 1, "code": "labor", "name": "Labor"},
  "created_at": "2026-01-30T18:07:54+00:00",
  "updated_at": "2026-01-30T18:07:54+00:00"
}
```

---

## Part 1: Schema Changes

### 1A. Tasks Table — New Columns

```sql
-- Migration: 012_add_task_fields.sql

ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS linked_reservation_id BIGINT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS linked_reservation_external_id VARCHAR(50);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS total_cost NUMERIC(10,2);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS total_time VARCHAR(32);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS estimated_time VARCHAR(32);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS estimated_rate NUMERIC(10,2);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS billable BOOLEAN;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS itemized_cost BOOLEAN;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS subdepartment_id INTEGER;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS subdepartment_name VARCHAR(128);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS summary_note TEXT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS template_name VARCHAR(128);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS task_series_id BIGINT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS parent_task_id BIGINT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS requested_by_id INTEGER;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS requested_by_name VARCHAR(128);

-- Index for reservation linkage queries
CREATE INDEX IF NOT EXISTS idx_tasks_linked_reservation
ON breezeway.tasks(linked_reservation_id) WHERE linked_reservation_id IS NOT NULL;

COMMENT ON COLUMN breezeway.tasks.linked_reservation_id IS 'Breezeway reservation ID from linked_reservation field';
COMMENT ON COLUMN breezeway.tasks.linked_reservation_external_id IS 'External reservation ID (e.g., Guesty) from linked_reservation field';
```

### 1B. Properties Table — New Columns

```sql
-- Migration: 013_add_property_fields.sql

ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS bedrooms INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS bathrooms INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS living_area INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS year_built INTEGER;
```

### 1C. Reservations Table — New Columns

```sql
-- Migration: 014_add_reservation_fields.sql

ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS adults INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS children INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS pets INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS source VARCHAR(64);
```

---

## Part 2: New Tables

### 2A. Task Supplies

```sql
-- Migration: 015_create_task_supplies.sql

CREATE TABLE IF NOT EXISTS breezeway.task_supplies (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    -- IDs
    supply_usage_id BIGINT NOT NULL,  -- "id" from API (the usage record)
    supply_id BIGINT,                  -- "supply_id" from API (reference to supply)

    -- Supply details
    name VARCHAR(128),
    description VARCHAR(255),
    size VARCHAR(128),
    quantity INTEGER,
    unit_cost NUMERIC(10,2),
    total_price NUMERIC(10,2),

    -- Billing
    bill_to VARCHAR(64),
    billable BOOLEAN,
    markup_pricing_type VARCHAR(32),
    markup_rate NUMERIC(10,4),

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_task_supply UNIQUE (task_pk, supply_usage_id)
);

CREATE INDEX idx_task_supplies_task ON breezeway.task_supplies(task_pk);
CREATE INDEX idx_task_supplies_supply ON breezeway.task_supplies(supply_id);
```

### 2B. Task Costs

```sql
-- Migration: 016_create_task_costs.sql

CREATE TABLE IF NOT EXISTS breezeway.task_costs (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    -- IDs
    cost_id BIGINT NOT NULL,

    -- Cost details
    cost NUMERIC(10,2),
    description VARCHAR(255),
    bill_to VARCHAR(64),

    -- Type
    type_cost_id INTEGER,
    type_cost_code VARCHAR(64),
    type_cost_name VARCHAR(64),

    -- Timestamps
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    synced_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_task_cost UNIQUE (task_pk, cost_id)
);

CREATE INDEX idx_task_costs_task ON breezeway.task_costs(task_pk);
```

### 2C. Property Contacts

```sql
-- Migration: 017_create_property_contacts.sql

CREATE TABLE IF NOT EXISTS breezeway.property_contacts (
    id BIGSERIAL PRIMARY KEY,
    property_pk BIGINT NOT NULL REFERENCES breezeway.properties(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    contact_id BIGINT NOT NULL,
    contact_type VARCHAR(64),
    name VARCHAR(128),
    email VARCHAR(255),
    phone VARCHAR(32),

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_property_contact UNIQUE (property_pk, contact_id)
);

CREATE INDEX idx_property_contacts_property ON breezeway.property_contacts(property_pk);
```

### 2D. Reservation Tags

```sql
-- Migration: 018_create_reservation_tags.sql

CREATE TABLE IF NOT EXISTS breezeway.reservation_tags (
    id BIGSERIAL PRIMARY KEY,
    reservation_pk BIGINT NOT NULL REFERENCES breezeway.reservations(id) ON DELETE CASCADE,
    tag_pk BIGINT NOT NULL REFERENCES breezeway.tags(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    created_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_reservation_tag UNIQUE (reservation_pk, tag_pk)
);

CREATE INDEX idx_reservation_tags_reservation ON breezeway.reservation_tags(reservation_pk);
```

### 2E. Templates (Reference Data)

```sql
-- Migration: 019_create_templates.sql

CREATE TABLE IF NOT EXISTS breezeway.templates (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    template_id BIGINT NOT NULL,
    name VARCHAR(128),
    department VARCHAR(64),

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_template UNIQUE (template_id, region_code)
);
```

### 2F. Subdepartments (Reference Data)

```sql
-- Migration: 020_create_subdepartments.sql

CREATE TABLE IF NOT EXISTS breezeway.subdepartments (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    subdepartment_id INTEGER NOT NULL,
    name VARCHAR(128),

    created_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_subdepartment UNIQUE (subdepartment_id, region_code)
);
```

---

## Part 3: Config.py Updates

### 3A. Tasks Entity Updates

```python
ENTITY_CONFIGS = {
    'tasks': {
        # ... existing config ...

        'fields_mapping': {
            # EXISTING MAPPINGS (unchanged)
            'id': 'task_id',
            'home_id': 'home_id',
            'name': 'task_name',
            # ... etc ...

            # NEW MAPPINGS
            'total_cost': 'total_cost',
            'total_time': 'total_time',
            'estimated_time': 'estimated_time',
            'estimated_rate': 'estimated_rate',
            'billable': 'billable',
            'itemized_cost': 'itemized_cost',
            'task_series_id': 'task_series_id',
            'parent_task_id': 'parent_task_id',
        },

        'nested_fields': {
            # EXISTING (unchanged)
            'created_by': {'id': 'created_by_id', 'name': 'created_by_name'},
            'finished_by': {'id': 'finished_by_id', 'name': 'finished_by_name'},
            'type_task_status': {'code': 'task_status_code', 'name': 'task_status_name', 'stage': 'task_status_stage'},

            # NEW NESTED FIELDS
            'subdepartment': {
                'id': 'subdepartment_id',
                'name': 'subdepartment_name'
            },
            'template': {
                'name': 'template_name'  # We already have template_id mapped
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
        },

        'child_tables': {
            # EXISTING (unchanged)
            # 'assignments': { ... },
            # 'photos': { ... },
            # 'comments': { ... },
            # 'requirements': { ... },
            # 'task_tags': { ... },

            # NEW CHILD TABLES
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
        }
    },

    # ... other entities ...
}
```

### 3B. Properties Entity Updates

```python
'properties': {
    # ... existing config ...

    'fields_mapping': {
        # EXISTING (unchanged)
        'id': 'property_id',
        'name': 'property_name',
        # ... etc ...

        # NEW MAPPINGS
        'bedrooms': 'bedrooms',
        'bathrooms': 'bathrooms',
        'living_area': 'living_area',
        'year_built': 'year_built',
    },

    'child_tables': {
        # EXISTING
        # 'photos': { ... },

        # NEW
        'contacts': {
            'table_name': 'property_contacts',
            'requires_api_call': True,
            'endpoint_template': '/property/{property_id}/contacts',
            'parent_fk': 'property_pk',
            'parent_id_field': 'property_id',
            'natural_key': ['property_pk', 'contact_id'],
            'fields_mapping': {
                'id': 'contact_id',
                'type': 'contact_type',
                'name': 'name',
                'email': 'email',
                'phone': 'phone'
            }
        }
    }
}
```

### 3C. New Entity Configs

```python
'templates': {
    'endpoint': '/company/template',
    'api_id_field': 'id',
    'table_name': 'templates',
    'natural_key': ['template_id', 'region_code'],
    'supports_incremental': False,
    'fields_mapping': {
        'id': 'template_id',
        'name': 'name',
        'department': 'department'
    }
},

'subdepartments': {
    'endpoint': '/company/subdepartment',
    'api_id_field': 'id',
    'table_name': 'subdepartments',
    'natural_key': ['subdepartment_id', 'region_code'],
    'supports_incremental': False,
    'fields_mapping': {
        'id': 'subdepartment_id',
        'name': 'name'
    }
}
```

---

## Part 4: ETL Logic Updates

### 4A. Fix Reservation FK Resolution

Replace the date-based heuristic with direct linkage:

```python
# In etl_base.py - update _resolve_parent_fks() method

def _resolve_reservation_fk_for_tasks(self, cur):
    """Resolve reservation_pk using linked_reservation_id from API response"""
    if self.entity_type != 'tasks':
        return

    schema = DATABASE_CONFIG['schema']
    table_name = self.entity_config['table_name']

    self.logger.info("Resolving reservation_pk from linked_reservation_id")

    # Direct lookup using linked_reservation_id
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
```

### 4B. Remove/Deprecate Old Heuristic

Comment out or remove the date-matching logic:

```python
# DEPRECATED: Date-based heuristic matching
# Keep as reference but do not execute
#
# The old logic attempted to match tasks to reservations by:
# - Exact date match (checkin_date and checkout_date)
# - Scheduled date within reservation window
# - Date range overlap
#
# This is replaced by direct linked_reservation_id lookup
```

---

## Part 5: Schedule Updates

### 5A. Updated Crontab

```bash
# BREEZEWAY ETL

# Hourly: Properties, Reservations, Tasks (upgraded from daily)
0 * * * * /root/Breezeway/scripts/run_hourly_etl.sh >> /root/Breezeway/logs/cron_hourly.log 2>&1

# Daily: People, Supplies, Tags, Property Contacts
0 0 * * * /root/Breezeway/scripts/run_daily_etl.sh >> /root/Breezeway/logs/cron_daily.log 2>&1

# Weekly: Templates, Subdepartments (reference data)
0 2 * * 0 /root/Breezeway/scripts/run_weekly_etl.sh >> /root/Breezeway/logs/cron_weekly.log 2>&1
```

### 5B. Updated run_hourly_etl.sh

```bash
#!/bin/bash
# Hourly ETL: Properties, Reservations, Tasks

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"
ENTITIES="properties reservations tasks"  # Tasks upgraded to hourly

for entity in $ENTITIES; do
    for region in $REGIONS; do
        python3 etl/run_etl.py "$region" "$entity"
    done
done
```

### 5C. Updated run_daily_etl.sh

```bash
#!/bin/bash
# Daily ETL: People, Supplies, Tags, Property Contacts

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"
ENTITIES="people supplies tags"  # Removed tasks (now hourly)

for entity in $ENTITIES; do
    for region in $REGIONS; do
        python3 etl/run_etl.py "$region" "$entity"
    done
done

# Property contacts (separate loop - requires property sync first)
for region in $REGIONS; do
    python3 etl/run_etl.py "$region" property_contacts
done
```

### 5D. New run_weekly_etl.sh

```bash
#!/bin/bash
# Weekly ETL: Reference data (Templates, Subdepartments)

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"

for region in $REGIONS; do
    python3 etl/run_etl.py "$region" templates
    python3 etl/run_etl.py "$region" subdepartments
done
```

---

## Part 6: Deployment Plan

### Phase 1: Schema Migration (Low Risk)

```bash
# 1. Backup database
pg_dump -h localhost -U breezeway breezeway > ~/backup_$(date +%Y%m%d).sql

# 2. Run migrations
cd ~/Breezeway/migrations
for f in 012*.sql 013*.sql 014*.sql 015*.sql 016*.sql 017*.sql 018*.sql 019*.sql 020*.sql; do
    echo "Running $f..."
    psql -h localhost -U breezeway -d breezeway -f "$f"
done

# 3. Verify
psql -h localhost -U breezeway -d breezeway -c "\d breezeway.task_supplies"
```

### Phase 2: Config & Code Update

```bash
# 1. Update config.py (backup first)
cp ~/Breezeway/etl/config.py ~/Breezeway/etl/config.py.backup.$(date +%Y%m%d)

# 2. Update etl_base.py
cp ~/Breezeway/etl/etl_base.py ~/Breezeway/etl/etl_base.py.backup.$(date +%Y%m%d)

# 3. Test with single region
python3 ~/Breezeway/etl/run_etl.py nashville tasks
```

### Phase 3: Full Sync & Backfill

```bash
# 1. Run full sync for all regions to populate new fields
for region in nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country; do
    echo "=== Syncing $region ==="
    python3 ~/Breezeway/etl/run_etl.py "$region" tasks
done

# 2. Verify reservation linkage improvement
psql -h localhost -U breezeway -d breezeway -c "
SELECT region_code,
       COUNT(*) as total_tasks,
       COUNT(linked_reservation_id) as has_linked_res,
       COUNT(reservation_pk) as has_res_fk,
       ROUND(100.0 * COUNT(reservation_pk) / COUNT(*), 1) as pct_linked
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code;
"
```

### Phase 4: Schedule Update

```bash
# 1. Update crontab
crontab -e
# Add/modify entries per Section 5A

# 2. Deploy new scripts
chmod +x ~/Breezeway/scripts/run_weekly_etl.sh

# 3. Monitor for 24-48 hours
tail -f ~/Breezeway/logs/cron_hourly.log
```

---

## Part 7: Verification & Success Criteria

### Verification Queries

```sql
-- 1. Task-reservation linkage rate (target: >50%)
SELECT
    region_code,
    COUNT(*) as total_tasks,
    COUNT(linked_reservation_id) as has_linked_res_id,
    COUNT(reservation_pk) as has_reservation_fk,
    ROUND(100.0 * COUNT(reservation_pk) / NULLIF(COUNT(linked_reservation_id), 0), 1) as resolution_rate
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code;

-- 2. Task supplies populated
SELECT region_code, COUNT(*) as supply_records
FROM breezeway.task_supplies
GROUP BY region_code;

-- 3. Task costs populated
SELECT region_code, COUNT(*) as cost_records
FROM breezeway.task_costs
GROUP BY region_code;

-- 4. New task fields populated
SELECT
    COUNT(*) as total,
    COUNT(subdepartment_id) as has_subdept,
    COUNT(total_cost) as has_total_cost,
    COUNT(billable) as has_billable
FROM breezeway.tasks
WHERE synced_at > NOW() - INTERVAL '24 hours';
```

### Success Criteria

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Task-reservation linkage | >50% (up from ~4%) | Query 1 above |
| Task supplies table | >0 records | Query 2 above |
| Task costs table | >0 records | Query 3 above |
| New task fields | >50% populated | Query 4 above |
| ETL success rate | 100% | Check logs |
| Hourly task sync duration | <30 minutes | Check logs |

---

## Part 8: Rollback Plan

All changes are additive (new columns, new tables). Rollback is straightforward:

```bash
# If issues arise:

# 1. Revert config.py
cp ~/Breezeway/etl/config.py.backup.YYYYMMDD ~/Breezeway/etl/config.py

# 2. Revert etl_base.py
cp ~/Breezeway/etl/etl_base.py.backup.YYYYMMDD ~/Breezeway/etl/etl_base.py

# 3. Revert crontab (tasks back to daily)
crontab -e

# New tables/columns can remain - they will not affect existing functionality
```

---

## Appendix A: Complete Migration File List

```
~/Breezeway/migrations/
├── 012_add_task_fields.sql
├── 013_add_property_fields.sql
├── 014_add_reservation_fields.sql
├── 015_create_task_supplies.sql
├── 016_create_task_costs.sql
├── 017_create_property_contacts.sql
├── 018_create_reservation_tags.sql
├── 019_create_templates.sql
└── 020_create_subdepartments.sql
```

## Appendix B: API Endpoints Used

| Endpoint | Current | After |
|----------|---------|-------|
| GET /property | Hourly | Hourly (+ new fields) |
| GET /property/{id}/contacts | Not used | Daily |
| GET /reservation | Hourly | Hourly (+ new fields) |
| GET /task/?home_id=... | Daily | Hourly (+ new fields) |
| GET /task/{id}/comments | Daily | Hourly |
| GET /task/{id}/requirements | Daily | Hourly |
| GET /company/template | Not used | Weekly |
| GET /company/subdepartment | Not used | Weekly |
| GET /person | Daily | Daily |
| GET /supply | Daily | Daily |
| GET /task/tag | Daily | Daily |

---

**Document Version:** 1.0
**Last Updated:** 2026-02-02

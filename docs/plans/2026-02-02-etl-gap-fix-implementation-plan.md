# Breezeway ETL Gap Fix - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all data gaps in Breezeway ETL to achieve full data capture and accurate task-reservation linkage.

**Architecture:** Extend existing configuration-driven ETL framework with new field mappings, child table configs, and updated FK resolution logic. All changes are additive - no breaking changes to existing functionality.

**Tech Stack:** Python 3.8+, PostgreSQL 13+, psycopg2, existing ETL framework at `/root/Breezeway/etl/`

**Remote Server:** `company-database` (82.25.90.53) - all work done via SSH

---

## Task 1: Database Backup

**Files:**
- None (database operation)

**Step 1: Create backup before any changes**

```bash
ssh company-database 'pg_dump -h localhost -U breezeway breezeway > ~/breezeway_backup_$(date +%Y%m%d_%H%M).sql && ls -la ~/breezeway_backup_*.sql | tail -1'
```

Expected: Backup file created, shows file size

**Step 2: Verify backup is valid**

```bash
ssh company-database 'head -20 ~/breezeway_backup_$(date +%Y%m%d)*.sql | grep -E "(PostgreSQL|breezeway)"'
```

Expected: Shows PostgreSQL header and breezeway references

---

## Task 2: Migration 012 - Add Task Fields

**Files:**
- Create: `/root/Breezeway/migrations/012_add_task_fields.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/012_add_task_fields.sql << '\''EOF'\''
-- Migration 012: Add missing task fields
-- Date: 2026-02-02
-- Purpose: Capture linked_reservation, financial fields, subdepartment, etc.

-- Reservation linkage (THE KEY FIX)
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS linked_reservation_id BIGINT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS linked_reservation_external_id VARCHAR(50);

-- Financial fields
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS total_cost NUMERIC(10,2);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS total_time VARCHAR(32);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS estimated_time VARCHAR(32);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS estimated_rate NUMERIC(10,2);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS billable BOOLEAN;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS itemized_cost BOOLEAN;

-- Subdepartment
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS subdepartment_id INTEGER;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS subdepartment_name VARCHAR(128);

-- Summary
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS summary_note TEXT;

-- Template name (we have ID already)
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS template_name VARCHAR(128);

-- Task hierarchy
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS task_series_id BIGINT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS parent_task_id BIGINT;

-- Requested by
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS requested_by_id INTEGER;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS requested_by_name VARCHAR(128);

-- Index for reservation linkage queries
CREATE INDEX IF NOT EXISTS idx_tasks_linked_reservation
ON breezeway.tasks(linked_reservation_id) WHERE linked_reservation_id IS NOT NULL;

-- Comments
COMMENT ON COLUMN breezeway.tasks.linked_reservation_id IS '\''Breezeway reservation ID from linked_reservation field'\'';
COMMENT ON COLUMN breezeway.tasks.linked_reservation_external_id IS '\''External reservation ID (e.g., Guesty) from linked_reservation field'\'';

SELECT '\''Migration 012 complete: Task fields added'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/012_add_task_fields.sql'
```

Expected: Multiple "ALTER TABLE" and final "Migration 012 complete" message

**Step 3: Verify columns exist**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT column_name FROM information_schema.columns WHERE table_schema='\''breezeway'\'' AND table_name='\''tasks'\'' AND column_name LIKE '\''linked%'\'' OR column_name LIKE '\''subdep%'\'' ORDER BY column_name;"'
```

Expected: Shows linked_reservation_id, linked_reservation_external_id, subdepartment_id, subdepartment_name

**Step 4: Commit migration file**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/012_add_task_fields.sql && git commit -m "migration: 012 add task fields (linkage, financial, subdepartment)"'
```

---

## Task 3: Migration 013 - Add Property Fields

**Files:**
- Create: `/root/Breezeway/migrations/013_add_property_fields.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/013_add_property_fields.sql << '\''EOF'\''
-- Migration 013: Add missing property fields
-- Date: 2026-02-02

ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS bedrooms INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS bathrooms INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS living_area INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS year_built INTEGER;

SELECT '\''Migration 013 complete: Property fields added'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/013_add_property_fields.sql'
```

Expected: "Migration 013 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/013_add_property_fields.sql && git commit -m "migration: 013 add property fields (bedrooms, bathrooms, etc)"'
```

---

## Task 4: Migration 014 - Add Reservation Fields

**Files:**
- Create: `/root/Breezeway/migrations/014_add_reservation_fields.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/014_add_reservation_fields.sql << '\''EOF'\''
-- Migration 014: Add missing reservation fields
-- Date: 2026-02-02

ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS adults INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS children INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS pets INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS source VARCHAR(64);

SELECT '\''Migration 014 complete: Reservation fields added'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/014_add_reservation_fields.sql'
```

Expected: "Migration 014 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/014_add_reservation_fields.sql && git commit -m "migration: 014 add reservation fields (adults, children, pets, source)"'
```

---

## Task 5: Migration 015 - Create Task Supplies Table

**Files:**
- Create: `/root/Breezeway/migrations/015_create_task_supplies.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/015_create_task_supplies.sql << '\''EOF'\''
-- Migration 015: Create task_supplies table
-- Date: 2026-02-02

CREATE TABLE IF NOT EXISTS breezeway.task_supplies (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    -- IDs
    supply_usage_id BIGINT NOT NULL,
    supply_id BIGINT,

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

CREATE INDEX IF NOT EXISTS idx_task_supplies_task ON breezeway.task_supplies(task_pk);
CREATE INDEX IF NOT EXISTS idx_task_supplies_supply ON breezeway.task_supplies(supply_id);

SELECT '\''Migration 015 complete: task_supplies table created'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/015_create_task_supplies.sql'
```

Expected: "Migration 015 complete"

**Step 3: Verify table**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "\d breezeway.task_supplies"'
```

Expected: Table structure with all columns

**Step 4: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/015_create_task_supplies.sql && git commit -m "migration: 015 create task_supplies table"'
```

---

## Task 6: Migration 016 - Create Task Costs Table

**Files:**
- Create: `/root/Breezeway/migrations/016_create_task_costs.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/016_create_task_costs.sql << '\''EOF'\''
-- Migration 016: Create task_costs table
-- Date: 2026-02-02

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

CREATE INDEX IF NOT EXISTS idx_task_costs_task ON breezeway.task_costs(task_pk);

SELECT '\''Migration 016 complete: task_costs table created'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/016_create_task_costs.sql'
```

Expected: "Migration 016 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/016_create_task_costs.sql && git commit -m "migration: 016 create task_costs table"'
```

---

## Task 7: Migration 017 - Create Property Contacts Table

**Files:**
- Create: `/root/Breezeway/migrations/017_create_property_contacts.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/017_create_property_contacts.sql << '\''EOF'\''
-- Migration 017: Create property_contacts table
-- Date: 2026-02-02

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

CREATE INDEX IF NOT EXISTS idx_property_contacts_property ON breezeway.property_contacts(property_pk);

SELECT '\''Migration 017 complete: property_contacts table created'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/017_create_property_contacts.sql'
```

Expected: "Migration 017 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/017_create_property_contacts.sql && git commit -m "migration: 017 create property_contacts table"'
```

---

## Task 8: Migration 018 - Create Reservation Tags Table

**Files:**
- Create: `/root/Breezeway/migrations/018_create_reservation_tags.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/018_create_reservation_tags.sql << '\''EOF'\''
-- Migration 018: Create reservation_tags table
-- Date: 2026-02-02

CREATE TABLE IF NOT EXISTS breezeway.reservation_tags (
    id BIGSERIAL PRIMARY KEY,
    reservation_pk BIGINT NOT NULL REFERENCES breezeway.reservations(id) ON DELETE CASCADE,
    tag_pk BIGINT NOT NULL REFERENCES breezeway.tags(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    created_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_reservation_tag UNIQUE (reservation_pk, tag_pk)
);

CREATE INDEX IF NOT EXISTS idx_reservation_tags_reservation ON breezeway.reservation_tags(reservation_pk);

SELECT '\''Migration 018 complete: reservation_tags table created'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/018_create_reservation_tags.sql'
```

Expected: "Migration 018 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/018_create_reservation_tags.sql && git commit -m "migration: 018 create reservation_tags table"'
```

---

## Task 9: Migration 019 - Create Templates Table

**Files:**
- Create: `/root/Breezeway/migrations/019_create_templates.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/019_create_templates.sql << '\''EOF'\''
-- Migration 019: Create templates table
-- Date: 2026-02-02

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

SELECT '\''Migration 019 complete: templates table created'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/019_create_templates.sql'
```

Expected: "Migration 019 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/019_create_templates.sql && git commit -m "migration: 019 create templates table"'
```

---

## Task 10: Migration 020 - Create Subdepartments Table

**Files:**
- Create: `/root/Breezeway/migrations/020_create_subdepartments.sql`

**Step 1: Create migration file**

```bash
ssh company-database 'cat > ~/Breezeway/migrations/020_create_subdepartments.sql << '\''EOF'\''
-- Migration 020: Create subdepartments table
-- Date: 2026-02-02

CREATE TABLE IF NOT EXISTS breezeway.subdepartments (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,

    subdepartment_id INTEGER NOT NULL,
    name VARCHAR(128),

    created_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT uq_subdepartment UNIQUE (subdepartment_id, region_code)
);

SELECT '\''Migration 020 complete: subdepartments table created'\'';
EOF'
```

**Step 2: Run migration**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -f ~/Breezeway/migrations/020_create_subdepartments.sql'
```

Expected: "Migration 020 complete"

**Step 3: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add migrations/020_create_subdepartments.sql && git commit -m "migration: 020 create subdepartments table"'
```

---

## Task 11: Verify All Migrations

**Step 1: List all tables in breezeway schema**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT table_name FROM information_schema.tables WHERE table_schema='\''breezeway'\'' ORDER BY table_name;"'
```

Expected: Should include new tables: property_contacts, reservation_tags, subdepartments, task_costs, task_supplies, templates

**Step 2: Verify task table has new columns**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT column_name FROM information_schema.columns WHERE table_schema='\''breezeway'\'' AND table_name='\''tasks'\'' ORDER BY ordinal_position;" | wc -l'
```

Expected: Count should be ~50 (was ~34 before)

---

## Task 12: Backup config.py

**Files:**
- Backup: `/root/Breezeway/etl/config.py`

**Step 1: Create backup**

```bash
ssh company-database 'cp ~/Breezeway/etl/config.py ~/Breezeway/etl/config.py.backup.$(date +%Y%m%d)'
```

**Step 2: Verify backup**

```bash
ssh company-database 'ls -la ~/Breezeway/etl/config.py*'
```

Expected: Shows original and backup file

---

## Task 13: Update config.py - Task Fields Mapping

**Files:**
- Modify: `/root/Breezeway/etl/config.py`

**Step 1: Read current tasks fields_mapping section**

```bash
ssh company-database 'grep -n "fields_mapping" ~/Breezeway/etl/config.py | head -5'
```

Note the line numbers for tasks fields_mapping

**Step 2: Add new task field mappings**

Add these lines to the tasks `fields_mapping` dict (after existing mappings, before the closing brace):

```python
            # NEW: Financial fields
            'total_cost': 'total_cost',
            'total_time': 'total_time',
            'estimated_time': 'estimated_time',
            'estimated_rate': 'estimated_rate',
            'billable': 'billable',
            'itemized_cost': 'itemized_cost',
            # NEW: Task hierarchy
            'task_series_id': 'task_series_id',
            'parent_task_id': 'parent_task_id',
```

**Step 3: Add new nested_fields for tasks**

Add to tasks `nested_fields` dict:

```python
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
            },
```

**Step 4: Add supplies child table config**

Add to tasks `child_tables` dict:

```python
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
```

**Step 5: Add costs child table config**

Add to tasks `child_tables` dict:

```python
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
            },
```

**Step 6: Verify syntax**

```bash
ssh company-database 'cd ~/Breezeway && python3 -c "from etl.config import ENTITY_CONFIGS; print(\"Config valid\")"'
```

Expected: "Config valid" (no syntax errors)

**Step 7: Commit config changes**

```bash
ssh company-database 'cd ~/Breezeway && git add etl/config.py && git commit -m "config: add task fields, supplies, costs mappings"'
```

---

## Task 14: Update config.py - Property Fields

**Files:**
- Modify: `/root/Breezeway/etl/config.py`

**Step 1: Add property field mappings**

Add to properties `fields_mapping`:

```python
            'bedrooms': 'bedrooms',
            'bathrooms': 'bathrooms',
            'living_area': 'living_area',
            'year_built': 'year_built',
```

**Step 2: Verify and commit**

```bash
ssh company-database 'cd ~/Breezeway && python3 -c "from etl.config import ENTITY_CONFIGS; print(ENTITY_CONFIGS[\"properties\"][\"fields_mapping\"].get(\"bedrooms\"))"'
```

Expected: "bedrooms"

```bash
ssh company-database 'cd ~/Breezeway && git add etl/config.py && git commit -m "config: add property fields (bedrooms, bathrooms, etc)"'
```

---

## Task 15: Update config.py - Reservation Fields

**Files:**
- Modify: `/root/Breezeway/etl/config.py`

**Step 1: Add reservation field mappings**

Add to reservations `fields_mapping`:

```python
            'adults': 'adults',
            'children': 'children',
            'pets': 'pets',
            'source': 'source',
```

**Step 2: Verify and commit**

```bash
ssh company-database 'cd ~/Breezeway && python3 -c "from etl.config import ENTITY_CONFIGS; print(ENTITY_CONFIGS[\"reservations\"][\"fields_mapping\"].get(\"adults\"))"'
```

Expected: "adults"

```bash
ssh company-database 'cd ~/Breezeway && git add etl/config.py && git commit -m "config: add reservation fields (adults, children, pets, source)"'
```

---

## Task 16: Backup etl_base.py

**Files:**
- Backup: `/root/Breezeway/etl/etl_base.py`

**Step 1: Create backup**

```bash
ssh company-database 'cp ~/Breezeway/etl/etl_base.py ~/Breezeway/etl/etl_base.py.backup.$(date +%Y%m%d)'
```

---

## Task 17: Update etl_base.py - Fix Reservation FK Resolution

**Files:**
- Modify: `/root/Breezeway/etl/etl_base.py`

**Step 1: Find the current reservation FK resolution code**

```bash
ssh company-database 'grep -n "reservation_pk" ~/Breezeway/etl/etl_base.py | head -10'
```

Note the line numbers

**Step 2: Replace heuristic matching with direct linkage**

Find the section that does date-based matching and replace with:

```python
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

**Step 3: Verify syntax**

```bash
ssh company-database 'cd ~/Breezeway && python3 -c "from etl.etl_base import BreezewayETL; print(\"ETL base valid\")"'
```

Expected: "ETL base valid"

**Step 4: Commit**

```bash
ssh company-database 'cd ~/Breezeway && git add etl/etl_base.py && git commit -m "fix: replace date heuristic with linked_reservation_id for task-reservation FK"'
```

---

## Task 18: Test Single Region ETL

**Step 1: Run task ETL for Nashville**

```bash
ssh company-database 'cd ~/Breezeway && python3 etl/run_etl.py nashville tasks 2>&1 | tail -30'
```

Expected: ETL completes successfully, shows records processed

**Step 2: Verify new fields populated**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT COUNT(*) as total, COUNT(linked_reservation_id) as has_linked_res, COUNT(total_time) as has_total_time FROM breezeway.tasks WHERE region_code='\''nashville'\'' AND synced_at > NOW() - INTERVAL '\''1 hour'\'';"'
```

Expected: Shows counts with has_linked_res > 0

**Step 3: Verify supplies captured**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT COUNT(*) FROM breezeway.task_supplies WHERE region_code='\''nashville'\'';"'
```

Expected: Count > 0

**Step 4: Verify costs captured**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT COUNT(*) FROM breezeway.task_costs WHERE region_code='\''nashville'\'';"'
```

Expected: Count > 0 (or 0 if no costs exist in Nashville data)

---

## Task 19: Run Full Task Sync for All Regions

**Step 1: Run task ETL for all regions**

```bash
ssh company-database 'cd ~/Breezeway && for region in nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country; do echo "=== $region ===" && python3 etl/run_etl.py "$region" tasks 2>&1 | tail -5; done'
```

Expected: All 8 regions complete successfully

**Step 2: Verify overall linkage improvement**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "
SELECT region_code,
       COUNT(*) as total_tasks,
       COUNT(linked_reservation_id) as has_linked_res,
       COUNT(reservation_pk) as has_res_fk,
       ROUND(100.0 * COUNT(reservation_pk) / NULLIF(COUNT(*), 0), 1) as pct_linked
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code;
"'
```

Expected: pct_linked should be significantly higher than the ~4% baseline

---

## Task 20: Update Cron Scripts

**Files:**
- Modify: `/root/Breezeway/scripts/run_hourly_etl.sh`
- Modify: `/root/Breezeway/scripts/run_daily_etl.sh`
- Create: `/root/Breezeway/scripts/run_weekly_etl.sh`

**Step 1: Update hourly script to include tasks**

```bash
ssh company-database 'cat > ~/Breezeway/scripts/run_hourly_etl.sh << '\''EOF'\''
#!/bin/bash
# Hourly ETL: Properties, Reservations, Tasks (tasks upgraded from daily)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/hourly_etl_$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name "hourly_etl_*.log" -mtime +30 -delete

log() { echo "[$(date '\''+%Y-%m-%d %H:%M:%S'\'')] $*" | tee -a "$LOG_FILE"; }

log "=========================================================================="
log "HOURLY ETL START"
log "=========================================================================="

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"
ENTITIES="properties reservations tasks"

TOTAL_JOBS=0
FAILED_JOBS=0

for entity in $ENTITIES; do
    log "Starting $entity ETL..."
    for region in $REGIONS; do
        log "  → Running: $region / $entity"
        TOTAL_JOBS=$((TOTAL_JOBS + 1))
        cd "$PROJECT_DIR"
        python3 etl/run_etl.py "$region" "$entity" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log "  ✓ SUCCESS: $region / $entity"
        else
            log "  ✗ FAILED: $region / $entity"
            FAILED_JOBS=$((FAILED_JOBS + 1))
        fi
    done
done

log "=========================================================================="
log "HOURLY ETL COMPLETE - Total: $TOTAL_JOBS, Failed: $FAILED_JOBS"
log "=========================================================================="

[ $FAILED_JOBS -gt 0 ] && exit 1
EOF
chmod +x ~/Breezeway/scripts/run_hourly_etl.sh'
```

**Step 2: Update daily script (remove tasks)**

```bash
ssh company-database 'cat > ~/Breezeway/scripts/run_daily_etl.sh << '\''EOF'\''
#!/bin/bash
# Daily ETL: People, Supplies, Tags (tasks moved to hourly)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/daily_etl_$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name "daily_etl_*.log" -mtime +30 -delete

log() { echo "[$(date '\''+%Y-%m-%d %H:%M:%S'\'')] $*" | tee -a "$LOG_FILE"; }

log "=========================================================================="
log "DAILY ETL START"
log "=========================================================================="

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"
ENTITIES="people supplies tags"

TOTAL_JOBS=0
FAILED_JOBS=0

for entity in $ENTITIES; do
    log "Starting $entity ETL..."
    for region in $REGIONS; do
        log "  → Running: $region / $entity"
        TOTAL_JOBS=$((TOTAL_JOBS + 1))
        cd "$PROJECT_DIR"
        python3 etl/run_etl.py "$region" "$entity" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log "  ✓ SUCCESS: $region / $entity"
        else
            log "  ✗ FAILED: $region / $entity"
            FAILED_JOBS=$((FAILED_JOBS + 1))
        fi
    done
done

log "=========================================================================="
log "DAILY ETL COMPLETE - Total: $TOTAL_JOBS, Failed: $FAILED_JOBS"
log "=========================================================================="

[ $FAILED_JOBS -gt 0 ] && exit 1
EOF
chmod +x ~/Breezeway/scripts/run_daily_etl.sh'
```

**Step 3: Create weekly script**

```bash
ssh company-database 'cat > ~/Breezeway/scripts/run_weekly_etl.sh << '\''EOF'\''
#!/bin/bash
# Weekly ETL: Templates, Subdepartments (reference data)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/weekly_etl_$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() { echo "[$(date '\''+%Y-%m-%d %H:%M:%S'\'')] $*" | tee -a "$LOG_FILE"; }

log "=========================================================================="
log "WEEKLY ETL START - Reference Data"
log "=========================================================================="

REGIONS="nashville austin smoky hilton_head breckenridge sea_ranch mammoth hill_country"
ENTITIES="templates subdepartments"

for entity in $ENTITIES; do
    log "Starting $entity ETL..."
    for region in $REGIONS; do
        log "  → Running: $region / $entity"
        cd "$PROJECT_DIR"
        python3 etl/run_etl.py "$region" "$entity" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log "  ✓ SUCCESS: $region / $entity"
        else
            log "  ✗ FAILED: $region / $entity"
        fi
    done
done

log "=========================================================================="
log "WEEKLY ETL COMPLETE"
log "=========================================================================="
EOF
chmod +x ~/Breezeway/scripts/run_weekly_etl.sh'
```

**Step 4: Commit scripts**

```bash
ssh company-database 'cd ~/Breezeway && git add scripts/run_hourly_etl.sh scripts/run_daily_etl.sh scripts/run_weekly_etl.sh && git commit -m "scripts: update ETL schedules (tasks to hourly, add weekly)"'
```

---

## Task 21: Update Crontab

**Step 1: View current crontab**

```bash
ssh company-database 'crontab -l | grep -i breeze'
```

**Step 2: Update crontab**

```bash
ssh company-database 'crontab -l > /tmp/crontab.bak && cat /tmp/crontab.bak | grep -v "Breezeway" | grep -v "run_hourly_etl" | grep -v "run_daily_etl" > /tmp/crontab.new && echo "
# BREEZEWAY ETL
0 * * * * /root/Breezeway/scripts/run_hourly_etl.sh >> /root/Breezeway/logs/cron_hourly.log 2>&1
0 0 * * * /root/Breezeway/scripts/run_daily_etl.sh >> /root/Breezeway/logs/cron_daily.log 2>&1
0 2 * * 0 /root/Breezeway/scripts/run_weekly_etl.sh >> /root/Breezeway/logs/cron_weekly.log 2>&1
" >> /tmp/crontab.new && crontab /tmp/crontab.new'
```

**Step 3: Verify crontab**

```bash
ssh company-database 'crontab -l | grep -i breeze'
```

Expected: Shows 3 Breezeway cron entries (hourly, daily, weekly)

---

## Task 22: Final Verification

**Step 1: Task-reservation linkage check**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "
SELECT
    region_code,
    COUNT(*) as total,
    COUNT(linked_reservation_id) as has_link_id,
    COUNT(reservation_pk) as has_fk,
    ROUND(100.0 * COUNT(reservation_pk) / NULLIF(COUNT(linked_reservation_id), 0), 1) as resolution_pct
FROM breezeway.tasks
GROUP BY region_code
ORDER BY region_code;
"'
```

**Step 2: Task supplies check**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT region_code, COUNT(*) FROM breezeway.task_supplies GROUP BY region_code ORDER BY region_code;"'
```

**Step 3: Task costs check**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "SELECT region_code, COUNT(*) FROM breezeway.task_costs GROUP BY region_code ORDER BY region_code;"'
```

**Step 4: New fields populated check**

```bash
ssh company-database 'PGPASSWORD=breezeway2025user psql -h localhost -U breezeway -d breezeway -c "
SELECT
    COUNT(*) as total,
    COUNT(total_time) as has_total_time,
    COUNT(subdepartment_id) as has_subdept,
    COUNT(billable) as has_billable
FROM breezeway.tasks
WHERE synced_at > NOW() - INTERVAL '\''24 hours'\'';
"'
```

---

## Task 23: Final Commit and Push

**Step 1: Final commit**

```bash
ssh company-database 'cd ~/Breezeway && git status'
```

If any uncommitted changes:

```bash
ssh company-database 'cd ~/Breezeway && git add -A && git commit -m "feat: complete ETL gap fix implementation"'
```

**Step 2: Push to origin**

```bash
ssh company-database 'cd ~/Breezeway && git push origin main'
```

---

## Success Criteria Checklist

- [ ] Task-reservation linkage rate > 50% (up from ~4%)
- [ ] task_supplies table has records
- [ ] task_costs table has records
- [ ] New task fields populated (total_time, subdepartment, billable)
- [ ] Hourly ETL includes tasks
- [ ] Weekly ETL created for reference data
- [ ] All migrations committed
- [ ] No ETL failures in logs

---

**Document Version:** 1.0
**Created:** 2026-02-02

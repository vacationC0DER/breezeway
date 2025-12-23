-- Migration 008: Add remaining Breezeway API entities
-- Adds: People, Supplies, Task Requirements, Task Tags

-- ============================================================================
-- PEOPLE TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS breezeway.people (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL,
    person_id VARCHAR(64) NOT NULL,
    person_name VARCHAR(255),
    active BOOLEAN,
    accept_decline_tasks BOOLEAN,
    availability_monday JSONB,
    availability_tuesday JSONB,
    availability_wednesday JSONB,
    availability_thursday JSONB,
    availability_friday JSONB,
    availability_saturday JSONB,
    availability_sunday JSONB,
    last_sync_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_people_region FOREIGN KEY (region_code)
        REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    CONSTRAINT uq_people_natural_key UNIQUE (person_id, region_code)
);

CREATE INDEX idx_people_region ON breezeway.people(region_code);
CREATE INDEX idx_people_active ON breezeway.people(active);

-- ============================================================================
-- SUPPLIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS breezeway.supplies (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL,
    supply_id VARCHAR(64) NOT NULL,
    company_id VARCHAR(64),
    supply_name VARCHAR(255),
    description TEXT,
    size VARCHAR(255),
    internal_id VARCHAR(255),
    unit_cost NUMERIC(10, 2),
    stock_count INTEGER,
    low_stock_alert BOOLEAN,
    low_stock_count INTEGER,
    supply_category_id VARCHAR(64),
    stock_status_code VARCHAR(64),
    stock_status_name VARCHAR(255),
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    last_sync_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_supplies_region FOREIGN KEY (region_code)
        REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    CONSTRAINT uq_supplies_natural_key UNIQUE (supply_id, region_code)
);

CREATE INDEX idx_supplies_region ON breezeway.supplies(region_code);
CREATE INDEX idx_supplies_stock_status ON breezeway.supplies(stock_status_code);
CREATE INDEX idx_supplies_category ON breezeway.supplies(supply_category_id);

-- ============================================================================
-- TASK REQUIREMENTS TABLE (child of tasks)
-- ============================================================================
CREATE TABLE IF NOT EXISTS breezeway.task_requirements (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL,
    region_code VARCHAR(32) NOT NULL,
    requirement_id VARCHAR(64),
    section_name VARCHAR(255),
    action JSONB,
    response VARCHAR(255),
    type_requirement VARCHAR(64),
    photo_required BOOLEAN,
    photos JSONB,
    note TEXT,
    home_element_name VARCHAR(255),
    last_sync_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_requirement_task FOREIGN KEY (task_pk)
        REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_requirement_region FOREIGN KEY (region_code)
        REFERENCES breezeway.regions(region_code) ON DELETE CASCADE
);

CREATE INDEX idx_task_requirements_task_pk ON breezeway.task_requirements(task_pk);
CREATE INDEX idx_task_requirements_region ON breezeway.task_requirements(region_code);
CREATE INDEX idx_task_requirements_type ON breezeway.task_requirements(type_requirement);

-- ============================================================================
-- TASK TAGS TABLES
-- ============================================================================

-- Tag definitions (company-wide available tags)
CREATE TABLE IF NOT EXISTS breezeway.tags (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL,
    tag_id VARCHAR(64) NOT NULL,
    tag_name VARCHAR(255),
    tag_description TEXT,
    last_sync_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_tags_region FOREIGN KEY (region_code)
        REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    CONSTRAINT uq_tags_natural_key UNIQUE (tag_id, region_code)
);

CREATE INDEX idx_tags_region ON breezeway.tags(region_code);

-- Many-to-many relationship: tasks <-> tags
CREATE TABLE IF NOT EXISTS breezeway.task_tags (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL,
    tag_pk BIGINT NOT NULL,
    region_code VARCHAR(32) NOT NULL,
    last_sync_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_task_tags_task FOREIGN KEY (task_pk)
        REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_task_tags_tag FOREIGN KEY (tag_pk)
        REFERENCES breezeway.tags(id) ON DELETE CASCADE,
    CONSTRAINT fk_task_tags_region FOREIGN KEY (region_code)
        REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    CONSTRAINT uq_task_tags UNIQUE (task_pk, tag_pk)
);

CREATE INDEX idx_task_tags_task ON breezeway.task_tags(task_pk);
CREATE INDEX idx_task_tags_tag ON breezeway.task_tags(tag_pk);
CREATE INDEX idx_task_tags_region ON breezeway.task_tags(region_code);

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Tables added:
--   1. people (team members with availability)
--   2. supplies (inventory management)
--   3. task_requirements (task completion responses/checklists)
--   4. tags (available tags lookup)
--   5. task_tags (many-to-many: tasks <-> tags)

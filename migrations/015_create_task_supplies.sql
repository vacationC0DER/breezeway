-- Migration 015: Create task_supplies table
-- Tracks supplies used for tasks with cost and billing info

CREATE TABLE IF NOT EXISTS breezeway.task_supplies (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    supply_usage_id BIGINT NOT NULL,
    supply_id BIGINT,
    name VARCHAR(128),
    description VARCHAR(255),
    size VARCHAR(128),
    quantity INTEGER,
    unit_cost NUMERIC(10,2),
    total_price NUMERIC(10,2),
    bill_to VARCHAR(64),
    billable BOOLEAN,
    markup_pricing_type VARCHAR(32),
    markup_rate NUMERIC(10,4),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_task_supply UNIQUE (task_pk, supply_usage_id)
);
CREATE INDEX IF NOT EXISTS idx_task_supplies_task ON breezeway.task_supplies(task_pk);
CREATE INDEX IF NOT EXISTS idx_task_supplies_supply ON breezeway.task_supplies(supply_id);

-- Migration 016: Create task_costs table
-- Tracks additional costs associated with tasks

CREATE TABLE IF NOT EXISTS breezeway.task_costs (
    id BIGSERIAL PRIMARY KEY,
    task_pk BIGINT NOT NULL REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    cost_id BIGINT NOT NULL,
    cost NUMERIC(10,2),
    description VARCHAR(255),
    bill_to VARCHAR(64),
    type_cost_id INTEGER,
    type_cost_code VARCHAR(64),
    type_cost_name VARCHAR(64),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    synced_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_task_cost UNIQUE (task_pk, cost_id)
);
CREATE INDEX IF NOT EXISTS idx_task_costs_task ON breezeway.task_costs(task_pk);

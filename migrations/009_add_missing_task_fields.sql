-- Migration 009: Add missing task fields from API response
-- Adds: type_department, type_priority, scheduled fields, status breakdown, etc.

ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS type_department VARCHAR(64);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS type_priority VARCHAR(64);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS scheduled_date DATE;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS scheduled_time TIME;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS report_url TEXT;
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS reference_property_id VARCHAR(255);

-- Task status breakdown (from type_task_status nested object)
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS task_status_code VARCHAR(64);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS task_status_name VARCHAR(255);
ALTER TABLE breezeway.tasks ADD COLUMN IF NOT EXISTS task_status_stage VARCHAR(64);

-- Create indexes for new columns
CREATE INDEX IF NOT EXISTS idx_tasks_department ON breezeway.tasks(type_department);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON breezeway.tasks(type_priority);
CREATE INDEX IF NOT EXISTS idx_tasks_scheduled_date ON breezeway.tasks(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_tasks_status_code ON breezeway.tasks(task_status_code);

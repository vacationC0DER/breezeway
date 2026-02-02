-- Migration 012: Add Task Fields
-- Adds linked reservation tracking, cost/time estimates, and organizational fields

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
CREATE INDEX IF NOT EXISTS idx_tasks_linked_reservation ON breezeway.tasks(linked_reservation_id) WHERE linked_reservation_id IS NOT NULL;

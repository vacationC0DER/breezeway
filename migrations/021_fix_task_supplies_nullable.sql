-- Fix: Make supply_usage_id nullable since API returns null values
-- Run: sudo -u postgres psql -d breezeway -f ~/Breezeway/migrations/021_fix_task_supplies_nullable.sql

ALTER TABLE breezeway.task_supplies ALTER COLUMN supply_usage_id DROP NOT NULL;

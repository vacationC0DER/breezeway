-- Migration 021: Fix nullable constraints for child table IDs
-- These IDs can be null when API returns partial/empty records

-- Make supply_usage_id nullable (already done via ALTER)
-- ALTER TABLE breezeway.task_supplies ALTER COLUMN supply_usage_id DROP NOT NULL;

-- Make cost_id nullable (already done via ALTER)
-- ALTER TABLE breezeway.task_costs ALTER COLUMN cost_id DROP NOT NULL;

-- Note: These ALTER statements were run manually during the ETL fix process
-- This migration file documents the change for future reference

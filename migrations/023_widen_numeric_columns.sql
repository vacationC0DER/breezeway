-- Migration 023: Widen numeric(10,2) columns to numeric(15,2)
-- Applied: 2026-02-22
-- Fixes: "numeric field overflow" error for Mammoth task sync
-- Error: "A field with precision 10, scale 2 must round to an absolute value less than 10^8"
-- Root cause: Breezeway API returning values >= 100,000,000 in monetary fields

-- tasks
ALTER TABLE breezeway.tasks ALTER COLUMN rate_paid TYPE NUMERIC(15,2);
ALTER TABLE breezeway.tasks ALTER COLUMN total_cost TYPE NUMERIC(15,2);
ALTER TABLE breezeway.tasks ALTER COLUMN estimated_rate TYPE NUMERIC(15,2);

-- task_supplies
ALTER TABLE breezeway.task_supplies ALTER COLUMN unit_cost TYPE NUMERIC(15,2);
ALTER TABLE breezeway.task_supplies ALTER COLUMN total_price TYPE NUMERIC(15,2);
ALTER TABLE breezeway.task_supplies ALTER COLUMN markup_rate TYPE NUMERIC(15,4);

-- task_costs
ALTER TABLE breezeway.task_costs ALTER COLUMN cost TYPE NUMERIC(15,2);

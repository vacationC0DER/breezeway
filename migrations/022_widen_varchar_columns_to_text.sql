-- Migration 022: Widen varchar(255) columns to TEXT on task-related tables
-- Applied: 2026-02-22
-- Fixes: "value too long for type character varying(255)" errors
-- Affected regions: Breckenridge and Mammoth task syncs failing since 2026-02-03
-- Root cause: Breezeway API returns free-form text fields that can exceed 255 chars
--
-- NOTE: This migration requires dropping and recreating all dependent views
-- (26 regular views + 33 materialized views). The apply script handles this
-- automatically by saving definitions, dropping in dependency order, altering
-- columns, and recreating in reverse dependency order.
--
-- 12 analytics materialized views that depend on reviews_data were recreated
-- WITH NO DATA due to permission constraints on that table. They will
-- repopulate on next scheduled REFRESH.

-- task_requirements: response is the confirmed culprit (max_used = 255, new data exceeds it)
ALTER TABLE breezeway.task_requirements ALTER COLUMN response TYPE TEXT;
ALTER TABLE breezeway.task_requirements ALTER COLUMN section_name TYPE TEXT;
ALTER TABLE breezeway.task_requirements ALTER COLUMN home_element_name TYPE TEXT;

-- task_costs: description is at 219 chars and growing
ALTER TABLE breezeway.task_costs ALTER COLUMN description TYPE TEXT;

-- task_supplies: description could also grow
ALTER TABLE breezeway.task_supplies ALTER COLUMN description TYPE TEXT;

-- tasks: free-form name/status fields
ALTER TABLE breezeway.tasks ALTER COLUMN task_name TYPE TEXT;
ALTER TABLE breezeway.tasks ALTER COLUMN created_by_name TYPE TEXT;
ALTER TABLE breezeway.tasks ALTER COLUMN finished_by_name TYPE TEXT;
ALTER TABLE breezeway.tasks ALTER COLUMN reference_property_id TYPE TEXT;
ALTER TABLE breezeway.tasks ALTER COLUMN task_status_name TYPE TEXT;

-- task_comments: author_name
ALTER TABLE breezeway.task_comments ALTER COLUMN author_name TYPE TEXT;

-- task_assignments: assignee_name
ALTER TABLE breezeway.task_assignments ALTER COLUMN assignee_name TYPE TEXT;

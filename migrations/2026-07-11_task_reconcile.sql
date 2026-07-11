-- Delete-reconcile backstop state for breezeway.tasks.
-- The webhook is the sole delete path; all ETL is upsert-only. This adds
-- confirm-twice strike tracking + an audit log for the nightly sweep that
-- removes phantom tasks left behind by a dropped task-deleted webhook.
-- Additive only; the gw_edw FDW foreign table has a fixed column list and is
-- unaffected by new source columns.

ALTER TABLE breezeway.tasks
  ADD COLUMN IF NOT EXISTS webhook_missing_strikes smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS webhook_missing_since timestamptz;

CREATE TABLE IF NOT EXISTS breezeway.task_reconcile_deletes (
  id            bigserial PRIMARY KEY,
  deleted_at    timestamptz NOT NULL DEFAULT now(),
  region_code   varchar,
  task_id       varchar,
  task_name     text,
  scheduled_date date,
  reason        text,
  task_row      jsonb
);

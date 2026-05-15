-- ============================================================================
-- Migration 033: Fix ownership on tenants + tenant_regions
-- ============================================================================
-- 032 created the tables while connected as postgres, so they were owned by
-- postgres. The runtime user (breezeway) needs DML, so ownership must move.
-- Without this fix breezeway-admin.service can't INSERT/UPDATE these tables.
-- Date: 2026-05-15
-- ============================================================================

ALTER TABLE breezeway.tenants        OWNER TO breezeway;
ALTER TABLE breezeway.tenant_regions OWNER TO breezeway;

-- Verify
SELECT tablename, tableowner
FROM pg_tables
WHERE schemaname='breezeway' AND tablename IN ('tenants','tenant_regions');

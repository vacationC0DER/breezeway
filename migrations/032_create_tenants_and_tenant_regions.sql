-- ============================================================================
-- Migration 032: Tenants + Tenant Regions
-- ============================================================================
-- Description: Source-of-truth tables for multi-tenant Breezeway ETL.
--              Replaces the hardcoded REGIONS dict in etl/config.py so the
--              frontend onboarding wizard can add new tenants/regions without
--              code changes.
-- Date: 2026-05-15
-- Companion docs/plans/2026-05-15-breezeway-tenant-onboarding.md
-- ============================================================================
-- Run target: company-database.tail5089ad.ts.net, database = breezeway
-- Run as: sudo -u postgres psql -d breezeway -f 032_create_tenants_and_tenant_regions.sql
-- Idempotent: yes (uses IF NOT EXISTS / DO blocks)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. tenants
-- ----------------------------------------------------------------------------
-- id matches Supabase public.client.client_id (integer, not uuid).
-- One row per VR Goals customer (NOT per region — a tenant may have N regions).

CREATE TABLE IF NOT EXISTS breezeway.tenants (
  id              integer      PRIMARY KEY,
  name            text         NOT NULL,
  status          text         NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','provisioning','active','suspended','archived')),
  onboarding_step text,
  created_at      timestamptz  NOT NULL DEFAULT now(),
  updated_at      timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE breezeway.tenants IS
  'Source of truth for Breezeway tenant companies. id maps 1:1 to Supabase public.client.client_id.';

-- ----------------------------------------------------------------------------
-- 2. tenant_regions
-- ----------------------------------------------------------------------------
-- Replaces the hardcoded REGIONS dict in /root/Breezeway/etl/config.py.
-- One row per Breezeway company a tenant has access to.
-- active=false until backfill completes; active=true makes cron pick it up.

CREATE TABLE IF NOT EXISTS breezeway.tenant_regions (
  region_code           text         PRIMARY KEY,
  tenant_id             integer      NOT NULL REFERENCES breezeway.tenants(id),
  display_name          text         NOT NULL,
  breezeway_company_id  text         NOT NULL,
  active                boolean      NOT NULL DEFAULT false,
  created_at            timestamptz  NOT NULL DEFAULT now(),
  updated_at            timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tenant_regions_tenant
  ON breezeway.tenant_regions(tenant_id);

CREATE INDEX IF NOT EXISTS idx_tenant_regions_active
  ON breezeway.tenant_regions(active) WHERE active = true;

COMMENT ON TABLE breezeway.tenant_regions IS
  'Replaces hardcoded REGIONS dict in etl/config.py. Cron and webhook handler read active=true rows.';

-- ----------------------------------------------------------------------------
-- 3. api_tokens: add tenant_id FK
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='breezeway' AND table_name='api_tokens' AND column_name='tenant_id'
  ) THEN
    ALTER TABLE breezeway.api_tokens
      ADD COLUMN tenant_id integer REFERENCES breezeway.tenants(id);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 4. Backfill Grand Welcome (Supabase client_id = 1)
-- ----------------------------------------------------------------------------
-- Safe to re-run: ON CONFLICT DO NOTHING on tenants/tenant_regions.

INSERT INTO breezeway.tenants (id, name, status)
VALUES (1, 'B&B Ventures Co / Grand Welcome', 'active')
ON CONFLICT (id) DO NOTHING;

-- 8 GW regions. breezeway_company_id taken from existing etl/config.py REGIONS dict.
INSERT INTO breezeway.tenant_regions (region_code, tenant_id, display_name, breezeway_company_id, active) VALUES
  ('nashville',    1, 'Nashville',       '8558',  true),
  ('austin',       1, 'Austin',          '8561',  true),
  ('smoky',        1, 'Smoky Mountains', '8399',  true),
  ('hilton_head',  1, 'Hilton Head',     '12314', true),
  ('breckenridge', 1, 'Breckenridge',    '10530', true),
  ('sea_ranch',    1, 'Sea Ranch',       '14717', true),
  ('mammoth',      1, 'Mammoth',         '14720', true),
  ('hill_country', 1, 'Hill Country',    '8559',  true)
ON CONFLICT (region_code) DO NOTHING;

-- Link existing api_tokens rows to tenant_id=1 (idempotent).
UPDATE breezeway.api_tokens
SET tenant_id = 1
WHERE tenant_id IS NULL
  AND region_code IN ('nashville','austin','smoky','hilton_head','breckenridge','sea_ranch','mammoth','hill_country');

-- ----------------------------------------------------------------------------
-- 5. Verification (informational SELECTs at end of run)
-- ----------------------------------------------------------------------------

SELECT 'tenants' AS table, count(*) AS rows FROM breezeway.tenants
UNION ALL SELECT 'tenant_regions',                   count(*) FROM breezeway.tenant_regions
UNION ALL SELECT 'tenant_regions WHERE active=true', count(*) FROM breezeway.tenant_regions WHERE active = true
UNION ALL SELECT 'api_tokens WHERE tenant_id IS NULL', count(*) FROM breezeway.api_tokens WHERE tenant_id IS NULL;

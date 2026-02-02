-- Migration 019: Create templates table
-- Stores task templates by region

CREATE TABLE IF NOT EXISTS breezeway.templates (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    template_id BIGINT NOT NULL,
    name VARCHAR(128),
    department VARCHAR(64),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_template UNIQUE (template_id, region_code)
);

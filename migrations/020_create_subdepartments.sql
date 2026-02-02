-- Migration 020: Create subdepartments table
-- Stores subdepartment reference data by region

CREATE TABLE IF NOT EXISTS breezeway.subdepartments (
    id BIGSERIAL PRIMARY KEY,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    subdepartment_id INTEGER NOT NULL,
    name VARCHAR(128),
    created_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_subdepartment UNIQUE (subdepartment_id, region_code)
);

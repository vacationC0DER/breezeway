-- Migration 013: Add Property Fields
-- Adds property details: bedrooms, bathrooms, living area, year built

ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS bedrooms INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS bathrooms INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS living_area INTEGER;
ALTER TABLE breezeway.properties ADD COLUMN IF NOT EXISTS year_built INTEGER;

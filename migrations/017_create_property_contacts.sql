-- Migration 017: Create property_contacts table
-- Stores contact information associated with properties

CREATE TABLE IF NOT EXISTS breezeway.property_contacts (
    id BIGSERIAL PRIMARY KEY,
    property_pk BIGINT NOT NULL REFERENCES breezeway.properties(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    contact_id BIGINT NOT NULL,
    contact_type VARCHAR(64),
    name VARCHAR(128),
    email VARCHAR(255),
    phone VARCHAR(32),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    synced_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_property_contact UNIQUE (property_pk, contact_id)
);
CREATE INDEX IF NOT EXISTS idx_property_contacts_property ON breezeway.property_contacts(property_pk);

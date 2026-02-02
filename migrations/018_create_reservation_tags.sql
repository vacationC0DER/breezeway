-- Migration 018: Create reservation_tags table
-- Links reservations to tags (many-to-many relationship)

CREATE TABLE IF NOT EXISTS breezeway.reservation_tags (
    id BIGSERIAL PRIMARY KEY,
    reservation_pk BIGINT NOT NULL REFERENCES breezeway.reservations(id) ON DELETE CASCADE,
    tag_pk BIGINT NOT NULL REFERENCES breezeway.tags(id) ON DELETE CASCADE,
    region_code VARCHAR(32) NOT NULL REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_reservation_tag UNIQUE (reservation_pk, tag_pk)
);
CREATE INDEX IF NOT EXISTS idx_reservation_tags_reservation ON breezeway.reservation_tags(reservation_pk);

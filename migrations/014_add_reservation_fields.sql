-- Migration 014: Add Reservation Fields
-- Adds guest count details and booking source

ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS adults INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS children INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS pets INTEGER;
ALTER TABLE breezeway.reservations ADD COLUMN IF NOT EXISTS source VARCHAR(64);

-- Initialize separate schemas for each service
-- Run automatically on first postgres container start

CREATE SCHEMA IF NOT EXISTS platform;
CREATE SCHEMA IF NOT EXISTS transaction;

-- Grant permissions (Flyway migrations in each service will create tables)
GRANT ALL PRIVILEGES ON SCHEMA platform TO dev;
GRANT ALL PRIVILEGES ON SCHEMA transaction TO dev;

-- Transaction service gets read-only access to platform schema views
-- (Views will be created by platform service Flyway migrations)
GRANT USAGE ON SCHEMA platform TO dev;

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

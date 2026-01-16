-- PostgreSQL initialization script
-- Creates separate databases for Zitadel and Papermerge
-- This script runs automatically when PostgreSQL container starts for the first time

-- Create Zitadel database
CREATE DATABASE zitadel
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'C'
    LC_CTYPE = 'C'
    TEMPLATE = template0;

-- Create Papermerge database
CREATE DATABASE papermerge
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'C'
    LC_CTYPE = 'C'
    TEMPLATE = template0;

-- Grant all privileges to postgres user (already owner, but being explicit)
GRANT ALL PRIVILEGES ON DATABASE zitadel TO postgres;
GRANT ALL PRIVILEGES ON DATABASE papermerge TO postgres;

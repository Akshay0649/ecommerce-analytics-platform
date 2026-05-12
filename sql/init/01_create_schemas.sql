-- Bootstrap schemas and roles for the analytics warehouse.
-- Run automatically by the Postgres image at first boot.

-- Schemas: layered Kimball architecture
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS intermediate;
CREATE SCHEMA IF NOT EXISTS mart_core;
CREATE SCHEMA IF NOT EXISTS mart_finance;
CREATE SCHEMA IF NOT EXISTS mart_marketing;
CREATE SCHEMA IF NOT EXISTS snapshots;
CREATE SCHEMA IF NOT EXISTS dbt_test_audit;

-- Read-only role for BI tools (Metabase) — only sees marts.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bi_reader') THEN
    CREATE ROLE bi_reader LOGIN PASSWORD 'bi_reader';
  END IF;
END $$;

GRANT USAGE ON SCHEMA mart_core, mart_finance, mart_marketing TO bi_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA mart_core, mart_finance, mart_marketing
  GRANT SELECT ON TABLES TO bi_reader;

-- Pipeline service role
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'transformer') THEN
    CREATE ROLE transformer LOGIN PASSWORD 'transformer';
  END IF;
END $$;

GRANT ALL ON SCHEMA raw, staging, intermediate, mart_core, mart_finance,
                  mart_marketing, snapshots, dbt_test_audit TO transformer;

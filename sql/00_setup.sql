-- 00_setup.sql — create the project database and its two schemas.
-- Run once, as a superuser, connected to any existing database:
--     psql -h 127.0.0.1 -U postgres -f sql/00_setup.sql
--
-- Idempotent: safe to re-run. It will not drop anything.

-- CREATE DATABASE cannot run inside a transaction block, so this file is
-- deliberately not wrapped in BEGIN/COMMIT.

-- Guard: only create if absent. \gexec runs the string the query returns,
-- and returns no rows (so runs nothing) when the database already exists.
SELECT 'CREATE DATABASE ecommerce WITH ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'ecommerce')
\gexec

\connect ecommerce

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS core;

COMMENT ON SCHEMA staging IS
  'Landing zone. Raw CSV loaded here with every column as text, never edited in place. '
  'Nothing downstream reads staging except 03_cleaning.sql.';

COMMENT ON SCHEMA core IS
  'The star schema: dim_date, dim_customer, dim_product, dim_geography, '
  'fact_order_line, fact_return. Everything Power BI connects to lives here.';

-- Resolve unqualified names against core first, then staging.
ALTER DATABASE ecommerce SET search_path = core, staging, public;

-- Report what exists now.
SELECT current_database() AS database,
       nspname            AS schema,
       obj_description(oid, 'pg_namespace') IS NOT NULL AS documented
FROM pg_namespace
WHERE nspname IN ('staging', 'core', 'public')
ORDER BY nspname;

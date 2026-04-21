-- ============================================================
--  pg-baseera — External Database Setup (Mode B)
--  Run these commands on your existing PostgreSQL instance
--  as a superuser before starting pg-baseera.
-- ============================================================

-- 1. Create the monitoring user
CREATE USER pgexporter WITH PASSWORD 'your-secure-password-here';

-- 2. Grant monitoring permissions (PostgreSQL 10+)
GRANT pg_monitor TO pgexporter;

-- 3. Grant connect on your database
GRANT CONNECT ON DATABASE your_database_name TO pgexporter;

-- 4. Grant access to stats views
GRANT SELECT ON pg_stat_user_tables  TO pgexporter;
GRANT SELECT ON pg_stat_user_indexes TO pgexporter;
GRANT SELECT ON pg_statio_user_tables TO pgexporter;

-- 5. Enable pg_stat_statements (requires superuser)
--    Add 'pg_stat_statements' to shared_preload_libraries
--    in postgresql.conf, then restart PostgreSQL, then run:
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 6. Verify the user can connect
-- Run this from your terminal to test:
--   psql "postgresql://pgexporter:your-password@your-host:5432/your-db?sslmode=require"

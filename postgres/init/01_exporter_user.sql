-- Create monitoring user for postgres_exporter
-- Password is set via EXPORTER_PASSWORD in .env
CREATE USER pgexporter WITH PASSWORD 'changeme';

-- Grant necessary permissions
GRANT pg_monitor TO pgexporter;
GRANT CONNECT ON DATABASE appdb TO pgexporter;

-- Required for pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant access to stats views
GRANT SELECT ON pg_stat_user_tables  TO pgexporter;
GRANT SELECT ON pg_stat_user_indexes TO pgexporter;
GRANT SELECT ON pg_statio_user_tables TO pgexporter;

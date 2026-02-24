-- Kessel-in-a-Box: RBAC Database Initialization
-- Database for insights-rbac service

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create schema
CREATE SCHEMA IF NOT EXISTS rbac;

-- Placeholder tables (will be created by insights-rbac Django migrations)
-- These are just to ensure the database is ready

-- Workspace table (simplified version)
CREATE TABLE IF NOT EXISTS rbac.workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Role table (simplified version)
CREATE TABLE IF NOT EXISTS rbac.roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    workspace_id UUID REFERENCES rbac.workspaces(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_workspaces_name ON rbac.workspaces(name);
CREATE INDEX IF NOT EXISTS idx_roles_workspace ON rbac.roles(workspace_id);

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA rbac TO rbac;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA rbac TO rbac;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA rbac TO rbac;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA rbac GRANT ALL ON TABLES TO rbac;
ALTER DEFAULT PRIVILEGES IN SCHEMA rbac GRANT ALL ON SEQUENCES TO rbac;

-- Insert sample data for testing
INSERT INTO rbac.workspaces (id, name, description) VALUES
    ('00000000-0000-0000-0000-000000000001', 'default-workspace', 'Default workspace for testing'),
    ('00000000-0000-0000-0000-000000000002', 'admin-workspace', 'Admin workspace')
ON CONFLICT DO NOTHING;

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'RBAC database initialized successfully';
END $$;

-- Debezium heartbeat table for monitoring replication lag
CREATE TABLE IF NOT EXISTS rbac.debezium_heartbeat (
    id INT PRIMARY KEY,
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO rbac.debezium_heartbeat (id, ts) VALUES (1, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE SET ts = CURRENT_TIMESTAMP;

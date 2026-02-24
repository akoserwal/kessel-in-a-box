-- Kessel-in-a-Box: Inventory Database Initialization
-- Database for insights-host-inventory AND kessel-inventory-api

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS inventory;      -- insights-host-inventory schema
CREATE SCHEMA IF NOT EXISTS kessel;         -- kessel-inventory-api schema

-- ============================================================================
-- insights-host-inventory tables (simplified)
-- ============================================================================

-- Hosts table
CREATE TABLE IF NOT EXISTS inventory.hosts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    canonical_facts JSONB NOT NULL,
    display_name VARCHAR(255),
    workspace_id UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Host groups table
CREATE TABLE IF NOT EXISTS inventory.host_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    workspace_id UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tags table
CREATE TABLE IF NOT EXISTS inventory.tags (
    id SERIAL PRIMARY KEY,
    host_id UUID REFERENCES inventory.hosts(id) ON DELETE CASCADE,
    namespace VARCHAR(255),
    key VARCHAR(255) NOT NULL,
    value VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for insights-host-inventory
CREATE INDEX IF NOT EXISTS idx_hosts_workspace ON inventory.hosts(workspace_id);
CREATE INDEX IF NOT EXISTS idx_hosts_display_name ON inventory.hosts(display_name);
CREATE INDEX IF NOT EXISTS idx_host_groups_workspace ON inventory.host_groups(workspace_id);
CREATE INDEX IF NOT EXISTS idx_tags_host_id ON inventory.tags(host_id);
CREATE INDEX IF NOT EXISTS idx_tags_key ON inventory.tags(key);

-- ============================================================================
-- kessel-inventory-api tables (simplified)
-- ============================================================================

-- Resources table
CREATE TABLE IF NOT EXISTS kessel.resources (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_type VARCHAR(255) NOT NULL,
    resource_id VARCHAR(255) NOT NULL,
    workspace_id UUID NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(resource_type, resource_id, workspace_id)
);

-- Resource relationships table
CREATE TABLE IF NOT EXISTS kessel.resource_relationships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource_id UUID REFERENCES kessel.resources(id) ON DELETE CASCADE,
    relation VARCHAR(255) NOT NULL,
    subject_type VARCHAR(255) NOT NULL,
    subject_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(resource_id, relation, subject_type, subject_id)
);

-- Indexes for kessel-inventory-api
CREATE INDEX IF NOT EXISTS idx_resources_type ON kessel.resources(resource_type);
CREATE INDEX IF NOT EXISTS idx_resources_workspace ON kessel.resources(workspace_id);
CREATE INDEX IF NOT EXISTS idx_resources_lookup ON kessel.resources(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_relationships_resource ON kessel.resource_relationships(resource_id);
CREATE INDEX IF NOT EXISTS idx_relationships_subject ON kessel.resource_relationships(subject_type, subject_id);

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA inventory TO inventory;
GRANT ALL PRIVILEGES ON SCHEMA kessel TO inventory;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA inventory TO inventory;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA kessel TO inventory;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA inventory TO inventory;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA kessel TO inventory;

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory GRANT ALL ON TABLES TO inventory;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory GRANT ALL ON SEQUENCES TO inventory;
ALTER DEFAULT PRIVILEGES IN SCHEMA kessel GRANT ALL ON TABLES TO inventory;
ALTER DEFAULT PRIVILEGES IN SCHEMA kessel GRANT ALL ON SEQUENCES TO inventory;

-- Insert sample data for testing
INSERT INTO inventory.hosts (id, canonical_facts, display_name, workspace_id) VALUES
    ('00000000-0000-0000-0000-000000000001', 
     '{"fqdn": "host1.example.com", "insights_id": "12345"}',
     'host1.example.com',
     '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Inventory database initialized successfully';
END $$;

-- Debezium heartbeat table for monitoring replication lag
CREATE TABLE IF NOT EXISTS inventory.debezium_heartbeat (
    id INT PRIMARY KEY,
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO inventory.debezium_heartbeat (id, ts) VALUES (1, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE SET ts = CURRENT_TIMESTAMP;

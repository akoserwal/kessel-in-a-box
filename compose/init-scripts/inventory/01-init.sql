-- Kessel-in-a-Box: Inventory Database Initialization
-- Database for insights-host-inventory
-- NOTE: kessel-inventory-api (real) runs its own migrations via 'inventory-api migrate'

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS inventory;      -- insights-host-inventory schema

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

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA inventory TO inventory;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA inventory TO inventory;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA inventory TO inventory;

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory GRANT ALL ON TABLES TO inventory;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory GRANT ALL ON SEQUENCES TO inventory;

-- The real kessel-inventory-api will run its own migrations on the public schema

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

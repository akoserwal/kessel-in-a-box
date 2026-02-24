#!/usr/bin/env bash

# CDC Setup Script
# Configures Debezium connector for PostgreSQL CDC

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setting up CDC Pipeline"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Wait for Debezium to be ready
log_info "Waiting for Debezium Connect to be ready..."
max_attempts=30
attempt=0

while ! curl -sf http://localhost:8083/ > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
        log_warn "Debezium not ready after $max_attempts attempts"
        exit 1
    fi
    sleep 2
done

log_success "Debezium Connect is ready"

# Configure PostgreSQL for CDC
log_info "Configuring PostgreSQL for CDC..."

# Enable logical replication
docker exec kessel-postgres psql -U spicedb -d spicedb -c "ALTER SYSTEM SET wal_level = logical;" 2>/dev/null || true
docker exec kessel-postgres psql -U spicedb -d spicedb -c "ALTER SYSTEM SET max_replication_slots = 10;" 2>/dev/null || true
docker exec kessel-postgres psql -U spicedb -d spicedb -c "ALTER SYSTEM SET max_wal_senders = 10;" 2>/dev/null || true

# Restart PostgreSQL to apply settings
log_info "Restarting PostgreSQL to apply CDC settings..."
docker restart kessel-postgres > /dev/null
sleep 10

# Wait for PostgreSQL to be ready
while ! docker exec kessel-postgres pg_isready -U spicedb > /dev/null 2>&1; do
    sleep 1
done

log_success "PostgreSQL configured for CDC"

# Create Debezium connector
log_info "Creating Debezium PostgreSQL connector..."

connector_config='{
  "name": "spicedb-postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "spicedb",
    "database.password": "secretpassword",
    "database.dbname": "spicedb",
    "database.server.name": "kessel",
    "table.include.list": "public.relation_tuple,public.namespace_config",
    "plugin.name": "pgoutput",
    "publication.autocreate.mode": "filtered",
    "slot.name": "debezium_kessel",
    "topic.prefix": "kessel.cdc",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter.schemas.enable": "true",
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "rewrite",
    "snapshot.mode": "initial",
    "decimal.handling.mode": "string",
    "time.precision.mode": "connect",
    "include.schema.changes": "false"
  }
}'

# Register connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d "$connector_config" > /dev/null 2>&1

sleep 3

# Check connector status
status=$(curl -s http://localhost:8083/connectors/spicedb-postgres-connector/status)
state=$(echo "$status" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ "$state" == "RUNNING" ]]; then
    log_success "Debezium connector created and running"
else
    log_warn "Connector state: $state"
    echo "$status" | python3 -m json.tool 2>/dev/null || echo "$status"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "CDC Pipeline setup complete!"
echo
echo "Topics created:"
echo "  - kessel.cdc.public.relation_tuple"
echo "  - kessel.cdc.public.namespace_config"
echo
echo "Monitor CDC:"
echo "  # List connectors"
echo "  curl http://localhost:8083/connectors"
echo
echo "  # Check connector status"
echo "  curl http://localhost:8083/connectors/spicedb-postgres-connector/status"
echo
echo "  # View Kafka topics"
echo "  docker exec kessel-kafka kafka-topics --list --bootstrap-server localhost:9092"
echo
echo "  # Consume CDC events"
echo "  docker exec kessel-kafka kafka-console-consumer \\"
echo "    --bootstrap-server localhost:9092 \\"
echo "    --topic kessel.cdc.public.relation_tuple \\"
echo "    --from-beginning"
echo
echo "  # Access Kafka UI"
echo "  http://localhost:8080"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

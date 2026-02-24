#!/bin/bash
# SpiceDB Schema Management Helper Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPICEDB_TOKEN="${SPICEDB_PRESHARED_KEY:-testtesttesttest}"
SPICEDB_HOST="${SPICEDB_HOST:-localhost:50051}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

read_schema() {
    log_info "Reading current schema from SpiceDB..."
    echo '{}' | grpcurl -plaintext \
        -H "authorization: Bearer $SPICEDB_TOKEN" \
        -d @ "$SPICEDB_HOST" \
        authzed.api.v1.SchemaService/ReadSchema | jq -r '.schemaText'

    if [ $? -eq 0 ]; then
        log_success "Schema retrieved successfully"
    else
        log_error "Failed to retrieve schema"
        exit 1
    fi
}

write_schema() {
    local schema_file="$1"

    if [ ! -f "$schema_file" ]; then
        log_error "Schema file not found: $schema_file"
        exit 1
    fi

    log_info "Loading schema from: $schema_file"

    # Convert schema to JSON-escaped string
    SCHEMA_CONTENT=$(cat "$schema_file" | sed '/^\/\*/,/\*\//d; /^$/d' | jq -Rs .)

    # Create JSON payload
    PAYLOAD="{\"schema\": $SCHEMA_CONTENT}"

    # Write schema
    echo "$PAYLOAD" | grpcurl -plaintext \
        -H "authorization: Bearer $SPICEDB_TOKEN" \
        -d @ "$SPICEDB_HOST" \
        authzed.api.v1.SchemaService/WriteSchema

    if [ $? -eq 0 ]; then
        log_success "Schema loaded successfully"
        echo ""
        read_schema
    else
        log_error "Failed to load schema"
        exit 1
    fi
}

validate_schema() {
    local schema_file="$1"

    log_info "Validating schema syntax..."

    # Basic validation - check for required keywords
    if ! grep -q "definition" "$schema_file"; then
        log_error "No definitions found in schema"
        exit 1
    fi

    log_success "Schema syntax appears valid"
}

case "${1:-read}" in
    read)
        read_schema
        ;;
    write)
        if [ -z "$2" ]; then
            log_error "Usage: $0 write <schema-file>"
            exit 1
        fi
        validate_schema "$2"
        write_schema "$2"
        ;;
    validate)
        if [ -z "$2" ]; then
            log_error "Usage: $0 validate <schema-file>"
            exit 1
        fi
        validate_schema "$2"
        ;;
    *)
        echo "Usage: $0 {read|write|validate} [schema-file]"
        echo ""
        echo "Commands:"
        echo "  read              - Read current schema from SpiceDB"
        echo "  write <file>      - Write schema from file to SpiceDB"
        echo "  validate <file>   - Validate schema syntax"
        echo ""
        echo "Example:"
        echo "  $0 write schemas/kessel-authorization.zed"
        exit 1
        ;;
esac

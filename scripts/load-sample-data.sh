#!/usr/bin/env bash

# Load Sample Data Script
# Loads schemas and relationships for demonstration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SAMPLE_DATA_DIR="${PROJECT_ROOT}/sample-data"

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

# Wait for SpiceDB to be ready
wait_for_spicedb() {
    log_info "Waiting for SpiceDB to be ready..."
    local max_attempts=30
    local attempt=0

    while ! curl -sf http://localhost:8443/healthz &>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            log_warn "SpiceDB not ready after 30 attempts"
            return 1
        fi
        sleep 1
    done

    log_success "SpiceDB is ready"
}

# Load schema using zed CLI or HTTP API
load_schema() {
    local schema_file="$1"
    local schema_name="$(basename "$schema_file" .zed)"

    log_info "Loading schema: $schema_name"

    if command -v zed &>/dev/null; then
        # Use zed CLI
        zed --endpoint localhost:50051 --insecure schema write \
            --schema "$(cat "$schema_file")" &>/dev/null
        log_success "Schema loaded via zed CLI: $schema_name"
    else
        # Use HTTP API
        local preshared_key="${SPICEDB_PRESHARED_KEY:-testtesttesttest}"

        curl -X POST http://localhost:8443/v1/schema/write \
            -H "Authorization: Bearer ${preshared_key}" \
            -H "Content-Type: application/json" \
            -d "{\"schema\": $(jq -Rs . < "$schema_file")}" \
            &>/dev/null

        log_success "Schema loaded via HTTP API: $schema_name"
    fi
}

# Load relationships
load_relationships() {
    local rel_file="$1"
    local rel_name="$(basename "$rel_file" .json)"

    log_info "Loading relationships: $rel_name"

    if command -v zed &>/dev/null; then
        # Use zed CLI to write relationships
        while IFS= read -r line; do
            local resource=$(echo "$line" | jq -r '.resource')
            local relation=$(echo "$line" | jq -r '.relation')
            local subject=$(echo "$line" | jq -r '.subject')

            zed --endpoint localhost:50051 --insecure relationship create \
                "$resource" "$relation" "$subject" &>/dev/null || true
        done < "$rel_file"

        log_success "Relationships loaded: $rel_name"
    else
        log_warn "zed CLI not installed, skipping relationships for $rel_name"
        log_warn "Install zed: https://github.com/authzed/zed"
    fi
}

# Main execution
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Loading Sample Data"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    wait_for_spicedb || exit 1

    # Load GitHub schema if it exists
    if [[ -f "${SAMPLE_DATA_DIR}/schemas/github-clone.zed" ]]; then
        load_schema "${SAMPLE_DATA_DIR}/schemas/github-clone.zed"

        if [[ -f "${SAMPLE_DATA_DIR}/relationships/github-clone.json" ]]; then
            load_relationships "${SAMPLE_DATA_DIR}/relationships/github-clone.json"
        fi
    else
        log_warn "GitHub schema not found, skipping"
    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Sample data loading complete!"
    echo
    echo "Try these commands:"
    echo "  # Check a permission"
    if command -v zed &>/dev/null; then
        echo "  zed --endpoint localhost:50051 --insecure permission check \\"
        echo "    repo:myorg/myrepo write user:alice"
    else
        echo "  curl http://localhost:8443/v1/permissions/check \\"
        echo "    -H 'Authorization: Bearer testtesttesttest' \\"
        echo "    -d '{\"resource\":{\"objectType\":\"repo\",\"objectId\":\"myorg/myrepo\"}, ...}'"
    fi
    echo
}

main "$@"

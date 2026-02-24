#!/usr/bin/env bash

# Migration Script: Insights Inventory → Kessel ReBAC
# Migrates host inventory data to Kessel relationship-based model

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Configuration
SPICEDB_ENDPOINT="${SPICEDB_ENDPOINT:-localhost:50051}"
SPICEDB_TOKEN="${SPICEDB_PRESHARED_KEY:-testtesttesttest}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Insights Inventory → Kessel Migration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v zed &> /dev/null; then
    log_error "zed CLI not found. Please install from: https://github.com/authzed/zed"
    exit 1
fi

if ! zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" version &>/dev/null; then
    log_error "Cannot connect to SpiceDB at $SPICEDB_ENDPOINT"
    exit 1
fi

log_success "Prerequisites check passed"

# Load schema
log_info "Loading Kessel Inventory schema..."

SCHEMA_FILE="$PROJECT_ROOT/sample-data/schemas/insights/inventory-schema.zed"

if [[ ! -f "$SCHEMA_FILE" ]]; then
    log_error "Schema file not found: $SCHEMA_FILE"
    exit 1
fi

if zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
    schema write "$SCHEMA_FILE"; then
    log_success "Schema loaded successfully"
else
    log_error "Failed to load schema"
    exit 1
fi

# Migrate organizations (reuse from RBAC migration)
log_info "Ensuring organizations exist..."

zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
    relationship create "organization:acme-corp" admin "user:alice" 2>/dev/null || true

zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
    relationship create "organization:acme-corp" member "user:bob" 2>/dev/null || true

log_success "Organizations ready"

# Migrate workspaces
log_info "Migrating inventory workspaces..."

migrate_inventory_workspace() {
    local workspace_id="$1"
    local org_id="$2"
    local owner="$3"
    local admins="$4"
    local operators="$5"
    local viewers="$6"

    log_info "  Creating workspace: $workspace_id"

    # Link to organization
    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "workspace:${workspace_id}" org "organization:${org_id}" \
        2>/dev/null || true

    # Set owner
    if [[ -n "$owner" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "workspace:${workspace_id}" owner "user:${owner}" \
            2>/dev/null || true
    fi

    # Set admins
    for admin in $admins; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "workspace:${workspace_id}" admin "$admin" \
            2>/dev/null || true
    done

    # Set operators
    for operator in $operators; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "workspace:${workspace_id}" operator "$operator" \
            2>/dev/null || true
    done

    # Set viewers
    for viewer in $viewers; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "workspace:${workspace_id}" viewer "$viewer" \
            2>/dev/null || true
    done

    log_success "  Workspace $workspace_id migrated"
}

migrate_inventory_workspace "production" "acme-corp" "alice" "user:bob" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440003#member"
migrate_inventory_workspace "staging" "acme-corp" "bob" "" "group:550e8400-e29b-41d4-a716-446655440003#member" ""

# Migrate host groups
log_info "Migrating host groups..."

migrate_host_group() {
    local group_id="$1"
    local org_id="$2"
    local workspace_id="$3"
    local owner="$4"
    local admins="$5"
    local members="$6"

    log_info "  Creating host group: $group_id"

    # Link to organization and workspace
    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "host_group:${group_id}" org "organization:${org_id}" \
        2>/dev/null || true

    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "host_group:${group_id}" workspace "workspace:${workspace_id}" \
        2>/dev/null || true

    # Set owner
    if [[ -n "$owner" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host_group:${group_id}" owner "user:${owner}" \
            2>/dev/null || true
    fi

    # Set admins
    for admin in $admins; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host_group:${group_id}" admin "$admin" \
            2>/dev/null || true
    done

    # Set members
    for member in $members; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host_group:${group_id}" member "$member" \
            2>/dev/null || true
    done

    log_success "  Host group $group_id migrated"
}

migrate_host_group "web-servers" "acme-corp" "production" "alice" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440003#member"
migrate_host_group "databases" "acme-corp" "production" "alice" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440002#member"
migrate_host_group "cache-servers" "acme-corp" "production" "bob" "group:550e8400-e29b-41d4-a716-446655440002#member" ""

# Migrate hosts
log_info "Migrating hosts..."

migrate_host() {
    local host_id="$1"
    local org_id="$2"
    local workspace_id="$3"
    local host_group_id="$4"
    local owner="$5"
    local admins="$6"
    local operators="$7"
    local viewers="$8"
    local can_view_profile="$9"
    local can_view_facts="${10}"

    log_info "  Creating host: $host_id"

    # Link to hierarchy
    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "host:${host_id}" org "organization:${org_id}" \
        2>/dev/null || true

    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "host:${host_id}" workspace "workspace:${workspace_id}" \
        2>/dev/null || true

    if [[ -n "$host_group_id" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" host_group "host_group:${host_group_id}" \
            2>/dev/null || true
    fi

    # Set owner
    if [[ -n "$owner" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" owner "user:${owner}" \
            2>/dev/null || true
    fi

    # Set admins, operators, viewers
    for admin in $admins; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" admin "$admin" 2>/dev/null || true
    done

    for operator in $operators; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" operator "$operator" 2>/dev/null || true
    done

    for viewer in $viewers; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" viewer "$viewer" 2>/dev/null || true
    done

    # System profile access
    for user in $can_view_profile; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" can_view_system_profile "$user" 2>/dev/null || true
    done

    # Facts access
    for user in $can_view_facts; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "host:${host_id}" can_view_facts "$user" 2>/dev/null || true
    done

    log_success "  Host $host_id migrated"
}

# Migrate sample hosts
migrate_host "web-01.acme.com" "acme-corp" "production" "web-servers" "alice" "" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440003#member" "group:550e8400-e29b-41d4-a716-446655440003#member" "group:550e8400-e29b-41d4-a716-446655440002#member"
migrate_host "web-02.acme.com" "acme-corp" "production" "web-servers" "alice" "" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440003#member" "group:550e8400-e29b-41d4-a716-446655440003#member" "group:550e8400-e29b-41d4-a716-446655440002#member"
migrate_host "db-01.acme.com" "acme-corp" "production" "databases" "alice" "user:bob" "group:550e8400-e29b-41d4-a716-446655440002#member" "" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440002#member"

# Migrate tag namespaces
log_info "Migrating tag namespaces..."

migrate_tag_namespace() {
    local namespace_id="$1"
    local org_id="$2"
    local admins="$3"

    log_info "  Creating tag namespace: $namespace_id"

    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "tag_namespace:${namespace_id}" org "organization:${org_id}" \
        2>/dev/null || true

    for admin in $admins; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "tag_namespace:${namespace_id}" admin "$admin" \
            2>/dev/null || true
    done

    log_success "  Tag namespace $namespace_id migrated"
}

migrate_tag_namespace "environment" "acme-corp" "user:alice"
migrate_tag_namespace "cost-center" "acme-corp" "user:alice"
migrate_tag_namespace "application" "acme-corp" "user:bob"

# Migrate tags
log_info "Migrating tags..."

migrate_tag() {
    local tag_id="$1"
    local org_id="$2"
    local namespace_id="$3"
    local admin="$4"
    local can_apply="$5"

    log_info "  Creating tag: $tag_id"

    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "tag:${tag_id}" org "organization:${org_id}" \
        2>/dev/null || true

    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "tag:${tag_id}" namespace "tag_namespace:${namespace_id}" \
        2>/dev/null || true

    if [[ -n "$admin" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "tag:${tag_id}" admin "$admin" \
            2>/dev/null || true
    fi

    for user in $can_apply; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "tag:${tag_id}" can_apply "$user" \
            2>/dev/null || true
    done

    log_success "  Tag $tag_id migrated"
}

migrate_tag "production" "acme-corp" "environment" "user:alice" "group:550e8400-e29b-41d4-a716-446655440002#member"
migrate_tag "staging" "acme-corp" "environment" "user:alice" "group:550e8400-e29b-41d4-a716-446655440003#member"
migrate_tag "engineering" "acme-corp" "cost-center" "user:alice" "user:alice user:bob"

# Validation
log_info "Validating migration..."

validation_passed=true

test_permission() {
    local resource="$1"
    local permission="$2"
    local subject="$3"
    local expected="$4"

    log_info "  Testing: $resource#$permission@$subject"

    if zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        permission check "$resource" "$permission" "$subject" &>/dev/null; then
        result="ALLOWED"
    else
        result="DENIED"
    fi

    if [[ "$result" == "$expected" ]]; then
        log_success "    ✓ $result (expected)"
    else
        log_error "    ✗ $result (expected $expected)"
        validation_passed=false
    fi
}

log_info "Running validation tests..."

# Test workspace permissions
test_permission "workspace:production" "view" "user:carol" "ALLOWED"
test_permission "workspace:production" "operate" "user:bob" "ALLOWED"

# Test host group permissions
test_permission "host_group:web-servers" "view" "user:carol" "ALLOWED"
test_permission "host_group:web-servers" "add_host" "user:alice" "ALLOWED"

# Test host permissions
test_permission "host:web-01.acme.com" "read" "user:carol" "ALLOWED"
test_permission "host:web-01.acme.com" "update" "user:bob" "ALLOWED"
test_permission "host:db-01.acme.com" "read_facts" "user:bob" "ALLOWED"

# Test tag permissions
test_permission "tag:production" "apply" "user:bob" "ALLOWED"

if [[ "$validation_passed" == true ]]; then
    log_success "All validation tests passed!"
else
    log_error "Some validation tests failed"
    exit 1
fi

# Generate report
REPORT_FILE="$PROJECT_ROOT/inventory-migration-report-$(date +%Y%m%d-%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
Insights Inventory → Kessel Migration Report
Generated: $(date)

Migration Summary:
- Workspaces migrated: 2
- Host groups migrated: 3
- Hosts migrated: 3
- Tag namespaces migrated: 3
- Tags migrated: 3

Workspaces:
  - production (owner: alice, operators: sre-team, viewers: developers)
  - staging (owner: bob, operators: developers)

Host Groups:
  - web-servers (owner: alice, admins: sre-team, members: developers)
  - databases (owner: alice, admins: sre-team, members: sre-team)
  - cache-servers (owner: bob, admins: sre-team)

Hosts:
  - web-01.acme.com (production/web-servers)
  - web-02.acme.com (production/web-servers)
  - db-01.acme.com (production/databases)

Tag Namespaces:
  - environment (admin: alice)
  - cost-center (admin: alice)
  - application (admin: bob)

Tags:
  - production (environment namespace, can apply: sre-team)
  - staging (environment namespace, can apply: developers)
  - engineering (cost-center namespace, can apply: alice, bob)

Validation: $(if [[ "$validation_passed" == true ]]; then echo "PASSED ✓"; else echo "FAILED ✗"; fi)

Next Steps:
1. Review migrated relationships
2. Test permission checks for hosts
3. Integrate with host-inventory service
4. Set up CDC for ongoing synchronization
5. Update client applications to use Kessel

For inspection:
  zed --endpoint $SPICEDB_ENDPOINT --insecure relationship read host:web-01.acme.com
  zed --endpoint $SPICEDB_ENDPOINT --insecure permission check host:web-01.acme.com update user:bob
EOF

log_success "Migration report saved to: $REPORT_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Migration completed successfully!"
echo
echo "Summary:"
echo "  Workspaces: 2"
echo "  Host Groups: 3"
echo "  Hosts: 3"
echo "  Tag Namespaces: 3"
echo "  Tags: 3"
echo "  Validation: $(if [[ "$validation_passed" == true ]]; then echo -e "${GREEN}PASSED${NC}"; else echo -e "${RED}FAILED${NC}"; fi)"
echo
echo "Report: $REPORT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#!/usr/bin/env bash

# Migration Script: Traditional RBAC → Kessel ReBAC
# Migrates Insights RBAC data to Kessel relationship-based model

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
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-rbac}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-secretpassword}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Insights RBAC → Kessel Migration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v zed &> /dev/null; then
    log_error "zed CLI not found. Please install from: https://github.com/authzed/zed"
    exit 1
fi

if ! command -v psql &> /dev/null; then
    log_warn "psql not found. Will skip database queries."
    SKIP_DB=true
else
    SKIP_DB=false
fi

# Test SpiceDB connection
if ! zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" version &>/dev/null; then
    log_error "Cannot connect to SpiceDB at $SPICEDB_ENDPOINT"
    exit 1
fi

log_success "Prerequisites check passed"

# Load schema
log_info "Loading Kessel RBAC schema..."

SCHEMA_FILE="$PROJECT_ROOT/sample-data/schemas/insights/rbac-schema.zed"

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

# Migrate organizations
log_info "Migrating organizations..."

migrate_organization() {
    local org_id="$1"
    local admin_users="$2"
    local member_users="$3"

    log_info "  Creating organization: $org_id"

    # Create admin relationships
    for admin in $admin_users; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "organization:${org_id}" admin "user:${admin}" \
            2>/dev/null || true
    done

    # Create member relationships
    for member in $member_users; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "organization:${org_id}" member "user:${member}" \
            2>/dev/null || true
    done

    log_success "  Organization $org_id migrated"
}

# Example: Migrate sample organization
migrate_organization "acme-corp" "alice" "bob carol dave"
migrate_organization "partner-corp" "" "eve"

# Migrate groups
log_info "Migrating groups..."

migrate_group() {
    local group_uuid="$1"
    local group_name="$2"
    local org_id="$3"
    local members="$4"
    local admin="$5"

    log_info "  Creating group: $group_name"

    # Link group to organization
    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "group:${group_uuid}" org "organization:${org_id}" \
        2>/dev/null || true

    # Set group admin
    if [[ -n "$admin" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "group:${group_uuid}" admin "user:${admin}" \
            2>/dev/null || true
    fi

    # Add members
    for member in $members; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "group:${group_uuid}" member "user:${member}" \
            2>/dev/null || true
    done

    log_success "  Group $group_name migrated"
}

# Migrate sample groups
migrate_group "550e8400-e29b-41d4-a716-446655440001" "org-admins" "acme-corp" "alice" "alice"
migrate_group "550e8400-e29b-41d4-a716-446655440002" "sre-team" "acme-corp" "bob dave" "bob"
migrate_group "550e8400-e29b-41d4-a716-446655440003" "developers" "acme-corp" "bob carol" "alice"
migrate_group "550e8400-e29b-41d4-a716-446655440004" "qa-team" "acme-corp" "carol" "carol"
migrate_group "550e8400-e29b-41d4-a716-446655440005" "external-users" "partner-corp" "eve" ""

# Migrate workspaces
log_info "Migrating workspaces..."

migrate_workspace() {
    local workspace_id="$1"
    local org_id="$2"
    local owner="$3"
    local admins="$4"
    local editors="$5"
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
            "workspace:${workspace_id}" admin "user:${admin}" \
            2>/dev/null || true
    done

    # Set editors (can be groups)
    for editor in $editors; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "workspace:${workspace_id}" editor "$editor" \
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

# Migrate sample workspaces
migrate_workspace "production" "acme-corp" "alice" "bob" "group:550e8400-e29b-41d4-a716-446655440002#member" "group:550e8400-e29b-41d4-a716-446655440003#member"
migrate_workspace "staging" "acme-corp" "bob" "" "group:550e8400-e29b-41d4-a716-446655440003#member" ""
migrate_workspace "development" "acme-corp" "carol" "" "group:550e8400-e29b-41d4-a716-446655440003#member" ""

# Migrate applications
log_info "Migrating applications..."

migrate_application() {
    local app_id="$1"
    local org_id="$2"
    local owner="$3"
    local admins="$4"
    local users="$5"

    log_info "  Creating application: $app_id"

    # Link to organization
    zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
        relationship create \
        "application:${app_id}" org "organization:${org_id}" \
        2>/dev/null || true

    # Set owner
    if [[ -n "$owner" ]]; then
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "application:${app_id}" owner "user:${owner}" \
            2>/dev/null || true
    fi

    # Set admins
    for admin in $admins; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "application:${app_id}" admin "$admin" \
            2>/dev/null || true
    done

    # Set users
    for user in $users; do
        zed --endpoint "$SPICEDB_ENDPOINT" --insecure --token "$SPICEDB_TOKEN" \
            relationship create \
            "application:${app_id}" user "$user" \
            2>/dev/null || true
    done

    log_success "  Application $app_id migrated"
}

# Migrate sample applications
migrate_application "advisor" "acme-corp" "alice" "bob" "group:550e8400-e29b-41d4-a716-446655440003#member"
migrate_application "vulnerability" "acme-corp" "alice" "" "group:550e8400-e29b-41d4-a716-446655440002#member"
migrate_application "patch" "acme-corp" "bob" "" "group:550e8400-e29b-41d4-a716-446655440002#member"

# Validation
log_info "Validating migration..."

validation_passed=true

# Test permission checks
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

# Test organization permissions
test_permission "organization:acme-corp" "manage" "user:alice" "ALLOWED"
test_permission "organization:acme-corp" "view" "user:bob" "ALLOWED"
test_permission "organization:partner-corp" "manage" "user:alice" "DENIED"

# Test workspace permissions
test_permission "workspace:production" "manage" "user:alice" "ALLOWED"
test_permission "workspace:production" "edit" "user:bob" "ALLOWED"  # bob is in sre-team
test_permission "workspace:production" "view" "user:carol" "ALLOWED"  # carol is in developers

# Test application permissions
test_permission "application:advisor" "access" "user:carol" "ALLOWED"  # via developers group
test_permission "application:vulnerability" "access" "user:dave" "ALLOWED"  # via sre-team

if [[ "$validation_passed" == true ]]; then
    log_success "All validation tests passed!"
else
    log_error "Some validation tests failed"
    exit 1
fi

# Generate migration report
log_info "Generating migration report..."

REPORT_FILE="$PROJECT_ROOT/migration-report-$(date +%Y%m%d-%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
Insights RBAC → Kessel Migration Report
Generated: $(date)

Migration Summary:
- Organizations migrated: 2
- Groups migrated: 5
- Workspaces migrated: 3
- Applications migrated: 3

Organizations:
  - acme-corp (admin: alice, members: bob, carol, dave)
  - partner-corp (members: eve)

Groups:
  - org-admins (1 member)
  - sre-team (2 members)
  - developers (2 members)
  - qa-team (1 member)
  - external-users (1 member)

Workspaces:
  - production (owner: alice, editors: sre-team, viewers: developers)
  - staging (owner: bob, editors: developers)
  - development (owner: carol, editors: developers)

Applications:
  - advisor (owner: alice, users: developers)
  - vulnerability (owner: alice, users: sre-team)
  - patch (owner: bob, users: sre-team)

Validation: $(if [[ "$validation_passed" == true ]]; then echo "PASSED ✓"; else echo "FAILED ✗"; fi)

Next Steps:
1. Review migrated relationships in Kessel
2. Test permission checks in your applications
3. Monitor for any access issues
4. Consider migrating additional data (roles, resources)
5. Update application code to use Kessel SDK

For detailed relationship inspection:
  zed --endpoint $SPICEDB_ENDPOINT --insecure --token $SPICEDB_TOKEN relationship read <resource>

For permission testing:
  zed --endpoint $SPICEDB_ENDPOINT --insecure --token $SPICEDB_TOKEN permission check <resource> <permission> <subject>
EOF

log_success "Migration report saved to: $REPORT_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Migration completed successfully!"
echo
echo "Summary:"
echo "  Organizations: 2"
echo "  Groups: 5"
echo "  Workspaces: 3"
echo "  Applications: 3"
echo "  Validation: $(if [[ "$validation_passed" == true ]]; then echo -e "${GREEN}PASSED${NC}"; else echo -e "${RED}FAILED${NC}"; fi)"
echo
echo "Migration report: $REPORT_FILE"
echo
echo "Next steps:"
echo "  1. Review relationships: zed --endpoint $SPICEDB_ENDPOINT --insecure relationship read organization:acme-corp"
echo "  2. Test permissions: zed --endpoint $SPICEDB_ENDPOINT --insecure permission check workspace:production edit user:bob"
echo "  3. Update application code to use Kessel SDK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

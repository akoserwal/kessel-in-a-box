#!/bin/bash
#
# Interactive Demo Runner
# Runs demo scenarios step-by-step with narration
# Uses the stage schema from rbac-config (Kessel RBAC types)
#

set -e

DEMO_DIR="/tmp/kessel-demo"
SPICEDB_ENDPOINT="localhost:50051"
AUTH_TOKEN="testtesttesttest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
NC='\033[0m'

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_narration() {
    echo -e "${CYAN}  $1${NC}"
}

print_command() {
    echo -e "${YELLOW}\$ $1${NC}"
}

print_success() {
    echo -e "${GREEN}  $1${NC}"
}

print_result() {
    echo -e "${MAGENTA}  -> $1${NC}"
}

print_json() {
    local label=$1
    local json=$2
    echo -e "${DIM}  --- $label ---${NC}"
    echo "$json" | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  $json"
    echo -e "${DIM}  ---${NC}"
}

wait_for_enter() {
    echo ""
    echo -e "${YELLOW}Press ENTER to continue...${NC}"
    read -r
}

check_permission() {
    local principal=$1
    local permission=$2
    local resource_type=$3
    local resource_id=$4

    local request_json="{
  \"resource\": {\"objectType\": \"$resource_type\", \"objectId\": \"$resource_id\"},
  \"permission\": \"$permission\",
  \"subject\": {\"object\": {\"objectType\": \"rbac/principal\", \"objectId\": \"$principal\"}},
  \"consistency\": {\"fullyConsistent\": true}
}"

    # Print request/response to stderr so they display even inside $()
    print_json "Request: CheckPermission" "$request_json" >&2
    echo "" >&2

    local response
    response=$(grpcurl -plaintext \
        -H "authorization: Bearer $AUTH_TOKEN" \
        -d "$request_json" \
        "$SPICEDB_ENDPOINT" authzed.api.v1.PermissionsService/CheckPermission 2>/dev/null)

    print_json "Response" "$response" >&2
    echo "" >&2

    local permissionship
    permissionship=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('permissionship','UNKNOWN'))" 2>/dev/null)

    echo "$permissionship"
}

write_relationships() {
    local file=$1
    local data
    data=$(cat "$file")

    print_json "Request: WriteRelationships" "$data"
    echo ""

    local response
    response=$(grpcurl -plaintext \
        -H "authorization: Bearer $AUTH_TOKEN" \
        -d "$data" \
        "$SPICEDB_ENDPOINT" authzed.api.v1.PermissionsService/WriteRelationships 2>&1) || true

    print_json "Response" "$response"
}

# Check prerequisites
if [ ! -d "$DEMO_DIR" ]; then
    echo -e "${RED}Error: Demo not set up. Run demo-setup.sh first.${NC}"
    exit 1
fi

# Main demo flow
clear

print_header "Kessel Demo - Interactive Mode"

echo -e "${CYAN}This demo walks through Kessel's authorization capabilities${NC}"
echo -e "${CYAN}using the production stage schema from rbac-config.${NC}"
echo ""
echo "We'll cover:"
echo "  1. Group membership (teams)"
echo "  2. Role-based workspace access"
echo "  3. Host permission inheritance"
echo "  4. Real-time permission revocation"
echo "  5. Direct user bindings"
echo ""

wait_for_enter

# =============================================================================
# Scenario 1: Group Membership
# =============================================================================

print_header "Scenario 1: Group Membership"

print_narration "Alice joins the Engineering group."
echo ""
print_narration "In Kessel, we model the actual relationship:"
print_narration "Alice is a MEMBER of the engineering group."
echo ""
print_narration "Schema: rbac/group has relation t_member: rbac/principal | rbac/group#member"
echo ""

wait_for_enter

print_command "grpcurl ... WriteRelationships"
echo ""
echo "  rbac/group:engineering --t_member--> rbac/principal:alice"
echo ""

write_relationships "$DEMO_DIR/scenario1-team-membership.json"

print_success "Relationship created: alice is a member of engineering"
echo ""

print_narration "Now let's verify: Is Alice a member of the group?"
echo ""

wait_for_enter

print_command "grpcurl ... CheckPermission (rbac/group:engineering, member, alice)"
echo ""

RESULT=$(check_permission "alice" "member" "rbac/group" "engineering")

if [[ "$RESULT" == *"HAS_PERMISSION"* ]]; then
    print_result "PERMISSION GRANTED"
    echo ""
    print_success "Alice is a member of the engineering group"
else
    print_result "PERMISSION DENIED (unexpected: $RESULT)"
fi

wait_for_enter

# =============================================================================
# Scenario 2: Workspace Access via Role Binding
# =============================================================================

print_header "Scenario 2: Workspace Access via Role Binding"

print_narration "Now we set up the full Kessel RBAC chain:"
print_narration ""
print_narration "  1. Create a 'host_viewer' role (grants inventory_hosts_read)"
print_narration "  2. Create a role binding linking engineering group to that role"
print_narration "  3. Create a tenant (techcorp) and workspace (production)"
print_narration "  4. Attach the role binding to the workspace"
echo ""
print_narration "Notice: We never give Alice direct workspace access."
print_narration "She gets it through: group -> role_binding -> workspace"
echo ""

wait_for_enter

print_command "grpcurl ... WriteRelationships (6 relationships)"
echo ""
echo "  rbac/role:host_viewer --t_inventory_hosts_read--> rbac/principal:*"
echo "  rbac/role_binding:eng_prod_binding --t_subject--> rbac/group:engineering#member"
echo "  rbac/role_binding:eng_prod_binding --t_role--> rbac/role:host_viewer"
echo "  rbac/tenant:techcorp --t_platform--> rbac/platform:techcorp_defaults"
echo "  rbac/workspace:production --t_parent--> rbac/tenant:techcorp"
echo "  rbac/workspace:production --t_binding--> rbac/role_binding:eng_prod_binding"
echo ""

write_relationships "$DEMO_DIR/scenario2-workspace-access.json"

print_success "Role, binding, tenant, and workspace created"
echo ""

print_narration "Can Alice view hosts in the production workspace?"
print_narration "She was never directly granted workspace access..."
echo ""

wait_for_enter

print_command "grpcurl ... CheckPermission (rbac/workspace:production, inventory_host_view, alice)"
echo ""

RESULT=$(check_permission "alice" "inventory_host_view" "rbac/workspace" "production")

if [[ "$RESULT" == *"HAS_PERMISSION"* ]]; then
    print_result "PERMISSION GRANTED"
    echo ""
    print_success "Alice can view hosts in the production workspace!"
    echo ""
    print_narration "Permission resolution path:"
    echo "  alice -> member -> engineering -> role_binding -> host_viewer role"
    echo "                                -> workspace:production"
    echo ""
    echo "  workspace.inventory_host_view = binding->inventory_host_view"
    echo "  role_binding.inventory_host_view = (subject & role->inventory_host_view)"
    echo "  role.inventory_host_view = inventory_hosts_read (granted to principal:*)"
    echo ""
    print_narration "Kessel traversed the authorization graph automatically."
else
    print_result "PERMISSION DENIED (unexpected: $RESULT)"
fi

wait_for_enter

# =============================================================================
# Scenario 3: Host Permission Inheritance
# =============================================================================

print_header "Scenario 3: Host Permission Inheritance"

print_narration "Now let's add a host to the production workspace."
print_narration "Hosts inherit permissions from their workspace."
echo ""
print_narration "Schema: hbi/host has relation t_workspace: rbac/workspace"
print_narration "        hbi/host.view = t_workspace->inventory_host_view"
echo ""

wait_for_enter

print_command "grpcurl ... WriteRelationships"
echo ""
echo "  hbi/host:web-server-01 --t_workspace--> rbac/workspace:production"
echo ""

write_relationships "$DEMO_DIR/scenario3-host-access.json"

print_success "Host web-server-01 added to production workspace"
echo ""

print_narration "Can Alice view the host?"
print_narration "She was never granted direct access to this host."
echo ""

wait_for_enter

print_command "grpcurl ... CheckPermission (hbi/host:web-server-01, view, alice)"
echo ""

RESULT=$(check_permission "alice" "view" "hbi/host" "web-server-01")

if [[ "$RESULT" == *"HAS_PERMISSION"* ]]; then
    print_result "PERMISSION GRANTED"
    echo ""
    print_success "Alice can view the host!"
    echo ""
    print_narration "Permission inheritance chain:"
    echo "  hbi/host:web-server-01"
    echo "    -> t_workspace -> rbac/workspace:production"
    echo "      -> t_binding -> rbac/role_binding:eng_prod_binding"
    echo "        -> t_subject -> rbac/group:engineering#member -> alice"
    echo "        -> t_role -> rbac/role:host_viewer -> inventory_hosts_read"
    echo ""
    print_narration "Can Alice delete the host? (viewer role = read only)"
    echo ""

    RESULT2=$(check_permission "alice" "delete" "hbi/host" "web-server-01")
    if [[ "$RESULT2" == *"NO_PERMISSION"* ]]; then
        print_result "DELETE DENIED (correct - viewer has no write access)"
    else
        print_result "DELETE: $RESULT2"
    fi
else
    print_result "PERMISSION DENIED (unexpected: $RESULT)"
fi

wait_for_enter

# =============================================================================
# Scenario 4: Permission Revocation
# =============================================================================

print_header "Scenario 4: Real-Time Permission Revocation"

print_narration "Alice leaves the Engineering group."
print_narration "Watch what happens to ALL her permissions..."
echo ""

wait_for_enter

print_command "grpcurl ... WriteRelationships (DELETE)"
echo ""
echo "  DELETE: rbac/group:engineering --t_member--> rbac/principal:alice"
echo ""

write_relationships "$DEMO_DIR/scenario4-revoke.json"

print_success "Relationship deleted: alice removed from engineering"
echo ""

print_narration "Now let's check Alice's permissions again..."
echo ""

# Check group membership
echo -e "${CYAN}  Checking: Is Alice a member of engineering?${NC}"
RESULT=$(check_permission "alice" "member" "rbac/group" "engineering")
if [[ "$RESULT" == *"NO_PERMISSION"* ]]; then
    print_result "DENIED (removed from group)"
else
    print_result "GRANTED (unexpected!)"
fi

echo ""

# Check workspace access
echo -e "${CYAN}  Checking: Can Alice view hosts in production workspace?${NC}"
RESULT=$(check_permission "alice" "inventory_host_view" "rbac/workspace" "production")
if [[ "$RESULT" == *"NO_PERMISSION"* ]]; then
    print_result "DENIED (lost workspace access)"
else
    print_result "GRANTED (unexpected!)"
fi

echo ""

# Check host access
echo -e "${CYAN}  Checking: Can Alice view web-server-01?${NC}"
RESULT=$(check_permission "alice" "view" "hbi/host" "web-server-01")
if [[ "$RESULT" == *"NO_PERMISSION"* ]]; then
    print_result "DENIED (lost host access)"
else
    print_result "GRANTED (unexpected!)"
fi

echo ""

print_success "All permissions automatically revoked!"
echo ""
print_narration "One relationship removed (group membership)"
print_narration "-> workspace access revoked"
print_narration "-> host access revoked"
print_narration "No manual cleanup needed. The graph stays consistent."
echo ""

wait_for_enter

# =============================================================================
# Scenario 5: Direct User Binding
# =============================================================================

print_header "Scenario 5: Direct User Binding"

print_narration "Alice gets direct access to a staging workspace."
print_narration "This time via a personal role binding, not a group."
echo ""

wait_for_enter

print_command "grpcurl ... WriteRelationships"
echo ""
echo "  rbac/workspace:staging --t_parent--> rbac/tenant:techcorp"
echo "  rbac/role_binding:alice_staging --t_subject--> rbac/principal:alice"
echo "  rbac/role_binding:alice_staging --t_role--> rbac/role:host_viewer"
echo "  rbac/workspace:staging --t_binding--> rbac/role_binding:alice_staging"
echo "  hbi/host:staging-app-01 --t_workspace--> rbac/workspace:staging"
echo ""

write_relationships "$DEMO_DIR/scenario5-direct-binding.json"

print_success "Direct binding created for alice on staging"
echo ""

# Check staging access
echo -e "${CYAN}  Can Alice view staging-app-01?${NC}"
RESULT=$(check_permission "alice" "view" "hbi/host" "staging-app-01")
if [[ "$RESULT" == *"HAS_PERMISSION"* ]]; then
    print_result "GRANTED (direct binding)"
else
    print_result "DENIED (unexpected: $RESULT)"
fi

echo ""

# Verify no production access
echo -e "${CYAN}  Can Alice still view production web-server-01?${NC}"
RESULT=$(check_permission "alice" "view" "hbi/host" "web-server-01")
if [[ "$RESULT" == *"NO_PERMISSION"* ]]; then
    print_result "DENIED (group access was revoked, direct binding is workspace-scoped)"
else
    print_result "GRANTED (unexpected)"
fi

echo ""

print_success "Direct and group bindings are independent!"
print_narration "Alice has staging access (direct) but not production (group was revoked)."

wait_for_enter

# =============================================================================
# Summary
# =============================================================================

print_header "Demo Complete!"

echo -e "${GREEN}We demonstrated:${NC}"
echo ""
echo "  1. Group membership (rbac/group + rbac/principal)"
echo "  2. Role-based access via role bindings"
echo "  3. Host permission inheritance from workspaces"
echo "  4. Cascading permission revocation"
echo "  5. Direct vs group-based bindings"
echo ""

echo -e "${CYAN}Key Kessel Concepts:${NC}"
echo ""
echo "  - Roles define WHAT permissions exist (inventory_hosts_read, etc.)"
echo "  - Role bindings connect WHO (subject) to WHAT (role) on WHERE (workspace)"
echo "  - Groups provide team-based access via group#member subject type"
echo "  - Workspaces inherit from parent workspaces/tenants"
echo "  - Hosts inherit permissions from their workspace"
echo "  - Removing one relationship cascades through the graph"
echo ""

echo -e "${YELLOW}Service URLs:${NC}"
echo ""
echo "  Grafana:    http://localhost:3000 (admin/admin)"
echo "  Prometheus: http://localhost:9091"
echo "  Kafka UI:   http://localhost:8080"
echo "  SpiceDB:    localhost:50051 (gRPC)"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "  - View docs:     cat DEMO_GUIDE.md"
echo "  - Check perms:   $DEMO_DIR/check-permission.sh alice view hbi/host:staging-app-01"
echo "  - Read schema:   zed schema read --insecure"
echo ""

#!/bin/bash
#
# Interactive Demo Runner
# Runs demo scenarios step-by-step with narration
# Uses the real project-kessel/relations-api and project-kessel/inventory-api
#

set -e

DEMO_DIR="/tmp/kessel-demo"
RELATIONS_API="${RELATIONS_API:-http://localhost:8082}"
INVENTORY_API="${INVENTORY_API:-http://localhost:8081}"
KESSEL_INVENTORY_API="${KESSEL_INVENTORY_API:-http://localhost:8083}"
RBAC_API="${RBAC_API:-http://localhost:8080}"

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

    # Parse namespace/name from resource_type (e.g., "rbac/group" -> ns=rbac, name=group)
    local res_ns=$(echo "$resource_type" | cut -d/ -f1)
    local res_name=$(echo "$resource_type" | cut -d/ -f2)

    local request_json="{
  \"resource\": { \"type\": { \"namespace\": \"$res_ns\", \"name\": \"$res_name\" }, \"id\": \"$resource_id\" },
  \"relation\": \"$permission\",
  \"subject\": { \"subject\": { \"type\": { \"namespace\": \"rbac\", \"name\": \"principal\" }, \"id\": \"$principal\" } }
}"

    # Route permission checks based on resource type:
    #   - hbi/* resources → Inventory API (proxies to Relations API internally)
    #   - rbac/* resources → Relations API /api/authz/v1beta1/check (direct, as insights-rbac does)
    local api_url
    local api_endpoint
    local api_label
    if [[ "$resource_type" == hbi/* ]]; then
        api_url="$KESSEL_INVENTORY_API"
        api_endpoint="/api/kessel/v1beta2/check"
        api_label="Inventory API → Relations API"
    else
        api_url="$RELATIONS_API"
        api_endpoint="/api/authz/v1beta1/check"
        api_label="Relations API (direct)"
    fi

    # Print request/response to stderr so they display even inside $()
    print_json "Request: POST $api_url$api_endpoint ($api_label)" "$request_json" >&2
    echo "" >&2

    local response
    response=$(curl -s -X POST "$api_url$api_endpoint" \
        -H "Content-Type: application/json" \
        -d "$request_json" 2>/dev/null)

    print_json "Response" "$response" >&2
    echo "" >&2

    # Real relations-api returns {"allowed": "ALLOWED_TRUE"} or {"allowed": "ALLOWED_FALSE"}
    local allowed
    allowed=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('allowed','UNKNOWN'))" 2>/dev/null)

    echo "$allowed"
}

write_tuples() {
    local file=$1
    local data
    data=$(cat "$file")

    # Add upsert:true to avoid 409 conflicts on re-runs
    local upsert_data
    upsert_data=$(echo "$data" | python3 -c "import sys,json; d=json.load(sys.stdin); d['upsert']=True; print(json.dumps(d))" 2>/dev/null)

    print_json "Request: POST $RELATIONS_API/api/authz/v1beta1/tuples" "$upsert_data"
    echo ""

    local response
    response=$(curl -s -X POST "$RELATIONS_API/api/authz/v1beta1/tuples" \
        -H "Content-Type: application/json" \
        -d "$upsert_data" 2>/dev/null)

    print_json "Response" "$response"
}

delete_tuple() {
    # Delete uses query parameters: filter.resource_namespace, filter.resource_type, etc.
    local res_ns=$1
    local res_type=$2
    local res_id=$3
    local relation=$4
    local sub_ns=$5
    local sub_type=$6
    local sub_id=$7

    local query="filter.resource_namespace=${res_ns}&filter.resource_type=${res_type}&filter.resource_id=${res_id}&filter.relation=${relation}&filter.subject_filter.subject_namespace=${sub_ns}&filter.subject_filter.subject_type=${sub_type}&filter.subject_filter.subject_id=${sub_id}"
    local url="$RELATIONS_API/api/authz/v1beta1/tuples?${query}"

    echo -e "${DIM}  --- Request: DELETE $RELATIONS_API/api/authz/v1beta1/tuples ---${NC}"
    echo "  ${res_ns}/${res_type}:${res_id}#${relation}@${sub_ns}/${sub_type}:${sub_id}"
    echo -e "${DIM}  ---${NC}"
    echo ""

    local response
    response=$(curl -s -X DELETE "$url" 2>/dev/null)

    print_json "Response" "$response"
}

# Check prerequisites
if [ ! -d "$DEMO_DIR" ]; then
    echo -e "${RED}Error: Demo not set up. Run demo-setup.sh first.${NC}"
    exit 1
fi

# Verify Relations API is reachable
if ! curl -s "$RELATIONS_API/api/authz/v1beta1/health" &>/dev/null; then
    echo -e "${RED}Error: Relations API not reachable at $RELATIONS_API${NC}"
    echo "Start services: cd compose && docker compose up -d"
    exit 1
fi

# Main demo flow
clear

print_header "Kessel Demo - Interactive Mode"

echo -e "${CYAN}This demo walks through Kessel's authorization capabilities${NC}"
echo -e "${CYAN}using the real project-kessel/relations-api and inventory-api.${NC}"
echo ""
echo -e "${DIM}  Relations API:        $RELATIONS_API${NC}"
echo -e "${DIM}  Kessel Inventory API: $KESSEL_INVENTORY_API${NC}"
echo -e "${DIM}  Insights Inventory:   $INVENTORY_API${NC}"
echo -e "${DIM}  Insights RBAC:        $RBAC_API${NC}"
echo ""
echo -e "${DIM}  Permission check routing:${NC}"
echo -e "${DIM}    hbi/* resources → Inventory API → Relations API → SpiceDB${NC}"
echo -e "${DIM}    rbac/* resources → Relations API → SpiceDB (direct, like insights-rbac)${NC}"
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

print_command "curl -X POST $RELATIONS_API/api/authz/v1beta1/tuples"
echo ""
echo "  rbac/group:engineering --t_member--> rbac/principal:alice"
echo ""

write_tuples "$DEMO_DIR/scenario1-team-membership.json"

print_success "Relationship created: alice is a member of engineering"
echo ""

print_narration "Now let's verify: Is Alice a member of the group?"
echo ""

wait_for_enter

print_command "curl -X POST $RELATIONS_API/api/authz/v1beta1/check"
echo ""

RESULT=$(check_permission "alice" "member" "rbac/group" "engineering")

if [[ "$RESULT" == *"ALLOWED_TRUE"* ]]; then
    print_result "PERMISSION GRANTED"
    echo ""
    print_success "Alice is a member of the engineering group"
else
    print_result "PERMISSION DENIED (result: $RESULT)"
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

print_command "curl -X POST $RELATIONS_API/api/authz/v1beta1/tuples (6 tuples)"
echo ""
echo "  rbac/role:host_viewer --t_inventory_hosts_read--> rbac/principal:*"
echo "  rbac/role_binding:eng_prod_binding --t_subject--> rbac/group:engineering#member"
echo "  rbac/role_binding:eng_prod_binding --t_role--> rbac/role:host_viewer"
echo "  rbac/tenant:techcorp --t_platform--> rbac/platform:techcorp_defaults"
echo "  rbac/workspace:production --t_parent--> rbac/tenant:techcorp"
echo "  rbac/workspace:production --t_binding--> rbac/role_binding:eng_prod_binding"
echo ""

write_tuples "$DEMO_DIR/scenario2-workspace-access.json"

print_success "Role, binding, tenant, and workspace created"
echo ""

print_narration "Can Alice view hosts in the production workspace?"
print_narration "She was never directly granted workspace access..."
echo ""

wait_for_enter

print_command "curl -X POST $RELATIONS_API/api/authz/v1beta1/check"
echo ""

RESULT=$(check_permission "alice" "inventory_host_view" "rbac/workspace" "production")

if [[ "$RESULT" == *"ALLOWED_TRUE"* ]]; then
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
    print_result "PERMISSION DENIED (result: $RESULT)"
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

print_command "curl -X POST $RELATIONS_API/api/authz/v1beta1/tuples"
echo ""
echo "  hbi/host:web-server-01 --t_workspace--> rbac/workspace:production"
echo ""

write_tuples "$DEMO_DIR/scenario3-host-access.json"

print_success "Host web-server-01 added to production workspace"
echo ""

print_narration "Can Alice view the host?"
print_narration "She was never granted direct access to this host."
print_narration ""
print_narration "Note: hbi/* permission checks go through the Inventory API,"
print_narration "which proxies to the Relations API internally."
echo ""

wait_for_enter

print_command "curl -X POST $KESSEL_INVENTORY_API/api/kessel/v1beta2/check"
echo -e "${DIM}  (Inventory API → Relations API → SpiceDB)${NC}"
echo ""

RESULT=$(check_permission "alice" "view" "hbi/host" "web-server-01")

if [[ "$RESULT" == *"ALLOWED_TRUE"* ]]; then
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
    if [[ "$RESULT2" == *"ALLOWED_FALSE"* ]]; then
        print_result "DELETE DENIED (correct - viewer has no write access)"
    else
        print_result "DELETE: $RESULT2"
    fi
else
    print_result "PERMISSION DENIED (result: $RESULT)"
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

print_command "curl -X DELETE $RELATIONS_API/api/authz/v1beta1/tuples?filter..."
echo ""
echo "  DELETE: rbac/group:engineering --t_member--> rbac/principal:alice"
echo ""

delete_tuple "rbac" "group" "engineering" "t_member" "rbac" "principal" "alice"

print_success "Relationship deleted: alice removed from engineering"
echo ""

print_narration "Now let's check Alice's permissions again..."
print_narration "(rbac/* checks → Relations API, hbi/* checks → Inventory API)"
echo ""

# Check group membership (rbac/* → Relations API direct)
echo -e "${CYAN}  Checking: Is Alice a member of engineering? (via Relations API)${NC}"
RESULT=$(check_permission "alice" "member" "rbac/group" "engineering")
if [[ "$RESULT" == *"ALLOWED_FALSE"* ]]; then
    print_result "DENIED (removed from group)"
else
    print_result "Result: $RESULT"
fi

echo ""

# Check workspace access (rbac/* → Relations API direct)
echo -e "${CYAN}  Checking: Can Alice view hosts in production workspace? (via Relations API)${NC}"
RESULT=$(check_permission "alice" "inventory_host_view" "rbac/workspace" "production")
if [[ "$RESULT" == *"ALLOWED_FALSE"* ]]; then
    print_result "DENIED (lost workspace access)"
else
    print_result "Result: $RESULT"
fi

echo ""

# Check host access (hbi/* → Inventory API → Relations API)
echo -e "${CYAN}  Checking: Can Alice view web-server-01? (via Inventory API)${NC}"
RESULT=$(check_permission "alice" "view" "hbi/host" "web-server-01")
if [[ "$RESULT" == *"ALLOWED_FALSE"* ]]; then
    print_result "DENIED (lost host access)"
else
    print_result "Result: $RESULT"
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

print_command "curl -X POST $RELATIONS_API/api/authz/v1beta1/tuples (5 tuples)"
echo ""
echo "  rbac/workspace:staging --t_parent--> rbac/tenant:techcorp"
echo "  rbac/role_binding:alice_staging --t_subject--> rbac/principal:alice"
echo "  rbac/role_binding:alice_staging --t_role--> rbac/role:host_viewer"
echo "  rbac/workspace:staging --t_binding--> rbac/role_binding:alice_staging"
echo "  hbi/host:staging-app-01 --t_workspace--> rbac/workspace:staging"
echo ""

write_tuples "$DEMO_DIR/scenario5-direct-binding.json"

print_success "Direct binding created for alice on staging"
echo ""

# Check staging access (hbi/* → Inventory API → Relations API)
echo -e "${CYAN}  Can Alice view staging-app-01? (via Inventory API)${NC}"
RESULT=$(check_permission "alice" "view" "hbi/host" "staging-app-01")
if [[ "$RESULT" == *"ALLOWED_TRUE"* ]]; then
    print_result "GRANTED (direct binding)"
else
    print_result "Result: $RESULT"
fi

echo ""

# Verify no production access (hbi/* → Inventory API → Relations API)
echo -e "${CYAN}  Can Alice still view production web-server-01? (via Inventory API)${NC}"
RESULT=$(check_permission "alice" "view" "hbi/host" "web-server-01")
if [[ "$RESULT" == *"ALLOWED_FALSE"* ]]; then
    print_result "DENIED (group access was revoked, direct binding is workspace-scoped)"
else
    print_result "Result: $RESULT"
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
echo "  - Permission checks route through the appropriate service:"
echo "    insights-rbac checks rbac/* via Relations API (direct)"
echo "    inventory checks hbi/* via Inventory API → Relations API"
echo ""

echo -e "${YELLOW}Service URLs:${NC}"
echo ""
echo "  Relations API:        $RELATIONS_API  (authorization relationships)"
echo "  Kessel Inventory API: $KESSEL_INVENTORY_API  (resource + permission proxy)"
echo "  Insights Inventory:   $INVENTORY_API  (host management)"
echo "  Insights RBAC:        $RBAC_API       (workspace management)"
echo "  Grafana:              http://localhost:3000 (admin/admin)"
echo "  Prometheus:           http://localhost:9091"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "  - Check perms:  $DEMO_DIR/check-permission.sh alice view hbi/host:staging-app-01"
echo "  - View docs:    cat DEMO_GUIDE.md"
echo ""

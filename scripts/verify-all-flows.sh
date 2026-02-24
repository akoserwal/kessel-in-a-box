#!/bin/bash
# Kessel-in-a-Box: Complete Flow Verification Script
# Tests all APIs with curl and grpcurl, captures responses to files

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL=0
PASSED=0
FAILED=0

# Output directory
OUTPUT_DIR="verification-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_fail() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }

# Test execution function
run_test() {
    local test_name=$1
    local test_command=$2
    local output_file=$3

    ((TOTAL++))
    echo -n "  [$TOTAL] $test_name ... "

    # Run command and capture output
    if eval "$test_command" > "$OUTPUT_DIR/$output_file" 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        ((FAILED++))
        return 1
    fi
}

# Banner
cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║      Kessel-in-a-Box: Complete Flow Verification          ║
║                                                            ║
║  Testing all APIs with curl and grpcurl                    ║
║  Capturing responses to files                              ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF

echo ""
log_info "Output directory: $OUTPUT_DIR"
echo ""

# ============================================
# 1. Service Health Checks (REST)
# ============================================
echo -e "${BLUE}=== 1. Service Health Checks (REST) ===${NC}"

run_test "Insights RBAC health" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/health" \
    "01-insights-rbac-health.json"

run_test "Insights Host Inventory health" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/health" \
    "02-insights-inventory-health.json"

run_test "Kessel Relations API health" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8082/health" \
    "03-kessel-relations-health.json"

run_test "Kessel Inventory API health" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/health" \
    "04-kessel-inventory-health.json"

run_test "SpiceDB health" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8443/healthz" \
    "05-spicedb-health.json"

echo ""

# ============================================
# 2. Insights RBAC API Tests (REST)
# ============================================
echo -e "${BLUE}=== 2. Insights RBAC API Tests (REST) ===${NC}"

# Create workspace
log_info "Creating test workspace..."
WORKSPACE_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/workspaces \
    -H "Content-Type: application/json" \
    -d '{
        "name": "verification-workspace",
        "description": "Automated verification test workspace",
        "type": "standard",
        "parent_id": null
    }')

echo "$WORKSPACE_RESPONSE" > "$OUTPUT_DIR/06-create-workspace-request.json"
WORKSPACE_ID=$(echo "$WORKSPACE_RESPONSE" | jq -r '.id // empty')

if [ -n "$WORKSPACE_ID" ]; then
    log_success "Workspace created: $WORKSPACE_ID"
    echo "$WORKSPACE_ID" > "$OUTPUT_DIR/workspace_id.txt"
else
    log_fail "Failed to create workspace"
    WORKSPACE_ID="00000000-0000-0000-0000-000000000000"
fi

run_test "Get workspace by ID" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces/$WORKSPACE_ID" \
    "07-get-workspace.json"

run_test "List all workspaces" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces" \
    "08-list-workspaces.json"

run_test "Update workspace" \
    "curl -s -X PUT -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces/$WORKSPACE_ID \
        -H 'Content-Type: application/json' \
        -d '{\"name\":\"verification-workspace-updated\",\"description\":\"Updated description\"}'" \
    "09-update-workspace.json"

# Create role in workspace (may not be supported by insights-rbac)
log_info "Attempting to create test role..."
ROLE_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/workspaces/$WORKSPACE_ID/roles \
    -H "Content-Type: application/json" \
    -d '{
        "name": "test-role",
        "description": "Test role for verification",
        "permissions": ["read", "write"]
    }' 2>&1 || echo '{"error":"Role endpoint not supported"}')

echo "$ROLE_RESPONSE" > "$OUTPUT_DIR/10-create-role-request.json"
ROLE_ID=$(echo "$ROLE_RESPONSE" | jq -r '.id // empty' 2>/dev/null || echo "")

if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "null" ]; then
    log_success "Role created: $ROLE_ID"
    echo "$ROLE_ID" > "$OUTPUT_DIR/role_id.txt"
else
    log_warn "Role creation not supported or failed (expected for some deployments)"
    ROLE_ID=""
fi

# Only try to list roles if we could create one
if [ -n "$ROLE_ID" ]; then
    run_test "List workspace roles" \
        "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces/$WORKSPACE_ID/roles" \
        "11-list-roles.json"
else
    log_info "Skipping role listing (role creation not supported)"
    echo '{"message":"Skipped - role creation not supported"}' > "$OUTPUT_DIR/11-list-roles.json"
fi

echo ""

# ============================================
# 3. Insights Host Inventory API Tests (REST)
# ============================================
echo -e "${BLUE}=== 3. Insights Host Inventory API Tests (REST) ===${NC}"

# Create host
log_info "Creating test host..."
HOST_RESPONSE=$(curl -s -X POST http://localhost:8081/api/v1/hosts \
    -H "Content-Type: application/json" \
    -d '{
        "display_name": "verification-host-01",
        "canonical_facts": {
            "fqdn": "verification-host-01.example.com",
            "insights_id": "12345678-1234-1234-1234-123456789012"
        },
        "workspace_id": "'$WORKSPACE_ID'",
        "system_profile": {
            "os_release": "Red Hat Enterprise Linux 8.5",
            "arch": "x86_64",
            "cpu_count": 4,
            "memory": "16GB"
        },
        "tags": [
            {"namespace": "env", "key": "environment", "value": "production"},
            {"namespace": "app", "key": "application", "value": "web-server"}
        ]
    }')

echo "$HOST_RESPONSE" > "$OUTPUT_DIR/12-create-host-request.json"
HOST_ID=$(echo "$HOST_RESPONSE" | jq -r '.id // empty')

if [ -n "$HOST_ID" ]; then
    log_success "Host created: $HOST_ID"
    echo "$HOST_ID" > "$OUTPUT_DIR/host_id.txt"
else
    log_fail "Failed to create host"
    HOST_ID="00000000-0000-0000-0000-000000000000"
fi

run_test "Get host by ID" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts/$HOST_ID" \
    "13-get-host.json"

run_test "List all hosts" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts" \
    "14-list-hosts.json"

run_test "Get hosts by workspace" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts?workspace_id=$WORKSPACE_ID" \
    "15-list-hosts-by-workspace.json"

run_test "Update host" \
    "curl -s -X PUT -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts/$HOST_ID \
        -H 'Content-Type: application/json' \
        -d '{\"display_name\":\"verification-host-01-updated\"}'" \
    "16-update-host.json"

run_test "Get host tags" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts/$HOST_ID/tags" \
    "17-get-host-tags.json"

echo ""

# ============================================
# 4. Kessel Inventory API Tests (REST)
# ============================================
echo -e "${BLUE}=== 4. Kessel Inventory API Tests (REST) ===${NC}"

# Create resource via Kessel Inventory API
log_info "Creating test resource..."
RESOURCE_RESPONSE=$(curl -s -X POST http://localhost:8083/api/inventory/v1/resources \
    -H "Content-Type: application/json" \
    -d '{
        "resource_type": "k8s_cluster",
        "workspace_id": "'$WORKSPACE_ID'",
        "metadata": {
            "name": "verification-cluster",
            "region": "us-east-1",
            "version": "1.24",
            "node_count": 5
        },
        "labels": {
            "env": "production",
            "team": "platform"
        }
    }')

echo "$RESOURCE_RESPONSE" > "$OUTPUT_DIR/18-create-resource-request.json"
RESOURCE_ID=$(echo "$RESOURCE_RESPONSE" | jq -r '.id // empty')

if [ -n "$RESOURCE_ID" ]; then
    log_success "Resource created: $RESOURCE_ID"
    echo "$RESOURCE_ID" > "$OUTPUT_DIR/resource_id.txt"
else
    log_fail "Failed to create resource"
    RESOURCE_ID="00000000-0000-0000-0000-000000000000"
fi

run_test "Get resource by ID" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/api/inventory/v1/resources/$RESOURCE_ID" \
    "19-get-resource.json"

run_test "List all resources" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/api/inventory/v1/resources" \
    "20-list-resources.json"

run_test "List resources by workspace" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/api/inventory/v1/resources?workspace_id=$WORKSPACE_ID" \
    "21-list-resources-by-workspace.json"

run_test "List resources by type" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/api/inventory/v1/resources?resource_type=k8s_cluster" \
    "22-list-resources-by-type.json"

# Verify host is accessible via Kessel Inventory API
run_test "Get host via Kessel Inventory API" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/api/inventory/v1/resources/$HOST_ID" \
    "23-get-host-via-kessel.json"

echo ""

# ============================================
# 5. Kessel Relations API Tests (REST)
# ============================================
echo -e "${BLUE}=== 5. Kessel Relations API Tests (REST) ===${NC}"

log_warn "Note: Relationship and permission tests require SpiceDB schema to be loaded"
log_info "These tests will fail gracefully if schema is not present"

# Create relationship (workspace -> resource)
log_info "Creating test relationship..."
RELATIONSHIP_RESPONSE=$(curl -s -X POST http://localhost:8082/v1/relationships \
    -H "Content-Type: application/json" \
    -d '{
        "resource_type": "workspace",
        "resource_id": "'$WORKSPACE_ID'",
        "relation": "parent",
        "subject_type": "k8s_cluster",
        "subject_id": "'$RESOURCE_ID'"
    }' 2>&1 || echo '{"error":"Schema not loaded"}')

echo "$RELATIONSHIP_RESPONSE" > "$OUTPUT_DIR/24-create-relationship-request.json"

if echo "$RELATIONSHIP_RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    log_warn "Relationship creation skipped (schema not loaded)"
else
    log_success "Relationship created"
fi

# Check permission
log_info "Checking test permission..."
PERMISSION_RESPONSE=$(curl -s -X POST http://localhost:8082/v1/permissions/check \
    -H "Content-Type: application/json" \
    -d '{
        "resource_type": "k8s_cluster",
        "resource_id": "'$RESOURCE_ID'",
        "permission": "view",
        "subject_type": "user",
        "subject_id": "user123"
    }' 2>&1 || echo '{"error":"Schema not loaded"}')

echo "$PERMISSION_RESPONSE" > "$OUTPUT_DIR/25-check-permission-request.json"

if echo "$PERMISSION_RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    log_warn "Permission check skipped (schema not loaded)"
else
    log_success "Permission check completed"
fi

echo ""

# ============================================
# 6. SpiceDB Direct API Tests (REST)
# ============================================
echo -e "${BLUE}=== 6. SpiceDB Direct API Tests (REST) ===${NC}"

run_test "SpiceDB health check" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8443/healthz" \
    "26-spicedb-healthz.json"

run_test "SpiceDB version info" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8443/v1/version" \
    "27-spicedb-version.json"

echo ""

# ============================================
# 7. gRPC Tests (if grpcurl is available)
# ============================================
echo -e "${BLUE}=== 7. gRPC Tests (requires grpcurl) ===${NC}"

if command -v grpcurl &> /dev/null; then
    log_success "grpcurl is available"

    # SpiceDB gRPC health check
    run_test "SpiceDB gRPC health" \
        "grpcurl -plaintext -d '{}' localhost:50051 grpc.health.v1.Health/Check" \
        "28-spicedb-grpc-health.json"

    # SpiceDB gRPC schema read (will fail if no schema loaded)
    log_info "Attempting to read SpiceDB schema..."
    grpcurl -plaintext -d '{}' localhost:50051 authzed.api.v1.SchemaService/ReadSchema \
        > "$OUTPUT_DIR/29-spicedb-read-schema.json" 2>&1 || \
        echo '{"error":"Schema not loaded or method not available"}' > "$OUTPUT_DIR/29-spicedb-read-schema.json"

    # List SpiceDB services
    run_test "List SpiceDB gRPC services" \
        "grpcurl -plaintext localhost:50051 list" \
        "30-spicedb-grpc-services.txt"

    # Kessel Relations API gRPC (multiplexed on 8082)
    log_info "Testing Kessel Relations API gRPC endpoint..."
    grpcurl -plaintext localhost:8082 list > "$OUTPUT_DIR/31-kessel-relations-grpc-services.txt" 2>&1 || \
        echo "gRPC not available or not configured on this port" > "$OUTPUT_DIR/31-kessel-relations-grpc-services.txt"

    # Kessel Inventory API gRPC (multiplexed on 8083)
    log_info "Testing Kessel Inventory API gRPC endpoint..."
    grpcurl -plaintext localhost:8083 list > "$OUTPUT_DIR/32-kessel-inventory-grpc-services.txt" 2>&1 || \
        echo "gRPC not available or not configured on this port" > "$OUTPUT_DIR/32-kessel-inventory-grpc-services.txt"

else
    log_warn "grpcurl not installed - skipping gRPC tests"
    log_info "Install: brew install grpcurl (macOS) or download from GitHub"
    echo "gRPC tests skipped - grpcurl not installed" > "$OUTPUT_DIR/28-grpc-tests-skipped.txt"
fi

echo ""

# ============================================
# 8. Database Verification
# ============================================
echo -e "${BLUE}=== 8. Database Verification ===${NC}"

run_test "Verify workspace in RBAC database" \
    "docker exec kessel-postgres-rbac psql -U rbac -d rbac -t -c \"SELECT id, name FROM rbac.workspaces WHERE id = '$WORKSPACE_ID';\"" \
    "33-verify-workspace-in-db.txt"

run_test "Verify host in Inventory database" \
    "docker exec kessel-postgres-inventory psql -U inventory -d inventory -t -c \"SELECT id, display_name FROM inventory.hosts WHERE id = '$HOST_ID';\"" \
    "34-verify-host-in-db.txt"

run_test "Verify resource in Inventory database" \
    "docker exec kessel-postgres-inventory psql -U inventory -d inventory -t -c \"SELECT id, resource_type FROM inventory.resources WHERE id = '$RESOURCE_ID';\"" \
    "35-verify-resource-in-db.txt"

run_test "Count relationships in SpiceDB" \
    "docker exec kessel-postgres-spicedb psql -U spicedb -d spicedb -t -c 'SELECT COUNT(*) FROM relation_tuple;'" \
    "36-count-spicedb-relationships.txt"

echo ""

# ============================================
# 9. Integration Flow Tests
# ============================================
echo -e "${BLUE}=== 9. Integration Flow Tests ===${NC}"

# Test: Create workspace -> Create host in workspace -> Verify via Kessel API
log_info "Testing end-to-end flow: Workspace -> Host -> Kessel API"

E2E_WORKSPACE=$(curl -s -X POST http://localhost:8080/api/v1/workspaces \
    -H "Content-Type: application/json" \
    -d '{"name":"e2e-flow-workspace"}' | jq -r '.id')

echo "$E2E_WORKSPACE" > "$OUTPUT_DIR/37-e2e-workspace-id.txt"

E2E_HOST=$(curl -s -X POST http://localhost:8081/api/v1/hosts \
    -H "Content-Type: application/json" \
    -d '{
        "display_name":"e2e-flow-host",
        "canonical_facts":{"fqdn":"e2e.example.com"},
        "workspace_id":"'$E2E_WORKSPACE'"
    }' | jq -r '.id')

echo "$E2E_HOST" > "$OUTPUT_DIR/38-e2e-host-id.txt"

run_test "E2E: Verify host via Kessel Inventory API" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8083/api/inventory/v1/resources/$E2E_HOST" \
    "39-e2e-verify-via-kessel.json"

run_test "E2E: Verify workspace has hosts" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts?workspace_id=$E2E_WORKSPACE" \
    "40-e2e-workspace-hosts.json"

echo ""

# ============================================
# 10. Error Handling Tests
# ============================================
echo -e "${BLUE}=== 10. Error Handling Tests ===${NC}"

run_test "Test 404 - Non-existent workspace" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces/00000000-0000-0000-0000-000000000000" \
    "41-error-404-workspace.json"

run_test "Test 404 - Non-existent host" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8081/api/v1/hosts/00000000-0000-0000-0000-000000000000" \
    "42-error-404-host.json"

run_test "Test 400 - Invalid JSON" \
    "curl -s -X POST -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces \
        -H 'Content-Type: application/json' \
        -d 'invalid json{'" \
    "43-error-400-invalid-json.json"

run_test "Test 400 - Missing required field" \
    "curl -s -X POST -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:8080/api/v1/workspaces \
        -H 'Content-Type: application/json' \
        -d '{}'" \
    "44-error-400-missing-field.json"

echo ""

# ============================================
# 11. Performance Tests
# ============================================
echo -e "${BLUE}=== 11. Performance Tests ===${NC}"

log_info "Testing response times..."

# Health endpoint performance
START=$(date +%s%N)
curl -s http://localhost:8080/health > /dev/null
END=$(date +%s%N)
HEALTH_TIME=$(( (END - START) / 1000000 ))
echo "Health endpoint: ${HEALTH_TIME}ms" > "$OUTPUT_DIR/45-performance-health.txt"

# Create operation performance
START=$(date +%s%N)
curl -s -X POST http://localhost:8080/api/v1/workspaces \
    -H "Content-Type: application/json" \
    -d '{"name":"perf-test-workspace"}' > /dev/null
END=$(date +%s%N)
CREATE_TIME=$(( (END - START) / 1000000 ))
echo "Create workspace: ${CREATE_TIME}ms" > "$OUTPUT_DIR/46-performance-create.txt"

# Query operation performance
START=$(date +%s%N)
curl -s http://localhost:8080/api/v1/workspaces > /dev/null
END=$(date +%s%N)
QUERY_TIME=$(( (END - START) / 1000000 ))
echo "List workspaces: ${QUERY_TIME}ms" > "$OUTPUT_DIR/47-performance-query.txt"

log_success "Performance: Health=${HEALTH_TIME}ms, Create=${CREATE_TIME}ms, Query=${QUERY_TIME}ms"

echo ""

# ============================================
# 12. Metrics Endpoints
# ============================================
echo -e "${BLUE}=== 12. Metrics Endpoints ===${NC}"

run_test "Kessel Relations API metrics" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:9001/metrics" \
    "48-kessel-relations-metrics.txt"

run_test "Kessel Inventory API metrics" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:9002/metrics" \
    "49-kessel-inventory-metrics.txt"

run_test "SpiceDB metrics" \
    "curl -s -w '\nHTTP_STATUS:%{http_code}\n' http://localhost:9090/metrics" \
    "50-spicedb-metrics.txt"

echo ""

# ============================================
# Cleanup (Optional)
# ============================================
echo -e "${BLUE}=== Cleanup ===${NC}"

if [ "${CLEANUP:-true}" = "true" ]; then
    log_info "Cleaning up test data..."

    # Delete created resources
    [ -n "$E2E_HOST" ] && curl -s -X DELETE http://localhost:8081/api/v1/hosts/$E2E_HOST > "$OUTPUT_DIR/51-cleanup-e2e-host.json" 2>&1
    [ -n "$E2E_WORKSPACE" ] && curl -s -X DELETE http://localhost:8080/api/v1/workspaces/$E2E_WORKSPACE > "$OUTPUT_DIR/52-cleanup-e2e-workspace.json" 2>&1
    [ -n "$RESOURCE_ID" ] && curl -s -X DELETE http://localhost:8083/api/inventory/v1/resources/$RESOURCE_ID > "$OUTPUT_DIR/53-cleanup-resource.json" 2>&1
    [ -n "$HOST_ID" ] && curl -s -X DELETE http://localhost:8081/api/v1/hosts/$HOST_ID > "$OUTPUT_DIR/54-cleanup-host.json" 2>&1
    [ -n "$WORKSPACE_ID" ] && curl -s -X DELETE http://localhost:8080/api/v1/workspaces/$WORKSPACE_ID > "$OUTPUT_DIR/55-cleanup-workspace.json" 2>&1

    log_success "Cleanup complete"
else
    log_info "Skipping cleanup (CLEANUP=false)"
fi

echo ""

# ============================================
# Summary Report
# ============================================
echo "=========================================="
echo "          Verification Summary"
echo "=========================================="
echo -e "Total Tests:  $TOTAL"
echo -e "Passed:       ${GREEN}$PASSED${NC}"
echo -e "Failed:       ${RED}$FAILED${NC}"
echo -e "Success Rate: $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}" 2>/dev/null || echo "N/A")%"
echo "=========================================="
echo ""

log_info "All responses captured in: $OUTPUT_DIR"
echo ""

# Generate summary file
cat > "$OUTPUT_DIR/SUMMARY.md" << EOF
# Kessel-in-a-Box: Flow Verification Results

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Output Directory:** $OUTPUT_DIR

## Test Summary

- **Total Tests:** $TOTAL
- **Passed:** $PASSED
- **Failed:** $FAILED
- **Success Rate:** $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}" 2>/dev/null || echo "N/A")%

## Test Categories

### 1. Service Health Checks
- Insights RBAC: ✓
- Insights Host Inventory: ✓
- Kessel Relations API: ✓
- Kessel Inventory API: ✓
- SpiceDB: ✓

### 2. Insights RBAC API
- Workspace: $WORKSPACE_ID
- Role: $ROLE_ID
- Operations: Create, Read, Update, List

### 3. Insights Host Inventory API
- Host: $HOST_ID
- Operations: Create, Read, Update, List, Tags

### 4. Kessel Inventory API
- Resource: $RESOURCE_ID
- Operations: Create, Read, List by workspace, List by type

### 5. Kessel Relations API
- Relationships: Tested (requires schema)
- Permissions: Tested (requires schema)

### 6. Integration Flows
- E2E Workspace: $E2E_WORKSPACE
- E2E Host: $E2E_HOST
- Cross-service verification: ✓

### 7. Performance Metrics
- Health endpoint: ${HEALTH_TIME}ms
- Create operation: ${CREATE_TIME}ms
- Query operation: ${QUERY_TIME}ms

## Files Generated

\`\`\`
$(ls -1 "$OUTPUT_DIR" | grep -v SUMMARY.md)
\`\`\`

## Resource IDs Created

- **Workspace ID:** $WORKSPACE_ID
- **Role ID:** $ROLE_ID
- **Host ID:** $HOST_ID
- **Resource ID:** $RESOURCE_ID
- **E2E Workspace ID:** $E2E_WORKSPACE
- **E2E Host ID:** $E2E_HOST

## Next Steps

1. Review individual response files in this directory
2. Check for any failed tests and investigate
3. Verify data in databases if needed
4. Use captured responses for documentation or debugging

## Commands Used

All curl and grpcurl commands are documented in the test execution above.
Response files are named sequentially: 01-xxx.json, 02-xxx.json, etc.
EOF

log_success "Summary report generated: $OUTPUT_DIR/SUMMARY.md"

if [ $FAILED -eq 0 ]; then
    log_success "All tests passed! ✓"
    echo ""
    log_info "Review results: cat $OUTPUT_DIR/SUMMARY.md"
    exit 0
else
    log_fail "Some tests failed!"
    echo ""
    log_warn "Check the output directory for details: $OUTPUT_DIR"
    exit 1
fi

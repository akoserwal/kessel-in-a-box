#!/usr/bin/env bash

# Basic Integration Test
# Tests core SpiceDB functionality with GitHub schema

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Check if zed is installed
if ! command -v zed &>/dev/null; then
    echo "Error: zed CLI not found. Install from: https://github.com/authzed/zed"
    exit 1
fi

# Configure zed
export ZED_ENDPOINT=localhost:50051
export ZED_INSECURE=true

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kessel Integration Tests - Basic Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Test 1: Schema is loaded
test_info "Test 1: Verify schema is loaded"
if zed schema read &>/dev/null; then
    test_pass "Schema is loaded"
else
    test_fail "Schema is not loaded"
fi

# Test 2: Positive permission check - Alice can create repo
test_info "Test 2: Alice (org admin) can create repository"
if zed permission check organization:acmecorp create_repo user:alice 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Alice can create repository (org admin)"
else
    test_fail "Alice should be able to create repository"
fi

# Test 3: Negative permission check - Bob cannot create repo
test_info "Test 3: Bob (member) cannot create repository"
if zed permission check organization:acmecorp create_repo user:bob 2>/dev/null | grep -q "PERMISSION_DENIED"; then
    test_pass "Bob cannot create repository (not admin)"
else
    test_fail "Bob should not be able to create repository"
fi

# Test 4: Team member can read repository
test_info "Test 4: Bob (team member) can read backend repository"
if zed permission check repository:acmecorp/backend read user:bob 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Bob can read backend repository (team write access)"
else
    test_fail "Bob should be able to read backend repository"
fi

# Test 5: Team member can write to repository
test_info "Test 5: Bob (team member) can write to backend repository"
if zed permission check repository:acmecorp/backend write user:bob 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Bob can write to backend repository (team write access)"
else
    test_fail "Bob should be able to write to backend repository"
fi

# Test 6: Team member cannot write to read-only repository
test_info "Test 6: Bob (team member) cannot write to frontend repository"
if zed permission check repository:acmecorp/frontend write user:bob 2>/dev/null | grep -q "PERMISSION_DENIED"; then
    test_pass "Bob cannot write to frontend repository (read-only)"
else
    test_fail "Bob should not be able to write to frontend repository"
fi

# Test 7: Org admin can delete repository
test_info "Test 7: Alice (org admin) can delete repository"
if zed permission check repository:acmecorp/backend delete user:alice 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Alice can delete repository (org admin)"
else
    test_fail "Alice should be able to delete repository"
fi

# Test 8: Regular member cannot delete repository
test_info "Test 8: Bob (member) cannot delete repository"
if zed permission check repository:acmecorp/backend delete user:bob 2>/dev/null | grep -q "PERMISSION_DENIED"; then
    test_pass "Bob cannot delete repository (not admin)"
else
    test_fail "Bob should not be able to delete repository"
fi

# Test 9: Issue author can edit their issue
test_info "Test 9: Bob (issue author) can edit issue"
if zed permission check issue:acmecorp/backend/123 edit user:bob 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Bob can edit issue (author)"
else
    test_fail "Bob should be able to edit issue"
fi

# Test 10: Team member with repo access can edit issue
test_info "Test 10: Charlie (team member) can edit issue"
if zed permission check issue:acmecorp/backend/123 edit user:charlie 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Charlie can edit issue (repo write access)"
else
    test_fail "Charlie should be able to edit issue"
fi

# Test 11: PR reviewer can approve
test_info "Test 11: Bob (reviewer) can approve PR"
if zed permission check pr:acmecorp/backend/456 approve user:bob 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Bob can approve PR (designated reviewer)"
else
    test_fail "Bob should be able to approve PR"
fi

# Test 12: Org admin can merge PR
test_info "Test 12: Alice (org admin) can merge PR"
if zed permission check pr:acmecorp/backend/456 merge user:alice 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "Alice can merge PR (org admin)"
else
    test_fail "Alice should be able to merge PR"
fi

# Test 13: Write new relationship
test_info "Test 13: Create new relationship (add user to org)"
if zed relationship create organization:acmecorp member user:david &>/dev/null; then
    test_pass "Created relationship: david is org member"
else
    test_fail "Failed to create relationship"
fi

# Test 14: Verify new relationship works
test_info "Test 14: David (new member) can view org repos"
if zed permission check organization:acmecorp view_repo user:david 2>/dev/null | grep -q "PERMISSION_GRANTED"; then
    test_pass "David can view org repos (new member)"
else
    test_fail "David should be able to view org repos"
fi

# Test 15: Delete relationship
test_info "Test 15: Delete relationship (remove user from org)"
if zed relationship delete organization:acmecorp member user:david &>/dev/null; then
    test_pass "Deleted relationship: david removed from org"
else
    test_fail "Failed to delete relationship"
fi

# Test 16: Verify deleted relationship
test_info "Test 16: David (removed) cannot view org repos"
if zed permission check organization:acmecorp view_repo user:david 2>/dev/null | grep -q "PERMISSION_DENIED"; then
    test_pass "David cannot view org repos (removed)"
else
    test_fail "David should not be able to view org repos"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Test Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  Passed: ${GREEN}$TESTS_PASSED${NC}"
echo "  Failed: ${RED}$TESTS_FAILED${NC}"
echo "  Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC} ✓"
    exit 0
else
    echo -e "${RED}Some tests failed${NC} ✗"
    exit 1
fi

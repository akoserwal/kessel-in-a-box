# GitHub Clone - Permission Test Scenarios

This document provides test scenarios for the GitHub clone schema.

## Setup

The following data is pre-loaded:
- **Organization**: `acmecorp`
  - Admin: `alice`
  - Members: `bob`, `charlie`
- **Team**: `acmecorp/engineering`
  - Members: `bob`, `charlie`
- **Repositories**:
  - `acmecorp/backend` - engineering team has write access
  - `acmecorp/frontend` - engineering team has read access

## Test Scenarios

### Scenario 1: Organization Admin Permissions

**Test**: Can Alice (org admin) create a repository?

```bash
zed permission check organization:acmecorp create_repo user:alice
# Expected: ✓ PERMISSION_GRANTED
```

**Test**: Can Bob (member) create a repository?

```bash
zed permission check organization:acmecorp create_repo user:bob
# Expected: ✗ PERMISSION_DENIED
```

### Scenario 2: Repository Read Access

**Test**: Can Bob (team member with write) read the backend repo?

```bash
zed permission check repository:acmecorp/backend read user:bob
# Expected: ✓ PERMISSION_GRANTED (via team write access)
```

**Test**: Can Charlie (team member) read the frontend repo?

```bash
zed permission check repository:acmecorp/frontend read user:charlie
# Expected: ✓ PERMISSION_GRANTED (via team read access)
```

**Test**: Can a non-member read the backend repo?

```bash
zed permission check repository:acmecorp/backend read user:stranger
# Expected: ✗ PERMISSION_DENIED
```

### Scenario 3: Repository Write Access

**Test**: Can Bob write to the backend repo?

```bash
zed permission check repository:acmecorp/backend write user:bob
# Expected: ✓ PERMISSION_GRANTED (via team write access)
```

**Test**: Can Bob write to the frontend repo?

```bash
zed permission check repository:acmecorp/frontend write user:bob
# Expected: ✗ PERMISSION_DENIED (only has read access)
```

### Scenario 4: Repository Admin Access

**Test**: Can Alice (repo admin) delete the backend repo?

```bash
zed permission check repository:acmecorp/backend delete user:alice
# Expected: ✓ PERMISSION_GRANTED (repo admin)
```

**Test**: Can Alice (org admin) delete the frontend repo?

```bash
zed permission check repository:acmecorp/frontend delete user:alice
# Expected: ✓ PERMISSION_GRANTED (org admin has delete on all repos)
```

**Test**: Can Bob delete the backend repo?

```bash
zed permission check repository:acmecorp/backend delete user:bob
# Expected: ✗ PERMISSION_DENIED (not a repo admin)
```

### Scenario 5: Issue Permissions

**Test**: Can Bob (issue author) edit issue #123?

```bash
zed permission check issue:acmecorp/backend/123 edit user:bob
# Expected: ✓ PERMISSION_GRANTED (issue author)
```

**Test**: Can Charlie (team member) edit Bob's issue?

```bash
zed permission check issue:acmecorp/backend/123 edit user:charlie
# Expected: ✓ PERMISSION_GRANTED (has write access to repo)
```

**Test**: Can a stranger view the issue?

```bash
zed permission check issue:acmecorp/backend/123 view user:stranger
# Expected: ✗ PERMISSION_DENIED (no repo access)
```

### Scenario 6: Pull Request Permissions

**Test**: Can Bob (reviewer) approve PR #456?

```bash
zed permission check pr:acmecorp/backend/456 approve user:bob
# Expected: ✓ PERMISSION_GRANTED (designated reviewer)
```

**Test**: Can Alice (org admin) merge PR #456?

```bash
zed permission check pr:acmecorp/backend/456 merge user:alice
# Expected: ✓ PERMISSION_GRANTED (org admin can write to repo)
```

**Test**: Can anyone with read access comment on the PR?

```bash
zed permission check pr:acmecorp/backend/456 comment user:bob
# Expected: ✓ PERMISSION_GRANTED (has read access)
```

## Bulk Check Example

Test multiple permissions at once:

```bash
# Create a test script
cat > /tmp/test-permissions.sh << 'EOF'
#!/bin/bash

CHECKS=(
  "organization:acmecorp create_repo user:alice"
  "repository:acmecorp/backend read user:bob"
  "repository:acmecorp/backend write user:bob"
  "repository:acmecorp/frontend write user:bob"
  "issue:acmecorp/backend/123 edit user:bob"
)

for check in "${CHECKS[@]}"; do
  echo "Testing: $check"
  zed permission check $check
  echo
done
EOF

chmod +x /tmp/test-permissions.sh
/tmp/test-permissions.sh
```

## Expected Results Summary

| User | Resource | Permission | Result | Reason |
|------|----------|------------|--------|--------|
| alice | organization:acmecorp | create_repo | ✓ | Org admin |
| bob | organization:acmecorp | create_repo | ✗ | Not admin |
| bob | repository:acmecorp/backend | read | ✓ | Team write access |
| bob | repository:acmecorp/backend | write | ✓ | Team write access |
| bob | repository:acmecorp/frontend | read | ✓ | Team read access |
| bob | repository:acmecorp/frontend | write | ✗ | Only read access |
| alice | repository:acmecorp/backend | delete | ✓ | Repo admin |
| bob | repository:acmecorp/backend | delete | ✗ | Not repo admin |
| bob | issue:acmecorp/backend/123 | edit | ✓ | Issue author |
| charlie | issue:acmecorp/backend/123 | edit | ✓ | Has repo write |
| bob | pr:acmecorp/backend/456 | approve | ✓ | Designated reviewer |
| alice | pr:acmecorp/backend/456 | merge | ✓ | Org admin (repo write) |

## Performance Benchmarks

Run performance tests:

```bash
# Single check latency
time zed permission check repository:acmecorp/backend read user:bob

# Bulk check throughput
./scripts/benchmark.sh --schema github-clone --checks 1000
```

Expected performance (local development):
- **p50 latency**: 2-5ms
- **p99 latency**: 10-20ms
- **Throughput**: 500-1000 checks/second

## Troubleshooting

If tests fail:

1. **Verify schema is loaded**:
   ```bash
   zed schema read
   ```

2. **Verify relationships exist**:
   ```bash
   zed relationship read organization:acmecorp admin
   ```

3. **Check SpiceDB logs**:
   ```bash
   docker logs kessel-spicedb --tail 100
   ```

4. **Reload sample data**:
   ```bash
   ./scripts/load-sample-data.sh
   ```

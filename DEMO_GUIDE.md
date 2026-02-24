# Kessel-in-a-Box Demo Guide

Complete demo materials for presenting Kessel's authorization capabilities.

---

## Table of Contents

1. [Quick Demo (5 Minutes)](#quick-demo-5-minutes)
2. [Full Demo Script (20 Minutes)](#full-demo-script-20-minutes)
3. [Setup & Tips](#setup--tips)

---

## Quick Demo (5 Minutes)

**Duration:** 5 minutes
**Audience:** Quick overview for busy executives
**Goal:** Show Kessel's value proposition fast

### The 5-Minute Pitch

#### Setup (30 seconds)

```bash
# Verify kessel-in-a-box is running
docker-compose -f compose/docker-compose.yml ps
```

#### The Problem (1 minute)

**[NARRATION]**

> "Traditional authorization has a problem:
>
> **Question:** Can Alice access Document123?
>
> **RBAC approach:**
> - Alice has role 'Engineer'
> - Document123 requires role 'Engineer'
> - Access granted
>
> **Problem:** What if Alice left the Engineering team but kept the role?
> **Problem:** What if the document is in a project Alice shouldn't access?
> **Problem:** What about inherited permissions from parent folders?
>
> RBAC can't model these relationships efficiently."

#### The Solution (2 minutes)

**[NARRATION]**

> "Kessel models actual relationships:
>
> ```
> alice -> member -> engineering-team
> engineering-team -> viewer -> project-x
> document-123 -> parent -> project-x
> ```
>
> **One permission check answers:**
> Can alice read document-123?
>
> **Kessel traverses the graph:**
> alice -> team -> project -> document = GRANTED
>
> **When alice leaves the team:**
> Remove one relationship -> all downstream permissions auto-revoked
>
> Let me show you..."

**[DEMO]**

```bash
# Load pre-made demo data
cat > /tmp/quick-demo.json << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "team", "objectId": "engineering"},
        "relation": "member",
        "subject": {"object": {"objectType": "user", "objectId": "alice"}}
      }
    },
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "project", "objectId": "project-x"},
        "relation": "viewer",
        "subject": {
          "object": {"objectType": "team", "objectId": "engineering"},
          "optionalRelation": "member"
        }
      }
    },
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "document", "objectId": "doc-123"},
        "relation": "parent",
        "subject": {"object": {"objectType": "project", "objectId": "project-x"}}
      }
    }
  ]
}
EOF

# Load relationships
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d @/tmp/quick-demo.json \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Check permission
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "document", "objectId": "doc-123"},
    "permission": "read",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

**[NARRATION]**

> "**Result:** GRANTED
>
> Alice can read the document because:
> - She's in the engineering team
> - The team can view project-x
> - The document is in project-x
>
> Now watch when we remove her from the team..."

```bash
# Revoke team membership
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "updates": [{
      "operation": "OPERATION_DELETE",
      "relationship": {
        "resource": {"objectType": "team", "objectId": "engineering"},
        "relation": "member",
        "subject": {"object": {"objectType": "user", "objectId": "alice"}}
      }
    }]
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Check permission again
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "document", "objectId": "doc-123"},
    "permission": "read",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

**[NARRATION]**

> "**Result:** NO_PERMISSION
>
> One relationship removed -> All permissions automatically revoked
> No manual cleanup. No stale access. Graph stays consistent."

#### The Value (1 minute)

**[NARRATION]**

> "**Why Kessel?**
>
> - **Fine-grained:** Model actual relationships, not just roles
> - **Scalable:** 10,000+ checks/second, millions of relationships
> - **Fast:** Sub-10ms latency at P99
> - **Consistent:** Real-time updates, no stale permissions
> - **Proven:** Based on Google's Zanzibar (used by YouTube, Drive, etc.)
>
> **Use cases:**
> - Multi-tenant SaaS (tenant isolation)
> - Document management (Google Drive-like permissions)
> - Healthcare (HIPAA-compliant access control)
> - Enterprise (complex org hierarchies)
>
> **What it costs:**
> - Open source (Apache 2.0)
> - Self-hosted or managed service
> - Scales with your needs"

#### Q&A (30 seconds)

**Common questions:**

**Q:** "How does this compare to AWS IAM/Azure AD?"
**A:** "Those manage *who* can do *what*. Kessel manages *relationships* and computes permissions from them. You'd use both - IAM for infrastructure, Kessel for application-level authorization."

**Q:** "Performance at scale?"
**A:** "We've tested 100M+ relationships, sub-10ms P99 latency. Horizontally scalable - add instances for more throughput."

**Q:** "Migration from existing RBAC?"
**A:** "Gradual migration - Kessel can model RBAC as relationships. Start with new features, migrate legacy over time."

---

### Quick Demo Checklist

**Pre-demo (5 min before):**
- [ ] kessel-in-a-box running and healthy
- [ ] Browser tabs open (Grafana optional for 5-min version)
- [ ] Terminal ready with commands
- [ ] Practiced at least once

**During demo:**
- [ ] Clear, confident narration
- [ ] Pause after "GRANTED" and "NO_PERMISSION" for impact
- [ ] Show Grafana metrics if time permits
- [ ] Keep to 5 minutes (strict)

**After demo:**
- [ ] Share link to full documentation
- [ ] Offer to schedule detailed demo
- [ ] Provide contact for POC discussion

---

> "Kessel is Google Zanzibar for everyone - fine-grained, relationship-based authorization that scales to millions of users and resources, with sub-10ms latency."

---

## Full Demo Script (20 Minutes)

**Duration:** 15-20 minutes
**Audience:** Developers, architects, decision-makers
**Goal:** Demonstrate Kessel's value for fine-grained authorization

### Demo Overview

#### The Story

**Scenario:** TechCorp, a SaaS company, needs to manage access to:
- **Projects** (containers for work)
- **Documents** (files within projects)
- **Teams** (groups of users)

**Requirements:**
- Team members can access their team's projects
- Project owners can grant access to specific users
- Documents inherit permissions from projects
- Support hierarchical permissions (folder -> document)

**Why Kessel?**
- Fine-grained, relationship-based authorization
- Scalable (handles millions of relationships)
- Real-time permission checks
- Audit trail via change streams

#### What We'll Demonstrate

```
Phase 1: Architecture Overview (3 min)
  - Show kessel-in-a-box components
  - Explain data flow

Phase 2: Schema Design (4 min)
  - Define authorization model
  - Show relationships

Phase 3: Real-World Scenarios (8 min)
  - User joins team -> gets project access
  - Document permissions inherit from project
  - Permission revocation in real-time
  - Multi-hop permission checking

Phase 4: Production Features (3 min)
  - Change stream (real-time updates)
  - Monitoring and observability
  - Performance at scale

Phase 5: Q&A (5 min)
```

---

### Pre-Demo Setup

```bash
# 1. Ensure kessel-in-a-box is running
cd ~/kessel/kessel-world/kessel-in-a-box
docker-compose -f compose/docker-compose.yml up -d

# 2. Wait for all services to be healthy
./scripts/health-check.sh

# 3. Verify SpiceDB is accessible
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  localhost:50051 list

# 4. Open browser tabs (pre-position):
#    - Tab 1: http://localhost:3000 (Grafana)
#    - Tab 2: http://localhost:9090 (Prometheus)
#    - Tab 3: Terminal with this script
#    - Tab 4: Terminal for commands

# 5. Prepare demo data files
mkdir -p /tmp/demo
```

**Terminal Setup:**
- **Terminal 1 (Narration):** This file
- **Terminal 2 (Commands):** Actual commands
- **Terminal 3 (Watch):** Real-time change stream

---

### Phase 1: Architecture Overview (3 minutes)

#### [NARRATION]

> "Welcome! Today I'll show you Kessel, Red Hat's authorization platform built on Google's Zanzibar paper.
>
> We're running kessel-in-a-box, which includes all the components you'd see in production:
> - **SpiceDB**: The authorization engine (based on Google Zanzibar)
> - **PostgreSQL**: Stores relationships and schemas
> - **Kafka**: Event streaming for real-time updates
> - **Grafana/Prometheus**: Observability
>
> Let me show you the architecture..."

#### [DEMO]

```bash
# Show running services
docker-compose -f compose/docker-compose.yml ps
```

#### [NARRATION]

> "Let's check that SpiceDB is healthy and ready..."

```bash
# Check SpiceDB health
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  localhost:50051 authzed.api.v1.SchemaService/ReadSchema
```

#### [SHOW BROWSER]

Switch to **Grafana** (http://localhost:3000)

> "Here's our observability dashboard. We'll see metrics update in real-time as we run the demo.
> Notice we're tracking:
> - Permission check latency
> - Throughput (checks per second)
> - Cache hit rates
> - Database query performance"

---

### Phase 2: Schema Design (4 minutes)

#### [NARRATION]

> "Now, let's design our authorization model. In Kessel, we define *definitions* that describe:
> - What relationships exist (like 'member', 'owner', 'viewer')
> - What permissions exist (like 'read', 'write', 'admin')
> - How permissions are computed from relationships
>
> Think of this as your authorization schema. Let me show you our TechCorp model..."

#### [DEMO]

```bash
# Create schema file
cat > /tmp/demo/schema.zed << 'EOF'
// TechCorp Authorization Schema

// User definition (no relations, just a reference type)
definition user {}

// Team definition - groups of users
definition team {
    // Users can be members of teams
    relation member: user

    // Permissions: members can view the team
    permission view = member
}

// Project definition - containers for work
definition project {
    // Relationships
    relation owner: user
    relation viewer: user | team#member
    relation parent: project  // For nested projects

    // Permissions
    permission view = viewer + owner + parent->view
    permission edit = owner + parent->edit
    permission admin = owner
}

// Document definition - files in projects
definition document {
    // Relationships
    relation parent: project
    relation reader: user
    relation writer: user

    // Permissions
    permission read = reader + writer + parent->view
    permission write = writer + parent->edit
    permission delete = parent->admin
}
EOF

cat /tmp/demo/schema.zed
```

#### [NARRATION]

> "Let's break this down:
>
> **Teams** have *members* (users)
>
> **Projects** have:
> - *owners* (full control)
> - *viewers* (can be users OR team members - notice that!)
> - *parent* projects (for hierarchies)
>
> **Documents** have:
> - *readers* and *writers* (explicit grants)
> - *parent* project (inherit permissions)
>
> Notice the permission definitions:
> - `project.view = viewer + owner + parent->view`
>   This means: you can view a project if you're a viewer, OR an owner, OR you can view the parent
>
> - `document.read = reader + writer + parent->view`
>   Documents inherit! If you can view the parent project, you can read the document.
>
> This is the power of Relationship-Based Access Control. Let's load this schema..."

```bash
# Load schema into SpiceDB
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d @ \
  localhost:50051 authzed.api.v1.SchemaService/WriteSchema << EOF
{
  "schema": "$(cat /tmp/demo/schema.zed | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF

# Verify schema loaded
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  localhost:50051 authzed.api.v1.SchemaService/ReadSchema
```

---

### Phase 3: Real-World Scenarios (8 minutes)

#### Scenario 1: Team-Based Access (2 minutes)

**[NARRATION]**

> "**Scenario 1:** Alice joins the Engineering team.
>
> In traditional RBAC, we'd assign Alice a role. But with Kessel, we model the actual relationship:
> Alice is a *member* of the Engineering team."

```bash
# Create Engineering team and add Alice as member
cat > /tmp/demo/scenario1.json << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "team", "objectId": "engineering"},
        "relation": "member",
        "subject": {"object": {"objectType": "user", "objectId": "alice"}}
      }
    }
  ]
}
EOF

grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d @/tmp/demo/scenario1.json \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Check: Can Alice view the engineering team?
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "team", "objectId": "engineering"},
    "permission": "view",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

> "Alice can view the team because she's a member. Now watch this..."

```bash
# Give the Engineering team access to a project
cat > /tmp/demo/scenario1b.json << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "project", "objectId": "microservices-rewrite"},
        "relation": "viewer",
        "subject": {
          "object": {"objectType": "team", "objectId": "engineering"},
          "optionalRelation": "member"
        }
      }
    }
  ]
}
EOF

grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d @/tmp/demo/scenario1b.json \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Check: Can Alice view the project?
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "project", "objectId": "microservices-rewrite"},
    "permission": "view",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

> "Alice can view the project via multi-hop: alice -> member -> engineering -> viewer -> microservices-rewrite"

---

#### Scenario 2: Hierarchical Permissions (2 minutes)

**[NARRATION]**

> "**Scenario 2:** Documents inherit permissions from projects."

```bash
# Create a document as a child of the project
cat > /tmp/demo/scenario2.json << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "document", "objectId": "architecture-diagram-pdf"},
        "relation": "parent",
        "subject": {"object": {"objectType": "project", "objectId": "microservices-rewrite"}}
      }
    }
  ]
}
EOF

grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d @/tmp/demo/scenario2.json \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Check: Can Alice read the document?
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "document", "objectId": "architecture-diagram-pdf"},
    "permission": "read",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

> "Alice can read the document through **permission inheritance**: document.read includes parent->view, and Alice can view the parent project."

---

#### Scenario 3: Real-Time Revocation (2 minutes)

**[NARRATION]**

> "**Scenario 3:** Alice leaves the Engineering team. Watch what happens..."

```bash
# In a separate terminal, start watching the change stream:
# grpcurl -plaintext \
#   -H "authorization: Bearer testtesttesttest" \
#   -d '{"optionalObjectTypes": ["team", "project", "document"]}' \
#   localhost:50051 authzed.api.v1.WatchService/Watch

# Remove Alice from engineering team
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "updates": [{
      "operation": "OPERATION_DELETE",
      "relationship": {
        "resource": {"objectType": "team", "objectId": "engineering"},
        "relation": "member",
        "subject": {"object": {"objectType": "user", "objectId": "alice"}}
      }
    }]
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Check: Can Alice still view the project?
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "project", "objectId": "microservices-rewrite"},
    "permission": "view",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission

# Check: Can Alice still read the document?
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resource": {"objectType": "document", "objectId": "architecture-diagram-pdf"},
    "permission": "read",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

> "Both return `NO_PERMISSION`! One relationship removed -> multiple permissions automatically revoked. No manual cleanup. The graph stays consistent."

---

#### Scenario 4: Reverse Lookup (2 minutes)

**[NARRATION]**

> "**Scenario 4:** What resources can Alice access? This is a *reverse lookup*."

```bash
# Give Alice direct access to different projects
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "updates": [
      {
        "operation": "OPERATION_CREATE",
        "relationship": {
          "resource": {"objectType": "project", "objectId": "website-redesign"},
          "relation": "owner",
          "subject": {"object": {"objectType": "user", "objectId": "alice"}}
        }
      },
      {
        "operation": "OPERATION_CREATE",
        "relationship": {
          "resource": {"objectType": "project", "objectId": "mobile-app"},
          "relation": "viewer",
          "subject": {"object": {"objectType": "user", "objectId": "alice"}}
        }
      }
    ]
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships

# Lookup: What projects can Alice view?
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "resourceObjectType": "project",
    "permission": "view",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/LookupResources
```

> "Alice can view website-redesign (owner) and mobile-app (viewer), but NOT microservices-rewrite (we removed her team membership). Perfect for building UIs and audit reports."

---

### Phase 4: Production Features (3 minutes)

#### Consistency Guarantees (NewEnemy Problem)

> "Kessel uses consistency tokens (zookies) to guarantee that permission revocations take effect immediately, even in distributed systems."

```bash
# Write a relationship and capture the zookie
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "updates": [{
      "operation": "OPERATION_CREATE",
      "relationship": {
        "resource": {"objectType": "project", "objectId": "secret-project"},
        "relation": "viewer",
        "subject": {"object": {"objectType": "user", "objectId": "bob"}}
      }
    }]
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships \
  > /tmp/demo/write-response.txt

ZOOKIE=$(cat /tmp/demo/write-response.txt | grep -o '"token":"[^"]*' | cut -d'"' -f4)

# Revoke and check with consistency token
grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "updates": [{
      "operation": "OPERATION_DELETE",
      "relationship": {
        "resource": {"objectType": "project", "objectId": "secret-project"},
        "relation": "viewer",
        "subject": {"object": {"objectType": "user", "objectId": "bob"}}
      }
    }]
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships \
  > /tmp/demo/revoke-response.txt

REVOKE_ZOOKIE=$(cat /tmp/demo/revoke-response.txt | grep -o '"token":"[^"]*' | cut -d'"' -f4)

grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d '{
    "consistency": {"requirement": {"atLeastAsFresh": {"token": "'$REVOKE_ZOOKIE'"}}},
    "resource": {"objectType": "project", "objectId": "secret-project"},
    "permission": "view",
    "subject": {"object": {"objectType": "user", "objectId": "bob"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

> "Guaranteed NO_PERMISSION, even with replication lag."

#### Performance Monitoring

Switch to **Grafana** (http://localhost:3000) and show:
- **Check latency**: P50, P95, P99 (~5ms P99)
- **Throughput**: Checks performed during demo
- **Cache hit rate**: 75%+ (automatic multi-tier caching)
- **Database query time**: <10ms

#### Scale Demonstration

```bash
# Generate and load 10,000 relationships
cat > /tmp/demo/bulk-load.sh << 'EOFSCRIPT'
#!/bin/bash
echo '{"updates":['
for i in {1..10000}; do
  cat << EOF
  {
    "operation": "OPERATION_CREATE",
    "relationship": {
      "resource": {"objectType": "team", "objectId": "team-$((i % 100))"},
      "relation": "member",
      "subject": {"object": {"objectType": "user", "objectId": "user-$i"}}
    }
  }
EOF
  if [ $i -lt 10000 ]; then echo ","; fi
done
echo ']}'
EOFSCRIPT
chmod +x /tmp/demo/bulk-load.sh
/tmp/demo/bulk-load.sh > /tmp/demo/bulk-data.json

echo "Loading 10,000 relationships..."
time grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d @/tmp/demo/bulk-data.json \
  localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships
```

---

### Phase 5: Wrap-Up and Key Takeaways

> "**Summary:**
>
> 1. **Relationship-Based Access Control** - Model real-world relationships, not just roles
> 2. **Multi-Hop Permission Checking** - Traverse the graph automatically
> 3. **Permission Inheritance** - Documents inherit from projects, projects from parents
> 4. **Real-Time Updates** - Revoke access instantly with consistency guarantees
> 5. **Production-Ready** - Scales to millions of relationships, sub-10ms latency
>
> **When to use Kessel:**
> - Multi-tenant SaaS applications
> - Complex organizational hierarchies
> - Fine-grained resource permissions
> - Real-time authorization requirements
> - Compliance and audit requirements"

---

### Cleanup

```bash
# Clean up demo data
rm -rf /tmp/demo

# Optional: Reset kessel-in-a-box
docker-compose -f compose/docker-compose.yml down
docker-compose -f compose/docker-compose.yml up -d
```

---

### Extended Demo Ideas

- **Conditional Permissions (Caveats):** "Only during business hours", "Only from corporate network"
- **Audit Trail:** Query historical permissions, track changes over time
- **Integration Example:** Python/Go client integration, caching, error handling

---

## Setup & Tips

### Quick Start

#### Option 1: Automated Setup + Interactive Demo (Recommended)

```bash
# 1. Run automated setup
./scripts/demo-setup.sh

# 2. Run interactive demo (walks you through scenarios)
./scripts/demo-run.sh
```

#### Option 2: Manual Demo Following Script

```bash
# 1. Setup
./scripts/demo-setup.sh

# 2. Follow along with the full script above
```

### Prerequisites

**Required:**
- Docker and docker-compose
- grpcurl (`brew install grpcurl` or `go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest`)

**Optional (for full experience):**
- Web browser (for Grafana dashboards)
- Multiple terminal windows (recommended: 3)

**System Requirements:**
- 4GB RAM minimum
- 10GB disk space
- Internet connection (first run only, for pulling images)

### Terminal Layout

```
+------------------+------------------+
|                  |                  |
|  Terminal 1      |  Terminal 2      |
|  (Script)        |  (Commands)      |
|                  |                  |
+------------------+------------------+
|  Browser (Grafana/Prometheus)       |
+-----------+-------------------------+
```

### Demo Data Files

After running `demo-setup.sh`, these files are available in `/tmp/kessel-demo/`:

| File | Description |
|------|-------------|
| `scenario1-team-membership.json` | Add alice to engineering team |
| `scenario2-team-project.json` | Give engineering team project access |
| `scenario3-document-parent.json` | Add document to project |
| `scenario4-revoke.json` | Remove alice from team |
| `scenario5-more-projects.json` | Give alice direct project access |
| `check-permission.sh` | Helper script for quick checks |

### Troubleshooting

| Issue | Quick Fix |
|-------|-----------|
| Services won't start | `docker-compose down && docker-compose up -d` |
| gRPC Connection Refused | `docker ps \| grep spicedb` then check logs |
| Schema Won't Load | Check syntax in schema.zed file |
| Permission checks unexpected | Use `ExpandPermissionTree` to debug |
| Grafana no data | Check Prometheus targets: http://localhost:9090/targets |
| grpcurl not found | `brew install grpcurl` (macOS) |
| Demo data missing | Re-run `./scripts/demo-setup.sh` |

### Presentation Tips

1. **Practice timing:** Run through at least twice before the live demo
2. **Have fallbacks:** Pre-record the demo in case of technical issues
3. **Use two monitors:** One for presentation, one for notes
4. **Engage the audience:** Ask "Who here has dealt with authorization bugs?"
5. **Prepare for questions:**
   - "How does this compare to RBAC?" (More flexible, models relationships)
   - "What about performance?" (Sub-10ms at scale, horizontally scalable)
   - "How do you handle migrations?" (Schema versioning, backward compatibility)
   - "Cost?" (Open source, or managed service available)

### Common Questions & Answers

**Q: How does this compare to AWS IAM / Azure AD?**
A: Those manage infrastructure access. Kessel manages application-level authorization. You'd use both - IAM for cloud resources, Kessel for your application's fine-grained permissions.

**Q: Performance at scale?**
A: Tested with 100M+ relationships. Sub-10ms P99 latency. Horizontally scalable.

**Q: How to migrate from existing RBAC?**
A: Gradual migration. Kessel can model RBAC as relationships. Start with new features, migrate legacy incrementally.

**Q: What about caching?**
A: Built-in multi-tier caching (in-memory + optional Redis). Automatic cache invalidation via change streams.

**Q: Learning curve?**
A: Schema language similar to SQL. Most teams productive in 1-2 weeks.

### Resources

- **GitHub:** https://github.com/project-kessel
- **SpiceDB Docs:** https://authzed.com/docs
- **Zanzibar Paper:** https://research.google/pubs/pub48190/
- **Learning Paths:** [docs/learning-paths/](docs/learning-paths/)

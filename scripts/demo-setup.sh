#!/bin/bash
#
# Demo Setup Script
# Prepares kessel-in-a-box for demo presentation using the stage schema
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Kessel-in-a-Box Demo Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker not found. Please install Docker.${NC}"
    exit 1
fi
echo -e "${GREEN}  Docker installed${NC}"

if ! command -v grpcurl &> /dev/null; then
    echo -e "${RED}Error: grpcurl not found. Please install grpcurl:${NC}"
    echo "  brew install grpcurl  # macOS"
    echo "  go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"
    exit 1
fi
echo -e "${GREEN}  grpcurl installed${NC}"

if ! command -v zed &> /dev/null; then
    echo -e "${RED}Error: zed not found. Please install zed:${NC}"
    echo "  brew install authzed/tap/zed  # macOS"
    exit 1
fi
echo -e "${GREEN}  zed CLI installed${NC}"
echo ""

SPICEDB_ENDPOINT="localhost:50051"
AUTH_TOKEN="testtesttesttest"

# Check SpiceDB is running
echo -e "${YELLOW}Checking SpiceDB...${NC}"
if ! grpcurl -plaintext -H "authorization: Bearer $AUTH_TOKEN" \
    "$SPICEDB_ENDPOINT" list &>/dev/null; then
    echo -e "${RED}Error: SpiceDB not reachable at $SPICEDB_ENDPOINT${NC}"
    echo "Start services: cd compose && docker compose up -d"
    exit 1
fi
echo -e "${GREEN}  SpiceDB is running${NC}"

# Verify stage schema is loaded
SCHEMA_DEFS=$(zed --endpoint "$SPICEDB_ENDPOINT" --token "$AUTH_TOKEN" --insecure \
    schema read 2>/dev/null | grep "^definition " | wc -l | tr -d ' ')

if [ "$SCHEMA_DEFS" -lt 8 ]; then
    echo -e "${YELLOW}  Stage schema not loaded, loading now...${NC}"
    zed --endpoint "$SPICEDB_ENDPOINT" --token "$AUTH_TOKEN" --insecure \
        schema write "$PROJECT_ROOT/services/spicedb/schema/schema.zed" 2>/dev/null
fi
echo -e "${GREEN}  Stage schema loaded ($SCHEMA_DEFS definitions)${NC}"
echo ""

# Create demo directory
DEMO_DIR="/tmp/kessel-demo"
mkdir -p "$DEMO_DIR"

echo -e "${YELLOW}Generating demo data files...${NC}"

# Scenario 1: Team membership (group + principal)
cat > "$DEMO_DIR/scenario1-team-membership.json" << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/group", "objectId": "engineering"},
        "relation": "t_member",
        "subject": {"object": {"objectType": "rbac/principal", "objectId": "alice"}}
      }
    }
  ]
}
EOF

# Scenario 2: Create role + role binding + workspace
cat > "$DEMO_DIR/scenario2-workspace-access.json" << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/role", "objectId": "host_viewer"},
        "relation": "t_inventory_hosts_read",
        "subject": {"object": {"objectType": "rbac/principal", "objectId": "*"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/role_binding", "objectId": "eng_prod_binding"},
        "relation": "t_subject",
        "subject": {
          "object": {"objectType": "rbac/group", "objectId": "engineering"},
          "optionalRelation": "member"
        }
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/role_binding", "objectId": "eng_prod_binding"},
        "relation": "t_role",
        "subject": {"object": {"objectType": "rbac/role", "objectId": "host_viewer"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/tenant", "objectId": "techcorp"},
        "relation": "t_platform",
        "subject": {"object": {"objectType": "rbac/platform", "objectId": "techcorp_defaults"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/workspace", "objectId": "production"},
        "relation": "t_parent",
        "subject": {"object": {"objectType": "rbac/tenant", "objectId": "techcorp"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/workspace", "objectId": "production"},
        "relation": "t_binding",
        "subject": {"object": {"objectType": "rbac/role_binding", "objectId": "eng_prod_binding"}}
      }
    }
  ]
}
EOF

# Scenario 3: Host in workspace (inheritance)
cat > "$DEMO_DIR/scenario3-host-access.json" << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "hbi/host", "objectId": "web-server-01"},
        "relation": "t_workspace",
        "subject": {"object": {"objectType": "rbac/workspace", "objectId": "production"}}
      }
    }
  ]
}
EOF

# Scenario 4: Revocation (remove from group)
cat > "$DEMO_DIR/scenario4-revoke.json" << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_DELETE",
      "relationship": {
        "resource": {"objectType": "rbac/group", "objectId": "engineering"},
        "relation": "t_member",
        "subject": {"object": {"objectType": "rbac/principal", "objectId": "alice"}}
      }
    }
  ]
}
EOF

# Scenario 5: Direct binding for alice
cat > "$DEMO_DIR/scenario5-direct-binding.json" << 'EOF'
{
  "updates": [
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/workspace", "objectId": "staging"},
        "relation": "t_parent",
        "subject": {"object": {"objectType": "rbac/tenant", "objectId": "techcorp"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/role_binding", "objectId": "alice_staging_binding"},
        "relation": "t_subject",
        "subject": {"object": {"objectType": "rbac/principal", "objectId": "alice"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/role_binding", "objectId": "alice_staging_binding"},
        "relation": "t_role",
        "subject": {"object": {"objectType": "rbac/role", "objectId": "host_viewer"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "rbac/workspace", "objectId": "staging"},
        "relation": "t_binding",
        "subject": {"object": {"objectType": "rbac/role_binding", "objectId": "alice_staging_binding"}}
      }
    },
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "hbi/host", "objectId": "staging-app-01"},
        "relation": "t_workspace",
        "subject": {"object": {"objectType": "rbac/workspace", "objectId": "staging"}}
      }
    }
  ]
}
EOF

echo -e "${GREEN}  Demo data files created${NC}"
echo ""

# Create helper script
cat > "$DEMO_DIR/check-permission.sh" << 'EOFSCRIPT'
#!/bin/bash
# Quick permission check helper for stage schema
# Usage: check-permission.sh <principal> <permission> <resource_type:resource_id>
# Example: check-permission.sh alice view hbi/host:web-server-01

if [ $# -ne 3 ]; then
    echo "Usage: $0 <principal> <permission> <resource_type:resource_id>"
    echo "Example: $0 alice view hbi/host:web-server-01"
    echo "Example: $0 alice inventory_host_view rbac/workspace:production"
    exit 1
fi

PRINCIPAL=$1
PERMISSION=$2
RESOURCE=$3

RESOURCE_TYPE=$(echo "$RESOURCE" | rev | cut -d: -f2- | rev)
RESOURCE_ID=$(echo "$RESOURCE" | rev | cut -d: -f1 | rev)

grpcurl -plaintext \
  -H "authorization: Bearer testtesttesttest" \
  -d "{
    \"resource\": {\"objectType\": \"$RESOURCE_TYPE\", \"objectId\": \"$RESOURCE_ID\"},
    \"permission\": \"$PERMISSION\",
    \"subject\": {\"object\": {\"objectType\": \"rbac/principal\", \"objectId\": \"$PRINCIPAL\"}},
    \"consistency\": {\"fullyConsistent\": true}
  }" \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('permissionship','UNKNOWN'))" 2>/dev/null || \
  echo "ERROR: Could not check permission"
EOFSCRIPT

chmod +x "$DEMO_DIR/check-permission.sh"

echo -e "${GREEN}  Helper scripts created${NC}"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Demo Ready!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}  kessel-in-a-box is running${NC}"
echo -e "${GREEN}  Stage schema loaded (rbac-config)${NC}"
echo -e "${GREEN}  Demo data files ready${NC}"
echo ""
echo -e "${YELLOW}Demo Resources:${NC}"
echo "  Demo directory:  $DEMO_DIR"
echo "  Demo script:     $PROJECT_ROOT/scripts/demo-run.sh"
echo "  Demo guide:      $PROJECT_ROOT/DEMO_GUIDE.md"
echo ""
echo -e "${YELLOW}Quick Test:${NC}"
echo "  $DEMO_DIR/check-permission.sh alice view hbi/host:web-server-01"
echo ""
echo -e "${YELLOW}Run Demo:${NC}"
echo "  $PROJECT_ROOT/scripts/demo-run.sh"
echo ""

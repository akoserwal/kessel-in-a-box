#!/usr/bin/env bash

# Insights Services Setup Script
# Sets up Red Hat Insights services integration with Kessel

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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setting up Insights Services Integration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v zed &> /dev/null; then
    log_error "zed CLI not found. Please install from: https://github.com/authzed/zed"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "docker not found. Please install Docker."
    exit 1
fi

log_success "Prerequisites check passed"

# Check if services are running
log_info "Checking if required services are running..."

required_services=("kessel-spicedb" "kessel-postgres" "kessel-redis" "kessel-kafka")
all_running=true

for service in "${required_services[@]}"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        log_error "Service not running: $service"
        all_running=false
    fi
done

if [[ "$all_running" == false ]]; then
    log_error "Not all required services are running."
    echo
    echo "Please start all phases first:"
    echo "  docker-compose \\"
    echo "    -f compose/docker-compose.yml \\"
    echo "    -f compose/docker-compose.kafka.yml \\"
    echo "    -f compose/docker-compose.redis.yml \\"
    echo "    -f compose/docker-compose.observability.yml \\"
    echo "    -f compose/docker-compose.insights.yml \\"
    echo "    up -d"
    exit 1
fi

log_success "All required services are running"

# Wait for SpiceDB to be ready
log_info "Waiting for SpiceDB to be ready..."
max_attempts=30
attempt=0

while ! zed --endpoint localhost:50051 --insecure --token testtesttesttest version &>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
        log_error "SpiceDB not ready after $max_attempts attempts"
        exit 1
    fi
    sleep 2
done

log_success "SpiceDB is ready"

# Check if Insights services are running
log_info "Checking Insights services..."

insights_services=("kessel-insights-rbac" "kessel-insights-inventory" "kessel-relations-api")
for service in "${insights_services[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        log_success "  $service is running"
    else
        log_warn "  $service is not running (will skip integration tests)"
    fi
done

# Run migrations
log_info "Running migration scripts..."

echo
echo "━━━ Running RBAC Migration ━━━"
"${SCRIPT_DIR}/insights-migration/migrate-rbac-to-kessel.sh" || {
    log_error "RBAC migration failed"
    exit 1
}

echo
echo "━━━ Running Inventory Migration ━━━"
"${SCRIPT_DIR}/insights-migration/migrate-inventory-to-kessel.sh" || {
    log_error "Inventory migration failed"
    exit 1
}

log_success "All migrations completed successfully"

# Set up integration examples
log_info "Setting up integration examples..."

if [[ -d "${PROJECT_ROOT}/sample-data/insights-examples" ]]; then
    cd "${PROJECT_ROOT}/sample-data/insights-examples"

    if [[ ! -d "node_modules" ]]; then
        log_info "Installing Node.js dependencies..."
        if command -v npm &> /dev/null; then
            npm install &>/dev/null
            log_success "Dependencies installed"
        else
            log_warn "npm not found. Skipping dependency installation."
            log_warn "To run examples, install Node.js and run: cd sample-data/insights-examples && npm install"
        fi
    else
        log_success "Dependencies already installed"
    fi

    cd "$PROJECT_ROOT"
fi

# Display status
log_info "Gathering service status..."

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Insights Services setup complete!"
echo
echo "Service Status:"

# Check each service
check_service() {
    local name=$1
    local port=$2
    local endpoint=$3

    if curl -sf "http://localhost:${port}${endpoint}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name (http://localhost:$port)"
    else
        echo -e "  ${RED}✗${NC} $name (http://localhost:$port) - Not responding"
    fi
}

check_service "Insights RBAC" "8080" "/api/rbac/v1/status/"
check_service "Insights Inventory" "8081" "/health"
check_service "Kessel Relations API" "8082" "/health"
check_service "Kessel Inventory API" "8083" "/health"
check_service "Principal Proxy" "8090" "/health"

echo
echo "Migrated Resources:"
echo "  Organizations: 2 (acme-corp, partner-corp)"
echo "  Groups: 5 (org-admins, sre-team, developers, qa-team, external-users)"
echo "  Workspaces: 3 (production, staging, development)"
echo "  Applications: 3 (advisor, vulnerability, patch)"
echo "  Hosts: 3 (web-01, web-02, db-01)"
echo "  Host Groups: 3 (web-servers, databases, cache-servers)"
echo "  Tags: 3 (production, staging, engineering)"
echo
echo "Sample Users:"
echo "  alice   - Organization Admin (full access)"
echo "  bob     - Workspace Admin, Host Operator"
echo "  carol   - Developer, Host Viewer"
echo "  dave    - SRE Team Member"
echo "  eve     - External User (limited access)"
echo
echo "Quick Tests:"
echo
echo "  # Test RBAC permissions"
echo "  zed --endpoint localhost:50051 --insecure \\"
echo "    permission check workspace:production edit user:bob"
echo
echo "  # Test inventory permissions"
echo "  zed --endpoint localhost:50051 --insecure \\"
echo "    permission check host:web-01.acme.com read user:carol"
echo
echo "  # List user's workspaces"
echo "  zed --endpoint localhost:50051 --insecure \\"
echo "    lookup resources workspace view user:bob"
echo
echo "  # List user's hosts"
echo "  zed --endpoint localhost:50051 --insecure \\"
echo "    lookup resources host read user:carol"
echo
echo "Run Integration Examples:"
echo
echo "  # RBAC integration demo"
echo "  cd sample-data/insights-examples && npm run demo:rbac"
echo
echo "  # Inventory integration demo"
echo "  cd sample-data/insights-examples && npm run demo:inventory"
echo
echo "  # All demos"
echo "  cd sample-data/insights-examples && npm run demo:all"
echo
echo "Documentation:"
echo "  Complete guide: QUICKSTART.md"
echo "  Architecture: docs/architecture.md"
echo "  Getting started: docs/getting-started.md"
echo "  RBAC schema: sample-data/schemas/insights/rbac-schema.zed"
echo "  Inventory schema: sample-data/schemas/insights/inventory-schema.zed"
echo "  Sample data: sample-data/insights/principals.json"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

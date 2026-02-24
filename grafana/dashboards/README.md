# Kessel-in-a-Box Grafana Dashboards

Updated: 2026-02-17

This directory contains **7 Grafana dashboards** - **5 essential dashboards** for the minimal demo environment plus **2 dashboards** for full Kessel deployment.

---

## Important Context

Kessel-in-a-box is a **MINIMAL DEMO** that includes:
- ✅ SpiceDB (authorization service)
- ✅ PostgreSQL databases (3 instances)
- ✅ Prometheus (metrics)
- ✅ Grafana (dashboards)
- ✅ AlertManager (alerts)
- ✅ Node Exporter (host metrics)
- ✅ Health Exporter (service health checks)

**NOT included:**
- ❌ inventory-api
- ❌ relations-api
- ❌ Kafka
- ❌ postgres-exporter

---

## Active Dashboards (5 Essential)

### 1. **Kessel SpiceDB Demo** ⭐ RECOMMENDED
**File:** `kessel-spicedb-demo.json`
**Best for:** Demo presentations and comprehensive monitoring

**Why this is the best dashboard:**
- Most comprehensive SpiceDB monitoring
- Professional appearance for demos
- Perfect balance of detail and clarity
- All key metrics in one place

**Sections:**
- **Overview**: Status, total requests, average latency, cache hit rate, error rate
- **Permission Checks**: CheckPermission request rate and latency (p50, p95, p99)
- **gRPC Methods**: Request rate and latency breakdown by method
- **Cache Performance**: Hits vs misses, hit rate percentage
- **Database**: PostgreSQL connection pool metrics (acquired, idle, total, max, utilization %)
- **Go Runtime**: Active goroutines, memory allocated, GC pause duration

**Use this for:**
- Customer demos
- Performance monitoring
- Troubleshooting authorization issues
- Understanding SpiceDB behavior

---

### 2. **Kessel Demo Overview**
**File:** `kessel-apis-overview.json`
**Best for:** Quick health check during demos

**Purpose:**
- High-level overview of demo environment
- Fast health status check
- Simple and clear presentation

**Metrics:**
- SpiceDB status (up/down)
- Request rate by gRPC method
- p95 latency
- Cache hit rate
- PostgreSQL connections
- Error rates and gRPC status codes

**Use this for:**
- Pre-demo health check
- Quick status overview
- Monitoring during presentations

---

### 3. **SpiceDB Authorization**
**File:** `kessel-relations-api.json`
**Best for:** Deep dive into authorization patterns

**Purpose:**
- Detailed SpiceDB authorization metrics
- Authorization operations analysis
- Permission check performance

**Metrics:**
- Permission check performance
- Relationship management operations
- gRPC method latency percentiles
- Status codes and error analysis
- Go runtime metrics

**Use this for:**
- Debugging authorization issues
- Understanding permission check patterns
- Performance tuning
- Analyzing relationship operations

---

### 4. **Kessel System (Minimal Demo)** ⚠️
**File:** `kessel-system-minimal-demo.json`
**Best for:** Overall system health monitoring

**Purpose:**
- System-wide health monitoring
- Infrastructure status
- Resource utilization

**Metrics:**
- Service health (SpiceDB, Prometheus, Node Exporter)
- SpiceDB request rate and latency
- System resources (CPU, Memory, Disk, Network)

**Note:** Adapted from full system dashboard - references to Kafka/postgres-exporter removed

**Use this for:**
- Infrastructure monitoring
- Resource utilization tracking
- Overall system health

---

### 5. **Kessel Data Flow (Minimal Demo)** ⚠️
**File:** `kessel-data-flow-minimal-demo.json`
**Best for:** Understanding authorization request flow

**Purpose:**
- Authorization data flow visualization
- Request flow patterns
- Understanding how authorization works

**Metrics:**
- SpiceDB request rate (CheckPermission, ReadRelationships)
- SpiceDB request latency (p50, p95, p99)
- SpiceDB requests by status (OK vs Errors)

**Note:** Adapted from full data flow dashboard - inventory-api, relations-api, Kafka, CDC components removed

**Use this for:**
- Explaining authorization flow
- Understanding request patterns
- Visualizing data movement

---

## Dashboards for Full Kessel Deployment (2)

These dashboards are included but will show **"No data"** until the corresponding services are deployed.

### 6. **Insights Host Inventory** ⚠️
**File:** `insights-host-inventory.json`
**Status:** ⚠️ Requires insights-host-inventory service (not in minimal demo)
**Best for:** Host inventory management monitoring

**Purpose:**
- Monitor host inventory operations
- Track host creation, updates, deletions
- Message queue performance
- Event production metrics
- RBAC authorization tracking

**Metrics Categories:**
- **Host Operations**: Create, update, delete, synchronize operations
- **Performance**: Deduplication, host lookup, commit latency
- **Message Queue**: Message processing, parsing failures, host additions
- **Event Production**: Event producer success/failure by topic
- **RBAC**: Access denied events, RBAC fetching failures

**To enable:**
1. Deploy insights-host-inventory service
2. Configure Prometheus to scrape `job="host-inventory"` or `job="insights-host-inventory"`
3. Metrics endpoint: `/metrics`

**Key Metrics:**
```promql
inventory_create_host_count             # Total hosts created
inventory_ingress_message_handler_*     # Message processing
inventory_event_producer_successes      # Events produced
inventory_rbac_access_denied            # Authorization failures
```

---

### 7. **Insights RBAC** ⚠️
**File:** `insights-rbac.json`
**Status:** ⚠️ Requires insights-rbac service (not in minimal demo)
**Best for:** RBAC service monitoring (Django application)

**Purpose:**
- Monitor RBAC Django application
- HTTP request/response metrics
- Database query performance
- Cache performance
- Application health

**Metrics Categories:**
- **HTTP Requests**: Request rate by method, view, status codes
- **Request Latency**: Latency percentiles (p50, p95, p99) by view
- **Database**: Operations, errors, connections
- **Cache**: Hit rate, operations, failures

**To enable:**
1. Deploy insights-rbac service (Django + django-prometheus)
2. Configure Prometheus to scrape `job="rbac"` or `job="insights-rbac"`
3. Metrics endpoint: `/metrics` or `/prometheus/metrics`

**Key Metrics:**
```promql
django_http_requests_total_by_method          # HTTP requests
django_http_requests_latency_seconds_*        # Request latency
django_db_execute_total                       # Database queries
django_cache_hits_total                       # Cache hits
```

**Technology:**
- Python/Django framework
- Libraries: django-prometheus, prometheus-client
- Automatic Django middleware metrics

---

## Dashboard Selection Guide

### For Demo Presentations
**Primary:** Kessel SpiceDB Demo ⭐
**Secondary:** Kessel Demo Overview (for quick checks)

### For Development & Debugging
**Primary:** SpiceDB Authorization
**Secondary:** Kessel SpiceDB Demo ⭐

### For Infrastructure Monitoring
**Primary:** Kessel System (Minimal Demo)
**Secondary:** Kessel Data Flow (Minimal Demo)

---

## Dashboard Features

All dashboards include:
- ✅ **10-second refresh rate** (demo-optimized)
- ✅ **Warning banners** (⚠️) on adapted dashboards
- ✅ **Proper latency thresholds**:
  - Green: < 10ms
  - Yellow: 10-50ms
  - Red: > 50ms
- ✅ **Actual SpiceDB metrics** (not placeholders)
- ✅ **Dark theme optimized**
- ✅ **No "No data" panels**

---

## Available Metrics

### gRPC Server Metrics
```promql
grpc_server_handled_total{job="spicedb"}
grpc_server_handling_seconds_bucket{job="spicedb"}
grpc_server_started_total{job="spicedb"}
grpc_server_msg_received_total{job="spicedb"}
grpc_server_msg_sent_total{job="spicedb"}
```

### SpiceDB Specific Metrics
```promql
spicedb_cache_hits_total
spicedb_cache_misses_total
spicedb_check_direct_dispatch_query_count_bucket
spicedb_datastore_gc_duration_seconds_bucket
spicedb_datastore_gc_namespaces_total
```

### PostgreSQL Connection Pool Metrics
```promql
pgxpool_acquired_conns{job="spicedb"}
pgxpool_idle_conns{job="spicedb"}
pgxpool_total_conns{job="spicedb"}
pgxpool_max_conns{job="spicedb"}
pgxpool_acquire_duration_ns{job="spicedb"}
```

### Go Runtime Metrics
```promql
go_goroutines{job="spicedb"}
go_memstats_alloc_bytes{job="spicedb"}
go_gc_duration_seconds{job="spicedb"}
```

### System Metrics (Node Exporter)
```promql
node_cpu_seconds_total{job="node"}
node_memory_MemAvailable_bytes{job="node"}
node_filesystem_avail_bytes{job="node"}
node_network_receive_bytes_total{job="node"}
```

---

## Archived Dashboards

The following dashboards have been moved to `/archive/`:

### Original Production Dashboards (4)
These require full Kessel deployment:
- `kessel-inventory-api.json` - Requires inventory-api service
- `kessel-data-pipeline.json` - Requires Kafka, Debezium
- `kessel-complete-system.json` - Requires Kafka, postgres-exporter
- `kessel-data-flow.json` - Requires inventory-api, relations-api, Kafka, CDC

### Redundant Dashboards (4)
These were removed to simplify the dashboard list:
- `kessel-authorization-monitoring.json` - Redundant with SpiceDB Authorization
- `kessel-data-pipeline-minimal-demo.json` - Similar to Data Flow (Minimal Demo)
- `kessel-overview.json` - Redundant with Kessel Demo Overview
- `spicedb-overview.json` - Redundant with Kessel SpiceDB Demo (which is better)

**Why archived:** Original dashboards require services not in kessel-in-a-box. Redundant dashboards provided similar functionality to kept dashboards.

---

## Usage

### Accessing Grafana

**URL:** http://localhost:3000

**Default credentials:**
- Username: `admin`
- Password: `admin`

### Recommended Starting Point

**For demos:** Start with **Kessel SpiceDB Demo** ⭐

This is the best all-around dashboard with comprehensive monitoring.

### Dashboard Navigation

- Click "Dashboards" icon (left sidebar)
- Search or browse by folder: **Kessel**
- Filter by tags: `kessel`, `spicedb`, `authorization`, `minimal`, `demo`

---

## Troubleshooting

### Dashboard Shows "No data"

**Step 1:** Verify SpiceDB is running
```bash
docker ps | grep spicedb
```

**Step 2:** Check Prometheus targets
```bash
curl http://localhost:9091/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job) - \(.health)"'
# Expected: spicedb - up
```

**Step 3:** Verify SpiceDB metrics
```bash
curl http://localhost:9090/metrics | grep grpc_server_started_total
```

**Step 4:** Check Grafana datasource
- Grafana UI → Configuration → Data Sources → Prometheus
- URL should be: `http://prometheus:9090`
- Click "Save & Test"

### Panel Shows "Metric not found"

**Verify metric exists:**
```bash
curl http://localhost:9090/metrics | grep -E "^[a-z]" | cut -d'{' -f1 | sort -u
```

**Common issues:**
- Using `spicedb_grpc_server_*` instead of `grpc_server_*`
- Missing job label: `{job="spicedb"}`
- Querying non-existent service

### Dashboard Not Loading

**Restart Grafana:**
```bash
docker-compose -f compose/docker-compose.yml restart grafana
```

**Check Grafana logs:**
```bash
docker logs kessel-grafana | tail -50
```

---

## Migration Notes

### From Full Kessel Deployment

If migrating from full deployment:
1. Use the 5 essential dashboards (work with minimal demo)
2. Original dashboards archived in `/archive/` for reference
3. Warning banners (⚠️) indicate adapted dashboards

### To Full Kessel Deployment

If deploying full Kessel stack:
1. Restore original dashboards from `/archive/`
2. Deploy missing services (inventory-api, relations-api, Kafka)
3. Configure Prometheus scrape targets
4. Install postgres-exporter

---

## Technical Details

### Dashboard Auto-Loading

Grafana automatically loads all dashboards from this directory on startup.

**Provisioning config:** `grafana/provisioning/dashboards/dashboards.yml`

### Datasource Configuration

All dashboards use the Prometheus datasource:
- **Name:** Prometheus
- **UID:** `prometheus`
- **URL:** `http://prometheus:9090`

**Datasource config:** `grafana/provisioning/datasources/prometheus.yml`

### Dashboard UIDs

Each dashboard has a stable UID for consistent linking:
- `kessel-spicedb-demo` - Kessel SpiceDB Demo
- `kessel-apis-overview` - Kessel Demo Overview
- `kessel-relations-api` - SpiceDB Authorization
- `kessel-system-minimal` - Kessel System (Minimal Demo)
- `kessel-data-flow-minimal` - Kessel Data Flow (Minimal Demo)
- `insights-host-inventory` - Insights Host Inventory
- `insights-rbac` - Insights RBAC

---

## Summary

**Total Active Dashboards:** 7
- **For Minimal Demo:** 5 dashboards (all working)
- **For Full Deployment:** 2 dashboards (requires additional services)

**Total Archived Dashboards:** 8 (4 original + 4 redundant)

**Dashboard Breakdown:**
- ✅ **5 essential dashboards** - Work with kessel-in-a-box minimal demo
- ⚠️ **2 optional dashboards** - Require insights-host-inventory and insights-rbac services
- 🗂️ **8 archived dashboards** - Require full Kessel production deployment

**Why this structure?**
- ✅ Eliminates redundancy
- ✅ Easier to navigate
- ✅ Clearer purpose for each dashboard
- ✅ Better user experience
- ✅ All essential use cases covered
- ✅ Ready for full deployment expansion

**Key Dashboard:**
**Kessel SpiceDB Demo** ⭐ is the primary dashboard for most use cases.

---

*Last updated: 2026-02-17*
*Dashboards optimized for kessel-in-a-box minimal demo environment*

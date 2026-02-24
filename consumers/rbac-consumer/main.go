package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/IBM/sarama"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Prometheus metrics
var (
	messagesProcessed = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "rbac_kafka_consumer_messages_processed_total",
			Help: "Total number of messages processed",
		},
		[]string{"topic", "status"},
	)
	validationErrors = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "rbac_kafka_consumer_validation_errors_total",
			Help: "Total number of validation errors",
		},
	)
	retryAttempts = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "rbac_kafka_consumer_retry_attempts_total",
			Help: "Total number of retry attempts",
		},
	)
	processingDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "rbac_kafka_consumer_message_processing_duration_seconds",
			Help:    "Message processing duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"topic"},
	)
)

func init() {
	prometheus.MustRegister(messagesProcessed)
	prometheus.MustRegister(validationErrors)
	prometheus.MustRegister(retryAttempts)
	prometheus.MustRegister(processingDuration)
}

// DebeziumEvent represents a Debezium CDC event (flattened by ExtractNewRecordState SMT)
type DebeziumEvent struct {
	// Flattened fields - all data fields are at top level
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	WorkspaceID string `json:"workspace_id"` // For roles
	TenantID    string `json:"tenant_id"`    // For workspaces
	CreatedAt   int64  `json:"created_at"`
	UpdatedAt   int64  `json:"updated_at"`

	// Debezium metadata fields
	Op      string `json:"__op"`      // c=create, u=update, d=delete, r=read(snapshot)
	Table   string `json:"__table"`   // Table name
	LSN     int64  `json:"__lsn"`     // Log sequence number
	TSMS    int64  `json:"__source_ts_ms"`
	Deleted string `json:"__deleted"` // "true" or "false"
}

// RelationshipRequest represents a request to create/delete a relationship
// This matches the format expected by kessel-relations-api
type RelationshipRequest struct {
	ResourceType string `json:"resource_type"`
	ResourceID   string `json:"resource_id"`
	Relation     string `json:"relation"`
	SubjectType  string `json:"subject_type"`
	SubjectID    string `json:"subject_id"`
}

// RBACConsumer consumes RBAC events and creates relationships in Kessel
type RBACConsumer struct {
	relationsAPIURL string
	consumer        sarama.ConsumerGroup
	topics          []string
	healthPath      string
	readyPath       string
}

func NewRBACConsumer(brokers []string, groupID, relationsAPIURL string, topics []string) (*RBACConsumer, error) {
	config := sarama.NewConfig()
	config.Version = sarama.V3_0_0_0
	config.Consumer.Group.Rebalance.Strategy = sarama.NewBalanceStrategyRoundRobin()
	config.Consumer.Offsets.Initial = sarama.OffsetOldest
	config.Consumer.Return.Errors = true
	// Manual offset commit for exactly-once processing
	config.Consumer.Offsets.AutoCommit.Enable = false

	consumer, err := sarama.NewConsumerGroup(brokers, groupID, config)
	if err != nil {
		return nil, fmt.Errorf("failed to create consumer group: %w", err)
	}

	return &RBACConsumer{
		relationsAPIURL: relationsAPIURL,
		consumer:        consumer,
		topics:          topics,
		healthPath:      "/tmp/kubernetes-liveness",
		readyPath:       "/tmp/kubernetes-readiness",
	}, nil
}

func (c *RBACConsumer) Start(ctx context.Context) error {
	// Create health check files
	c.updateHealthStatus(true)
	c.updateReadyStatus(true)

	handler := &ConsumerGroupHandler{
		relationsAPIURL: c.relationsAPIURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}

	for {
		select {
		case <-ctx.Done():
			c.updateHealthStatus(false)
			c.updateReadyStatus(false)
			return ctx.Err()
		default:
			if err := c.consumer.Consume(ctx, c.topics, handler); err != nil {
				log.Printf("Error from consumer: %v", err)
				c.updateReadyStatus(false)
				time.Sleep(5 * time.Second) // Brief pause before retry
			}
		}
	}
}

func (c *RBACConsumer) updateHealthStatus(healthy bool) {
	if healthy {
		os.WriteFile(c.healthPath, []byte("healthy"), 0644)
	} else {
		os.Remove(c.healthPath)
	}
}

func (c *RBACConsumer) updateReadyStatus(ready bool) {
	if ready {
		os.WriteFile(c.readyPath, []byte("ready"), 0644)
	} else {
		os.Remove(c.readyPath)
	}
}

func (c *RBACConsumer) Close() error {
	c.updateHealthStatus(false)
	c.updateReadyStatus(false)
	return c.consumer.Close()
}

// ConsumerGroupHandler handles consumed messages with infinite retry logic
type ConsumerGroupHandler struct {
	relationsAPIURL string
	httpClient      *http.Client
}

func (h *ConsumerGroupHandler) Setup(_ sarama.ConsumerGroupSession) error {
	log.Println("Consumer group session setup complete")
	return nil
}

func (h *ConsumerGroupHandler) Cleanup(_ sarama.ConsumerGroupSession) error {
	log.Println("Consumer group session cleanup complete")
	return nil
}

func (h *ConsumerGroupHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for message := range claim.Messages() {
		// Process message with infinite retry
		h.processMessageWithRetry(message)

		// Only commit offset after successful processing
		session.MarkMessage(message, "")
		session.Commit()
	}
	return nil
}

// processMessageWithRetry implements infinite retry with exponential backoff
func (h *ConsumerGroupHandler) processMessageWithRetry(msg *sarama.ConsumerMessage) {
	attempt := 0
	maxBackoff := 5 * time.Minute
	baseBackoff := 1 * time.Second

	for {
		start := time.Now()
		err := h.processMessage(msg)
		duration := time.Since(start).Seconds()

		processingDuration.WithLabelValues(msg.Topic).Observe(duration)

		if err == nil {
			messagesProcessed.WithLabelValues(msg.Topic, "success").Inc()
			return
		}

		// Log error and retry
		attempt++
		retryAttempts.Inc()
		log.Printf("Error processing message (attempt %d): %v", attempt, err)

		// Calculate backoff with exponential increase and jitter
		backoff := time.Duration(math.Min(
			float64(baseBackoff)*math.Pow(2, float64(attempt-1)),
			float64(maxBackoff),
		))

		// Add jitter (±20%)
		jitter := time.Duration(rand.Float64()*0.4-0.2) * backoff
		backoff += jitter

		log.Printf("Retrying in %v...", backoff)
		time.Sleep(backoff)
	}
}

func (h *ConsumerGroupHandler) processMessage(msg *sarama.ConsumerMessage) error {
	log.Printf("Processing message from topic %s, partition %d, offset %d",
		msg.Topic, msg.Partition, msg.Offset)

	var event DebeziumEvent
	if err := json.Unmarshal(msg.Value, &event); err != nil {
		validationErrors.Inc()
		log.Printf("WARNING: Failed to unmarshal event (skipping): %v", err)
		// Skip malformed messages - don't retry
		return nil
	}

	log.Printf("Event: op=%s, table=%s", event.Op, event.Table)

	// Handle different operations
	switch event.Op {
	case "c", "r": // Create or Read (snapshot)
		return h.handleCreate(event)
	case "u": // Update
		return h.handleUpdate(event)
	case "d": // Delete
		return h.handleDelete(event)
	default:
		log.Printf("Unknown operation: %s (skipping)", event.Op)
		return nil
	}
}

func (h *ConsumerGroupHandler) handleCreate(event DebeziumEvent) error {
	switch event.Table {
	case "workspaces":
		return h.createWorkspaceRelationships(event)
	case "roles":
		return h.createRoleRelationships(event)
	default:
		log.Printf("Unhandled table: %s", event.Table)
	}
	return nil
}

func (h *ConsumerGroupHandler) handleUpdate(event DebeziumEvent) error {
	// For simplicity, treat update as delete + create
	// This ensures all relationships are refreshed
	if err := h.handleDelete(event); err != nil {
		return err
	}
	return h.handleCreate(event)
}

func (h *ConsumerGroupHandler) handleDelete(event DebeziumEvent) error {
	switch event.Table {
	case "workspaces":
		return h.deleteWorkspaceRelationships(event)
	case "roles":
		return h.deleteRoleRelationships(event)
	default:
		log.Printf("Unhandled table: %s", event.Table)
	}
	return nil
}

// createWorkspaceRelationships creates relationships for a workspace using production schema
func (h *ConsumerGroupHandler) createWorkspaceRelationships(event DebeziumEvent) error {
	if event.ID == "" {
		validationErrors.Inc()
		log.Printf("WARNING: workspace id not found (skipping)")
		return nil
	}

	log.Printf("Creating relationships for workspace: %s (name: %s)", event.ID, event.Name)

	// Relationship 1: workspace -> parent tenant
	// rbac/workspace:workspace_id#t_parent@rbac/tenant:tenant_id
	if event.TenantID != "" {
		relationship := &RelationshipRequest{
			ResourceType: "rbac/workspace",
			ResourceID:   event.ID,
			Relation:     "t_parent",
			SubjectType:  "rbac/tenant",
			SubjectID:    event.TenantID,
		}
		if err := h.createRelationship(relationship); err != nil {
			return err
		}
	}

	// Relationship 2: Default admin ownership (for demo purposes)
	// In production, this would come from actual user/role data
	// rbac/workspace:workspace_id#t_binding@rbac/role_binding:binding_id
	// For now, we'll skip this as it requires additional role binding data

	return nil
}

// createRoleRelationships creates relationships for a role using production schema
func (h *ConsumerGroupHandler) createRoleRelationships(event DebeziumEvent) error {
	if event.ID == "" {
		validationErrors.Inc()
		log.Printf("WARNING: role id not found (skipping)")
		return nil
	}

	if event.WorkspaceID == "" {
		validationErrors.Inc()
		log.Printf("WARNING: workspace_id not found for role (skipping)")
		return nil
	}

	log.Printf("Creating relationships for role: %s (name: %s) in workspace: %s",
		event.ID, event.Name, event.WorkspaceID)

	// Note: The production schema doesn't have a simple "role belongs to workspace" relationship
	// Instead, roles are bound to resources via role_bindings
	// For this demo, we'll skip role relationships as they require the full binding context

	log.Printf("Note: Role relationships require role_binding context - skipping for now")
	return nil
}

// deleteWorkspaceRelationships deletes relationships for a workspace
func (h *ConsumerGroupHandler) deleteWorkspaceRelationships(event DebeziumEvent) error {
	if event.ID == "" {
		validationErrors.Inc()
		log.Printf("WARNING: workspace id not found for deletion (skipping)")
		return nil
	}

	log.Printf("Deleting relationships for workspace: %s", event.ID)

	// Delete parent relationship
	if event.TenantID != "" {
		relationship := &RelationshipRequest{
			ResourceType: "rbac/workspace",
			ResourceID:   event.ID,
			Relation:     "t_parent",
			SubjectType:  "rbac/tenant",
			SubjectID:    event.TenantID,
		}
		if err := h.deleteRelationship(relationship); err != nil {
			return err
		}
	}

	return nil
}

// deleteRoleRelationships deletes relationships for a role
func (h *ConsumerGroupHandler) deleteRoleRelationships(event DebeziumEvent) error {
	if event.ID == "" {
		validationErrors.Inc()
		log.Printf("WARNING: role id not found for deletion (skipping)")
		return nil
	}

	log.Printf("Deleting relationships for role: %s", event.ID)
	// Role relationship deletion would happen here if we had role relationships
	return nil
}

// createRelationship creates a relationship in SpiceDB via the Relations API
// Implements the retry logic for transient failures
func (h *ConsumerGroupHandler) createRelationship(req *RelationshipRequest) error {
	jsonData, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to marshal relationship request: %w", err)
	}

	url := fmt.Sprintf("%s/v1/relationships", h.relationsAPIURL)
	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")

	log.Printf("Creating relationship: %s:%s#%s@%s:%s",
		req.ResourceType, req.ResourceID,
		req.Relation,
		req.SubjectType, req.SubjectID)

	resp, err := h.httpClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("failed to call Relations API: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		log.Printf("✓ Successfully created relationship")
		return nil
	}

	// Return error to trigger retry
	return fmt.Errorf("Relations API returned status %d: %s", resp.StatusCode, string(body))
}

// deleteRelationship deletes a relationship from SpiceDB via the Relations API
func (h *ConsumerGroupHandler) deleteRelationship(req *RelationshipRequest) error {
	jsonData, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to marshal relationship request: %w", err)
	}

	url := fmt.Sprintf("%s/v1/relationships", h.relationsAPIURL)
	httpReq, err := http.NewRequest("DELETE", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")

	log.Printf("Deleting relationship: %s:%s#%s@%s:%s",
		req.ResourceType, req.ResourceID,
		req.Relation,
		req.SubjectType, req.SubjectID)

	resp, err := h.httpClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("failed to call Relations API: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		log.Printf("✓ Successfully deleted relationship")
		return nil
	}

	return fmt.Errorf("Relations API returned status %d: %s", resp.StatusCode, string(body))
}

func main() {
	// Configuration from environment
	kafkaBrokers := getEnv("KAFKA_BROKERS", "kafka:29092")
	groupID := getEnv("RBAC_KAFKA_CONSUMER_GROUP_ID", "rbac-consumer-group")
	relationsAPIURL := getEnv("KESSEL_RELATIONS_API_URL", "http://kessel-relations-api:8000")
	metricsPort := getEnv("METRICS_PORT", "9090")

	topics := []string{
		getEnv("RBAC_KAFKA_CONSUMER_TOPIC_WORKSPACES", "rbac.workspaces.events"),
		getEnv("RBAC_KAFKA_CONSUMER_TOPIC_ROLES", "rbac.roles.events"),
	}

	log.Printf("Starting RBAC Kafka Consumer")
	log.Printf("Kafka Brokers: %s", kafkaBrokers)
	log.Printf("Consumer Group: %s", groupID)
	log.Printf("Relations API: %s", relationsAPIURL)
	log.Printf("Topics: %v", topics)
	log.Printf("Metrics Port: %s", metricsPort)

	// Start Prometheus metrics server
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		addr := fmt.Sprintf(":%s", metricsPort)
		log.Printf("Starting metrics server on %s", addr)
		if err := http.ListenAndServe(addr, nil); err != nil {
			log.Printf("Metrics server error: %v", err)
		}
	}()

	consumer, err := NewRBACConsumer(
		[]string{kafkaBrokers},
		groupID,
		relationsAPIURL,
		topics,
	)
	if err != nil {
		log.Fatalf("Failed to create consumer: %v", err)
	}
	defer consumer.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-signals
		log.Printf("Received shutdown signal: %v", sig)
		cancel()
	}()

	// Start consuming
	log.Println("Starting to consume messages...")
	if err := consumer.Start(ctx); err != nil && err != context.Canceled {
		log.Fatalf("Consumer error: %v", err)
	}

	log.Println("Consumer stopped gracefully")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

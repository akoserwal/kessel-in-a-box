package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

var (
	db                   *sql.DB
	relationsAPIURL      string
	serverPort           = getEnv("SERVER_PORT", "8000")
)

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func main() {
	// Database configuration
	dbHost := getEnv("POSTGRES_HOST", "localhost")
	dbPort := getEnv("POSTGRES_PORT", "5432")
	dbUser := getEnv("POSTGRES_USER", "inventory")
	dbPassword := getEnv("POSTGRES_PASSWORD", "secretpassword")
	dbName := getEnv("POSTGRES_DB", "inventory")

	// Relations API configuration
	relationsAPIURL = getEnv("KESSEL_RELATIONS_ENDPOINT", "http://kessel-relations-api:8000")

	// Connect to PostgreSQL
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPassword, dbName)

	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Wait for database to be ready
	for i := 0; i < 30; i++ {
		err = db.Ping()
		if err == nil {
			break
		}
		log.Printf("Waiting for database... (%d/30)", i+1)
		time.Sleep(1 * time.Second)
	}
	if err != nil {
		log.Fatalf("Database not available: %v", err)
	}

	log.Printf("Connected to PostgreSQL at %s:%s", dbHost, dbPort)

	// Initialize schema
	if err := initSchema(); err != nil {
		log.Fatalf("Failed to initialize schema: %v", err)
	}

	// Setup HTTP handlers
	http.HandleFunc("/health", healthCheckHandler)
	http.HandleFunc("/livez", healthCheckHandler)
	http.HandleFunc("/readyz", readyCheckHandler)
	http.HandleFunc("/api/inventory/v1/resources", resourcesHandler)
	http.HandleFunc("/api/inventory/v1/resources/", resourceGetHandler)

	// Start HTTP server
	addr := ":" + serverPort
	log.Printf("Starting kessel-inventory-api (mock) on %s", addr)
	log.Printf("Endpoints: /api/inventory/v1/resources")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS resources (
		id TEXT PRIMARY KEY,
		resource_type TEXT NOT NULL,
		workspace_id TEXT,
		metadata JSONB,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_resources_type ON resources(resource_type);
	CREATE INDEX IF NOT EXISTS idx_resources_workspace ON resources(workspace_id);
	`

	_, err := db.Exec(schema)
	if err != nil {
		return fmt.Errorf("failed to create schema: %w", err)
	}

	log.Println("Database schema initialized")
	return nil
}

func healthCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func readyCheckHandler(w http.ResponseWriter, r *http.Request) {
	// Check database connectivity
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "not ready", "error": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

// ResourceRequest represents a request to create a resource
type ResourceRequest struct {
	ResourceType string                 `json:"resource_type"`
	ResourceID   string                 `json:"resource_id"`
	WorkspaceID  string                 `json:"workspace_id,omitempty"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
}

func resourcesHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		createResourceHandler(w, r)
	case http.MethodGet:
		listResourcesHandler(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func createResourceHandler(w http.ResponseWriter, r *http.Request) {
	var req ResourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
		return
	}

	log.Printf("Creating resource: %s:%s in workspace %s", req.ResourceType, req.ResourceID, req.WorkspaceID)

	// Store resource in database
	metadataJSON, _ := json.Marshal(req.Metadata)
	_, err := db.Exec(`
		INSERT INTO resources (id, resource_type, workspace_id, metadata, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (id) DO UPDATE SET
			resource_type = EXCLUDED.resource_type,
			workspace_id = EXCLUDED.workspace_id,
			metadata = EXCLUDED.metadata,
			updated_at = EXCLUDED.updated_at
	`, req.ResourceID, req.ResourceType, req.WorkspaceID, metadataJSON, time.Now(), time.Now())

	if err != nil {
		log.Printf("Failed to store resource: %v", err)
		http.Error(w, fmt.Sprintf("Failed to store resource: %v", err), http.StatusInternalServerError)
		return
	}

	// Create relationship in SpiceDB if workspace is specified
	if req.WorkspaceID != "" {
		if err := createResourceRelationship(req.ResourceType, req.ResourceID, req.WorkspaceID); err != nil {
			log.Printf("Warning: Failed to create relationship: %v", err)
			// Don't fail the request, just log the error
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":            req.ResourceID,
		"resource_type": req.ResourceType,
		"workspace_id":  req.WorkspaceID,
		"metadata":      req.Metadata,
		"created_at":    time.Now().Format(time.RFC3339),
	})
}

func createResourceRelationship(resourceType, resourceID, workspaceID string) error {
	// Create relationship: hbi/host:resourceID#t_workspace@rbac/workspace:workspaceID
	// According to the schema, hbi/host has a relation TO rbac/workspace (not the other way around)
	relationshipReq := map[string]string{
		"resource_type": "hbi/host",
		"resource_id":   resourceID,
		"relation":      "t_workspace",
		"subject_type":  "rbac/workspace",
		"subject_id":    workspaceID,
	}

	reqBody, _ := json.Marshal(relationshipReq)
	req, err := http.NewRequest("POST", relationsAPIURL+"/v1/relationships", bytes.NewBuffer(reqBody))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("relations API returned status %d", resp.StatusCode)
	}

	log.Printf("Created relationship: hbi/host:%s#t_workspace@rbac/workspace:%s", resourceID, workspaceID)
	return nil
}

func listResourcesHandler(w http.ResponseWriter, r *http.Request) {
	resourceType := r.URL.Query().Get("resource_type")
	workspaceID := r.URL.Query().Get("workspace_id")

	query := "SELECT id, resource_type, workspace_id, metadata, created_at FROM resources WHERE 1=1"
	args := []interface{}{}
	argNum := 1

	if resourceType != "" {
		query += fmt.Sprintf(" AND resource_type = $%d", argNum)
		args = append(args, resourceType)
		argNum++
	}

	if workspaceID != "" {
		query += fmt.Sprintf(" AND workspace_id = $%d", argNum)
		args = append(args, workspaceID)
		argNum++
	}

	query += " ORDER BY created_at DESC LIMIT 100"

	rows, err := db.Query(query, args...)
	if err != nil {
		http.Error(w, fmt.Sprintf("Query failed: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	resources := []map[string]interface{}{}
	for rows.Next() {
		var id, resType, workspaceID string
		var metadataJSON []byte
		var createdAt time.Time

		if err := rows.Scan(&id, &resType, &workspaceID, &metadataJSON, &createdAt); err != nil {
			continue
		}

		var metadata map[string]interface{}
		json.Unmarshal(metadataJSON, &metadata)

		resources = append(resources, map[string]interface{}{
			"id":            id,
			"resource_type": resType,
			"workspace_id":  workspaceID,
			"metadata":      metadata,
			"created_at":    createdAt.Format(time.RFC3339),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"resources": resources,
		"count":     len(resources),
	})
}

func resourceGetHandler(w http.ResponseWriter, r *http.Request) {
	// Extract resource ID from URL path
	resourceID := r.URL.Path[len("/api/inventory/v1/resources/"):]
	if resourceID == "" {
		http.Error(w, "Resource ID required", http.StatusBadRequest)
		return
	}

	var id, resType, workspaceID string
	var metadataJSON []byte
	var createdAt time.Time

	err := db.QueryRow(`
		SELECT id, resource_type, workspace_id, metadata, created_at
		FROM resources WHERE id = $1
	`, resourceID).Scan(&id, &resType, &workspaceID, &metadataJSON, &createdAt)

	if err == sql.ErrNoRows {
		http.Error(w, "Resource not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, fmt.Sprintf("Query failed: %v", err), http.StatusInternalServerError)
		return
	}

	var metadata map[string]interface{}
	json.Unmarshal(metadataJSON, &metadata)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":            id,
		"resource_type": resType,
		"workspace_id":  workspaceID,
		"metadata":      metadata,
		"created_at":    createdAt.Format(time.RFC3339),
	})
}

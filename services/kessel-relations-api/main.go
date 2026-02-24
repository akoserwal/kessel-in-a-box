package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	v1 "github.com/authzed/authzed-go/proto/authzed/api/v1"
	"github.com/authzed/authzed-go/v1"
	"github.com/authzed/grpcutil"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var (
	spicedbClient *authzed.Client
	serverPort    = getEnv("SERVER_PORT", "8000")
)

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func main() {
	// Connect to SpiceDB
	spicedbEndpoint := getEnv("SPICEDB_ENDPOINT", "localhost:50051")
	spicedbToken := getEnv("SPICEDB_TOKEN", "testtesttesttest")

	log.Printf("Connecting to SpiceDB at %s", spicedbEndpoint)

	var err error
	spicedbClient, err = authzed.NewClient(
		spicedbEndpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpcutil.WithInsecureBearerToken(spicedbToken),
	)
	if err != nil {
		log.Fatalf("Failed to connect to SpiceDB: %v", err)
	}

	// Setup HTTP handlers
	http.HandleFunc("/health", healthCheckHandler)
	http.HandleFunc("/livez", healthCheckHandler)
	http.HandleFunc("/readyz", readyCheckHandler)
	http.HandleFunc("/v1/relationships", relationshipsHandler)
	http.HandleFunc("/v1/permissions/check", checkPermissionHandler)

	// Start HTTP server
	addr := ":" + serverPort
	log.Printf("Starting kessel-relations-api (mock) on %s", addr)
	log.Printf("Endpoints: /v1/relationships, /v1/permissions/check")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func healthCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func readyCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

// RelationshipRequest represents a request to create/update relationships
type RelationshipRequest struct {
	ResourceType string `json:"resource_type"`
	ResourceID   string `json:"resource_id"`
	Relation     string `json:"relation"`
	SubjectType  string `json:"subject_type"`
	SubjectID    string `json:"subject_id"`
}

func relationshipsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RelationshipRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
		return
	}

	log.Printf("Creating relationship: %s:%s#%s@%s:%s",
		req.ResourceType, req.ResourceID, req.Relation, req.SubjectType, req.SubjectID)

	// Create relationship in SpiceDB
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	update := &v1.RelationshipUpdate{
		Operation: v1.RelationshipUpdate_OPERATION_TOUCH,
		Relationship: &v1.Relationship{
			Resource: &v1.ObjectReference{
				ObjectType: req.ResourceType,
				ObjectId:   req.ResourceID,
			},
			Relation: req.Relation,
			Subject: &v1.SubjectReference{
				Object: &v1.ObjectReference{
					ObjectType: req.SubjectType,
					ObjectId:   req.SubjectID,
				},
			},
		},
	}

	writeReq := &v1.WriteRelationshipsRequest{
		Updates: []*v1.RelationshipUpdate{update},
	}

	resp, err := spicedbClient.WriteRelationships(ctx, writeReq)
	if err != nil {
		log.Printf("Failed to write relationship: %v", err)
		http.Error(w, fmt.Sprintf("Failed to write relationship: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "created",
		"written_at": resp.WrittenAt.String(),
	})
}

// CheckPermissionRequest represents a permission check request
type CheckPermissionRequest struct {
	ResourceType string `json:"resource_type"`
	ResourceID   string `json:"resource_id"`
	Permission   string `json:"permission"`
	SubjectType  string `json:"subject_type"`
	SubjectID    string `json:"subject_id"`
}

func checkPermissionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CheckPermissionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
		return
	}

	log.Printf("Checking permission: %s:%s#%s@%s:%s",
		req.ResourceType, req.ResourceID, req.Permission, req.SubjectType, req.SubjectID)

	// Check permission in SpiceDB
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	checkResp, err := spicedbClient.CheckPermission(ctx, &v1.CheckPermissionRequest{
		Resource: &v1.ObjectReference{
			ObjectType: req.ResourceType,
			ObjectId:   req.ResourceID,
		},
		Permission: req.Permission,
		Subject: &v1.SubjectReference{
			Object: &v1.ObjectReference{
				ObjectType: req.SubjectType,
				ObjectId:   req.SubjectID,
			},
		},
		Consistency: &v1.Consistency{
			Requirement: &v1.Consistency_FullyConsistent{
				FullyConsistent: true,
			},
		},
	})

	if err != nil {
		log.Printf("Failed to check permission: %v", err)
		http.Error(w, fmt.Sprintf("Failed to check permission: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"permissionship": checkResp.Permissionship.String(),
		"checked_at":     checkResp.CheckedAt.String(),
	})
}

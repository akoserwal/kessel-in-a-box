# RBAC Kafka Consumer - Production-ready consumer for RBAC events
# Based on Red Hat Insights RBAC consumer patterns
FROM golang:1.21-alpine AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum* ./
RUN go mod download

# Copy source
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o rbac-consumer .

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/rbac-consumer .

# Create directory for health check files
RUN mkdir -p /tmp

# Expose metrics port
EXPOSE 9090

CMD ["./rbac-consumer"]

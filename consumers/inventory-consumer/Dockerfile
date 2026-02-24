# Dockerfile for Official Kessel Inventory Consumer
# Builds from official project-kessel/inventory-consumer repository
# Source: https://github.com/project-kessel/inventory-consumer

# Builder stage - builds from official repo
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7-1770267347 AS builder

# Install build dependencies
RUN microdnf install -y tar gzip make which gcc git && \
    microdnf clean all

# Install Go 1.21 (detect architecture)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then GOARCH="amd64"; else GOARCH="arm64"; fi && \
    curl -LO https://go.dev/dl/go1.21.0.linux-${GOARCH}.tar.gz && \
    tar -C /usr/local -xzf go1.21.0.linux-${GOARCH}.tar.gz && \
    rm go1.21.0.linux-${GOARCH}.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Set working directory
WORKDIR /workspace

# Clone official repository
RUN git clone --depth 1 https://github.com/project-kessel/inventory-consumer.git . && \
    ls -la

# Download dependencies
RUN go mod download

# Build the binary using local-build (FIPS build doesn't work outside official Dockerfile)
ARG VERSION=dev
RUN make local-build VERSION=${VERSION} && \
    ls -la bin/

# Final runtime stage
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7-1770267347

# Install runtime dependencies
RUN microdnf install -y ca-certificates && \
    microdnf clean all

# Copy binary from builder
COPY --from=builder /workspace/bin/inventory-consumer /usr/local/bin/inventory-consumer

# Make binary executable
RUN chmod +x /usr/local/bin/inventory-consumer

# Set PATH
ENV PATH="/usr/local/bin:${PATH}"

# Run as non-root user
USER 1001

# Entrypoint
ENTRYPOINT ["inventory-consumer"]
CMD ["start"]

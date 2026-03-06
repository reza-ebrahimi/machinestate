# Dockerfile for machinestate (Go implementation)
#
# Build:
#   docker build -f Dockerfile.go -t machinestate:go .
#
# Run:
#   docker run -d -p 8080:8080 -v /proc:/host/proc:ro -v /sys:/host/sys:ro machinestate:go

# ==== Build Stage ====
FROM golang:1.23-alpine AS builder

WORKDIR /build
COPY go/ ./go/

RUN cd go && CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /machinestate .

# ==== Runtime Stage ====
FROM debian:12-slim

# Install tools for full functionality
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    iproute2 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create config directory
RUN mkdir -p /root/.config/machinestate

# Copy binary from builder
COPY --from=builder /machinestate /usr/bin/machinestate

# Expose HTTP port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD curl -f http://localhost:8080/health || exit 1

# Default command - run HTTP server
ENV MACHINESTATE_PORT=8080
ENTRYPOINT ["/usr/bin/machinestate"]
CMD ["--http", "8080"]

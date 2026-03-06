# Dockerfile for machinestate (Zig implementation)
#
# Build:
#   docker build -f Dockerfile.zig -t machinestate:zig .
#
# Run:
#   docker run -d -p 8080:8080 -v /proc:/host/proc:ro -v /sys:/host/sys:ro machinestate:zig

# ==== Build Stage ====
FROM alpine:latest AS builder

# Install Zig 0.16.0-dev (code uses 0.16 APIs)
RUN apk add --no-cache curl xz && \
    curl -fSL --retry 3 -o /tmp/zig.tar.xz https://ziglang.org/builds/zig-x86_64-linux-0.16.0-dev.1859+212968c57.tar.xz && \
    tar -xJf /tmp/zig.tar.xz && \
    mv zig-x86_64-linux-0.16.0-dev.1859+212968c57 /opt/zig && \
    rm /tmp/zig.tar.xz

ENV PATH="/opt/zig:${PATH}"

WORKDIR /build
COPY zig/ ./zig/

RUN cd zig && zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu && \
    cp zig-out/bin/machinestate /machinestate

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

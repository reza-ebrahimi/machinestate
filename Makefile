.PHONY: all go zig clean test validate validate-mcp benchmark install
.PHONY: build-amd64 build-arm64 build-amd64-musl build-arm64-musl build-all-arch release
.PHONY: docker-build docker-run docker-stop docker-compose-up docker-compose-down

all: go zig

go:
	cd go && go build -o machinestate .

zig:
	cd zig && zig build -Doptimize=ReleaseFast

debug:
	cd zig && zig build

test:
	cd go && go test ./...
	cd zig && zig build test

validate: all
	@echo "=== Validating Go JSON output against schema ==="
	./go/machinestate --format json | uvx check-jsonschema --schemafile schema/report.schema.json -
	@echo "=== Validating Zig JSON output against schema ==="
	./zig/zig-out/bin/machinestate --format json | uvx check-jsonschema --schemafile schema/report.schema.json -
	@echo "=== Both implementations pass schema validation ==="

validate-mcp: all
	@./scripts/test-mcp.sh

benchmark: all
	@./scripts/benchmark.sh

clean:
	rm -f go/machinestate
	rm -rf zig/zig-out zig/.zig-cache

install: all
	sudo cp go/machinestate /usr/local/bin/machinestate-go
	sudo cp zig/zig-out/bin/machinestate /usr/local/bin/machinestate-zig
	sudo ln -sf /usr/local/bin/machinestate-go /usr/local/bin/machinestate

# Cross-compilation targets

# AMD64 builds (GNU libc)
build-amd64:
	cd go && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o machinestate-linux-amd64 .
	cd zig && zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu

# ARM64 builds (GNU libc)
build-arm64:
	cd go && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o machinestate-linux-arm64 .
	cd zig && zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu

# AMD64 builds (musl - static)
build-amd64-musl:
	cd go && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o machinestate-linux-amd64-static .
	cd zig && zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl

# ARM64 builds (musl - static)
build-arm64-musl:
	cd go && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o machinestate-linux-arm64-static .
	cd zig && zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-musl

# Build all architectures (GNU + musl)
build-all-arch: build-amd64 build-arm64 build-amd64-musl build-arm64-musl
	@echo "Built binaries for amd64 and arm64 (GNU and musl)"

# Release package (all architectures)
release: build-all-arch
	mkdir -p dist
	cp go/machinestate-linux-amd64 dist/machinestate-go-linux-amd64
	cp go/machinestate-linux-arm64 dist/machinestate-go-linux-arm64
	cp go/machinestate-linux-amd64-static dist/machinestate-go-linux-amd64-static
	cp go/machinestate-linux-arm64-static dist/machinestate-go-linux-arm64-static
	@echo "Release binaries in dist/"

# Docker targets
docker-build-go:
	docker build -f Dockerfile.go -t machinestate:go .

docker-build-zig:
	docker build -f Dockerfile.zig -t machinestate:zig .

docker-build: docker-build-go docker-build-zig

docker-run-go:
	docker run -d --name machinestate-go \
		-p 8080:8080 \
		-v /proc:/host/proc:ro \
		-v /sys:/host/sys:ro \
		machinestate:go

docker-run-zig:
	docker run -d --name machinestate-zig \
		-p 8081:8080 \
		-v /proc:/host/proc:ro \
		-v /sys:/host/sys:ro \
		machinestate:zig

docker-stop-go:
	docker stop machinestate-go && docker rm machinestate-go

docker-stop-zig:
	docker stop machinestate-zig && docker rm machinestate-zig

docker-compose-up:
	docker-compose up -d

docker-compose-down:
	docker-compose down

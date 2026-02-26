# Makefile for building the custom build tool and packaging if required

BINARY_NAME=dev
SOURCE_DIR=cmd/dev

# Build for multiple platforms
build-all: build build-linux build-darwin build-windows

# Ensure dev binary exists (builds if missing)
ensure-dev:
	@if [ ! -f "./$(BINARY_NAME)" ]; then \
		echo "Building $(BINARY_NAME) for current platform..."; \
		go build -o $(BINARY_NAME) ./$(SOURCE_DIR); \
	fi

# Build for current platform
build:
	@echo "Building $(BINARY_NAME) for current platform..."
	go build -o $(BINARY_NAME) ./$(SOURCE_DIR)

build-linux:
	@echo "Building $(BINARY_NAME) for Linux..."
	GOOS=linux GOARCH=amd64 go build -o $(BINARY_NAME)-linux-amd64 ./$(SOURCE_DIR)

build-darwin:
	@echo "Building $(BINARY_NAME) for macOS..."
	GOOS=darwin GOARCH=amd64 go build -o $(BINARY_NAME)-darwin-amd64 ./$(SOURCE_DIR)
	GOOS=darwin GOARCH=arm64 go build -o $(BINARY_NAME)-darwin-arm64 ./$(SOURCE_DIR)

build-windows:
	@echo "Building $(BINARY_NAME) for Windows..."
	GOOS=windows GOARCH=amd64 go build -o $(BINARY_NAME)-windows-amd64.exe ./$(SOURCE_DIR)

# Clean build artifacts
clean:
	@echo "Cleaning $(BINARY_NAME) artifacts..."
	rm $(BINARY_NAME)*

# Install dependencies
deps:
	@echo "Installing dependencies..."
	go mod tidy
	go mod download

# Generate changelog
changelog: ensure-dev
	@echo "Generating changelog..."
	@./dev changelog generate

# Generate changelog for next version
changelog-next: ensure-dev
	@echo "Generating changelog for next version..."
	@read -p "Next version (e.g., v1.2.0): " version; \
	./dev changelog generate --next $$version

# Validate commit messages follow conventional commits
validate-commits:
	@echo "Validating commit messages..."
	@git log --oneline origin/main..HEAD 2>/dev/null | while read line; do \
		if ! echo "$$line" | grep -qE "^[a-f0-9]+ (feat|fix|docs|refactor|test|perf|build|ci|chore)(\(.+\))?:"; then \
			echo "❌ Invalid commit: $$line"; \
			echo "   Commits must follow format: <type>[scope]: <description>"; \
			exit 1; \
		fi; \
	done || true
	@echo "✅ All commits follow conventional format"

# Setup changelog tooling (git-chglog)
setup-changelog: ensure-dev
	@echo "Setting up changelog tooling..."
	@./dev changelog init

# Build binaries for packaging (most common use case)
build-arm64: ensure-dev
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make build-binaries VERSION=x.y.z"; \
		exit 1; \
	fi
	@echo "Building binaries for Linux (arm64)..."
	@./dev build --os linux --arch amd64 --cross-os linux --cross-arch arm64 --version $(VERSION)

# Debian packaging targets
# Note: Build binaries first with: make build-binaries VERSION=x.y.z
deb-all: ensure-dev
	@echo "Building Debian packages for all architectures..."
	@echo "Note: Binaries must be built first with: ./dev build --os linux --arch amd64 --cross-os linux --cross-arch arm64 --version 0.1.0"
	@read -p "Version (e.g., 0.1.0): " version; \
	read -p "Debian version (buster/bookworm/trixie): " debian_ver; \
	for arch in amd64 arm64 armhf; do \
		echo "Building package for $$arch..."; \
		./dev package --version $$version --arch $$arch --debian-version $$debian_ver || true; \
	done

deb-amd64: ensure-dev
	@echo "Building Debian package for amd64 (bookworm)..."
	@read -p "Version (e.g., 0.1.0): " version; \
	./dev package --version $$version --arch amd64 --debian-version bookworm

deb-arm64: ensure-dev
	@echo "Building Debian package for arm64 (bookworm)..."
	@read -p "Version (e.g., 0.1.0): " version; \
	./dev package --version $$version --arch arm64 --debian-version bookworm

deb-armhf: ensure-dev
	@echo "Building Debian package for armhf (bookworm)..."
	@read -p "Version (e.g., 0.1.0): " version; \
	./dev package --version $$version --arch armhf --debian-version bookworm

deb-custom: ensure-dev
	@echo "Building custom Debian package..."
	@read -p "Version (e.g., 0.1.0): " version; \
	read -p "Architecture (amd64/arm64/armhf): " arch; \
	read -p "Debian version (buster/bookworm/trixie): " debian_ver; \
	./dev package --version $$version --arch $$arch --debian-version $$debian_ver

# Build Debian package for arm64 on Bookworm (most common packaging use case)
deb-arm64-bookworm: ensure-dev
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make deb-arm64-bookworm VERSION=x.y.z"; \
		exit 1; \
	fi
	@echo "Building Debian package for arm64 (Bookworm)..."
	@./dev package --version $(VERSION) --arch arm64 --debian-version bookworm

# Build Debian package for arm64 on Trixie (most common packaging use case)
deb-arm64-trixie: ensure-dev
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make deb-arm64-trixie VERSION=x.y.z"; \
		exit 1; \
	fi
	@echo "Building Debian package for arm64 (Trixie)..."
	@./dev package --version $(VERSION) --arch arm64 --debian-version trixie

deb-clean:
	@echo "Cleaning Debian build artifacts..."
	@rm -rf build/deb dist/deb
	@echo "✅ Debian build artifacts cleaned"

# CI/CD targets using Dagger
# Check if Dagger is installed
check-dagger:
	@if ! command -v dagger >/dev/null 2>&1; then \
		echo "❌ Dagger CLI is not installed."; \
		echo ""; \
		echo "Install it with:"; \
		echo "  curl -L https://dl.dagger.io/dagger/install.sh | sh"; \
		echo "  brew install dagger/tap/dagger"; \
		echo ""; \
		echo "Or visit: https://docs.dagger.io/install"; \
		exit 1; \
	fi
	@echo "✅ Dagger CLI found: $$(dagger version | head -n1)"

# Run linter via Dagger
ci-lint: check-dagger
	@echo "Running linter via Dagger..."
	@dagger call -m ./ci lint --github-token=env://GITHUB_TOKEN

# Run tests via Dagger
ci-test: check-dagger
	@echo "Running tests via Dagger..."
	@dagger call -m ./ci test --github-token=env://GITHUB_TOKEN

# Run both lint and test
ci-check: ci-lint ci-test
	@echo "✅ All CI checks passed"

# Build binary for a specific platform via Dagger
ci-build: check-dagger
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make ci-build VERSION=x.y.z PLATFORM=linux/amd64"; \
		exit 1; \
	fi
	@if [ -z "$(PLATFORM)" ]; then \
		echo "Error: PLATFORM is required. Usage: make ci-build VERSION=x.y.z PLATFORM=linux/amd64"; \
		echo "Supported platforms: linux/amd64, linux/arm64"; \
		exit 1; \
	fi
	@echo "Building binary via Dagger for $(PLATFORM)..."
	@dagger call -m ./ci build --version=$(VERSION) --platform=$(PLATFORM) --github-token=env://GITHUB_TOKEN

# Build Debian package via Dagger
ci-package: check-dagger
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make ci-package VERSION=x.y.z"; \
		exit 1; \
	fi
	@echo "Building Debian package via Dagger (arm64/trixie)..."
	@dagger call -m ./ci package --github-token=env://GITHUB_TOKEN \
		--version=$(VERSION) \
		--arch=arm64 \
		--debian-version=trixie \
		--binary=./dist/rackmonitor-linux-arm64

# Show help
help:
	@echo "Available targets:"
	@echo ""
	@echo "Build Tool:"
	@echo "  build            - Build dev tool for current platform"
	@echo "  build-all        - Build dev tool for all platforms"
	@echo "  build-linux      - Build dev tool for Linux"
	@echo "  build-darwin     - Build dev tool for macOS"
	@echo "  build-windows    - Build dev tool for Windows"
	@echo "  clean            - Clean build artifacts"
	@echo "  deps             - Install dependencies"
	@echo ""
	@echo "CI/CD (Dagger):"
	@echo "  ci-lint          - Run linter via Dagger"
	@echo "  ci-test          - Run tests via Dagger"
	@echo "  ci-check         - Run both lint and test"
	@echo "  ci-build         - Build binary via Dagger (requires VERSION=x.y.z PLATFORM=linux/amd64|linux/arm64)"
	@echo "  ci-package       - Build Debian package via Dagger (requires VERSION=x.y.z, builds arm64/trixie)"
	@echo ""
	@echo "Debian Packaging:"
	@echo "  deb-all          - Build .deb packages for all architectures (requires binaries in dist/)"
	@echo "  deb-amd64        - Build .deb for amd64 (Debian Bookworm)"
	@echo "  deb-arm64        - Build .deb for arm64 (Debian Bookworm)"
	@echo "  deb-armhf        - Build .deb for armhf (Debian Bookworm)"
	@echo "  deb-custom       - Build .deb with custom version/arch/debian version"
	@echo "  deb-arm64-trixie - Build .deb for arm64 (Debian Trixie) - requires VERSION=x.y.z"
	@echo "  deb-clean        - Clean Debian build artifacts"
	@echo ""
	@echo "Documentation:"
	@echo "  changelog        - Generate changelog from git history"
	@echo "  changelog-next   - Generate changelog for next version"
	@echo "  validate-commits - Validate commit messages"
	@echo "  setup-changelog  - Setup changelog tooling"
	@echo "  help             - Show this help"

.PHONY: build build-all build-linux build-darwin build-windows clean deps ensure-dev build-binaries changelog changelog-next validate-commits setup-changelog deb-all deb-amd64 deb-arm64 deb-armhf deb-custom deb-arm64-trixie deb-clean help check-dagger ci-lint ci-test ci-check ci-build ci-package
.PHONY: build test run clean commit push help

SWIFT := swift
PRODUCT_NAME := MPDControls
BUILD_DIR := .build

help:
	@echo "Mac MPD Controls - Build Commands"
	@echo ""
	@echo "  make build   - Build the project"
	@echo "  make test    - Run tests"
	@echo "  make run     - Run the application"
	@echo "  make clean   - Clean build artifacts"
	@echo "  make commit  - Commit and push changes"
	@echo ""

build:
	@echo "Building $(PRODUCT_NAME)..."
	@$(SWIFT) build

test:
	@echo "Running tests..."
	@$(SWIFT) test

run:
	@echo "Running $(PRODUCT_NAME)..."
	@$(SWIFT) run

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@$(SWIFT) package clean

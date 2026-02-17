APP_NAME := Sub Buddy
BUNDLE_NAME := Sub Buddy.app
SCHEME := SubBuddy
PROJECT := SubBuddy.xcodeproj
BUILD_DIR := build
INSTALL_DIR := /Applications
DMG_NAME := SubBuddy-$(shell date +%Y%m%d).dmg
VERSION := $(shell grep MARKETING_VERSION project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')

.PHONY: all generate build install uninstall dmg dist prepublish clean run help

all: build

# Generate the Xcode project from project.yml (requires xcodegen)
generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing xcodegen..."; brew install xcodegen; }
	xcodegen generate

# Build the app (Release configuration)
build: generate
	@echo "Building $(APP_NAME) v$(VERSION)..."
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" \
		-quiet
	@echo "Build succeeded: $(BUILD_DIR)/Build/Products/Release/$(BUNDLE_NAME)"

# Build debug version
debug: generate
	@echo "Building $(APP_NAME) (debug)..."
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" \
		-quiet
	@echo "Debug build succeeded."

# Install to /Applications
install: build
	@echo "Installing $(APP_NAME) to $(INSTALL_DIR)..."
	@if [ -d "$(INSTALL_DIR)/$(BUNDLE_NAME)" ]; then \
		echo "Removing previous installation..."; \
		rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"; \
	fi
	cp -R "$(BUILD_DIR)/Build/Products/Release/$(BUNDLE_NAME)" "$(INSTALL_DIR)/"
	@echo "$(APP_NAME) installed to $(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo "You can now launch it from Spotlight or run: open '$(INSTALL_DIR)/$(BUNDLE_NAME)'"

# Uninstall from /Applications
uninstall:
	@echo "Removing $(APP_NAME) from $(INSTALL_DIR)..."
	@if [ -d "$(INSTALL_DIR)/$(BUNDLE_NAME)" ]; then \
		rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"; \
		echo "$(APP_NAME) uninstalled."; \
	else \
		echo "$(APP_NAME) is not installed."; \
	fi

# Create a DMG installer
dmg: build
	@echo "Creating DMG..."
	@mkdir -p "$(BUILD_DIR)/dmg-staging"
	@rm -rf "$(BUILD_DIR)/dmg-staging/$(BUNDLE_NAME)"
	@cp -R "$(BUILD_DIR)/Build/Products/Release/$(BUNDLE_NAME)" "$(BUILD_DIR)/dmg-staging/"
	@ln -sf /Applications "$(BUILD_DIR)/dmg-staging/Applications"
	@rm -f "$(BUILD_DIR)/$(DMG_NAME)"
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(BUILD_DIR)/dmg-staging" \
		-ov \
		-format UDZO \
		"$(BUILD_DIR)/$(DMG_NAME)"
	@rm -rf "$(BUILD_DIR)/dmg-staging"
	@echo "DMG created: $(BUILD_DIR)/$(DMG_NAME)"

# Prepare distribution for npm (copies .app to dist/)
dist: build
	@echo "Preparing distribution..."
	@mkdir -p dist
	@rm -rf "dist/$(BUNDLE_NAME)"
	@cp -R "$(BUILD_DIR)/Build/Products/Release/$(BUNDLE_NAME)" dist/
	@echo "Distribution ready: dist/$(BUNDLE_NAME)"

# Alias for npm publish preparation
prepublish: dist
	@echo "Ready to publish. Run: npm publish"

# Build and run immediately
run: build
	@echo "Launching $(APP_NAME)..."
	@open "$(BUILD_DIR)/Build/Products/Release/$(BUNDLE_NAME)"

# Clean build artefacts
clean:
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean -quiet 2>/dev/null || true
	@echo "Clean complete."

# Show available commands
help:
	@echo ""
	@echo "  Sub Buddy — macOS menu bar app for RevenueCat metrics"
	@echo ""
	@echo "  Usage:"
	@echo "    make              Build the app (Release)"
	@echo "    make debug        Build the app (Debug)"
	@echo "    make install      Build and install to /Applications"
	@echo "    make uninstall    Remove from /Applications"
	@echo "    make dmg          Create a DMG installer"
	@echo "    make dist         Prepare .app for npm publish"
	@echo "    make run          Build and launch"
	@echo "    make clean        Remove build artefacts"
	@echo "    make generate     Regenerate Xcode project"
	@echo "    make help         Show this message"
	@echo ""

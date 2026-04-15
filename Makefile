APP         := Sandcage
BUNDLE_NAME := $(APP).app
BUILD_DIR   := .build/release
INSTALL_DIR := /Applications

.PHONY: all build bundle install uninstall clean

## Default: build a release .app bundle in the project directory
all: bundle

## Debug build (no .app bundle, fast iteration)
build:
	swift build

## Release build → Sandcage.app
bundle:
	swift build -c release
	@rm -rf $(BUNDLE_NAME)
	@mkdir -p $(BUNDLE_NAME)/Contents/MacOS
	@mkdir -p $(BUNDLE_NAME)/Contents/Resources
	cp $(BUILD_DIR)/$(APP)            $(BUNDLE_NAME)/Contents/MacOS/$(APP)
	cp Info.plist                     $(BUNDLE_NAME)/Contents/Info.plist
	@# Copy SPM resource bundle (profiles) so Bundle.module resolves correctly
	@if [ -d "$(BUILD_DIR)/$(APP)_$(APP).bundle" ]; then \
	    cp -r "$(BUILD_DIR)/$(APP)_$(APP).bundle" \
	          "$(BUNDLE_NAME)/Contents/MacOS/$(APP)_$(APP).bundle"; \
	fi
	@echo "→ $(BUNDLE_NAME) ready."

## Build and install to /Applications
install: bundle
	@echo "Installing to $(INSTALL_DIR)…"
	@rm -rf $(INSTALL_DIR)/$(BUNDLE_NAME)
	cp -r $(BUNDLE_NAME) $(INSTALL_DIR)/$(BUNDLE_NAME)
	@echo "✓ Installed. Launch Sandcage from Launchpad or open $(INSTALL_DIR)/$(BUNDLE_NAME)"

## Remove from /Applications
uninstall:
	@rm -rf $(INSTALL_DIR)/$(BUNDLE_NAME)
	@echo "✓ Uninstalled $(APP) from $(INSTALL_DIR)."

## Remove build artifacts and local .app bundle
clean:
	swift package clean
	rm -rf $(BUNDLE_NAME)

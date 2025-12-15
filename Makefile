BUILD_PATH = .build/action
BUNDLE_NAME = Swift Evolution.lbaction
BUNDLE_PATH = $(BUILD_PATH)/$(BUNDLE_NAME)/Contents
SCRIPTS_PATH = $(BUNDLE_PATH)/Scripts
RESOURCES_PATH = $(BUNDLE_PATH)/Resources
INFO_PLIST = $(BUNDLE_PATH)/Info.plist
ICON = $(RESOURCES_PATH)/Swift.png
INSTALL_PATH = $(HOME)/Library/Application Support/LaunchBar/Actions
RELEASE_PATH = .build/release-bundle
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0")

.PHONY: all build clean install release

all: build

build: main
	@echo "Assembling LaunchBar action bundle..."
	rm -rf "$(BUNDLE_NAME)"
	mkdir -p "$(SCRIPTS_PATH)"
	cp .build/release/main "$(SCRIPTS_PATH)"
	mkdir -p "$(RESOURCES_PATH)"
	cp icon.png "$(RESOURCES_PATH)"
	cp Info.plist "$(INFO_PLIST)"
	@echo "LaunchBar action built successfully at: $(BUNDLE_NAME)"

main:
	@echo "Building main executable with Swift Package Manager..."
	swift build -c release

clean:
	swift package clean
	rm -rf .build

install: build
	@echo "Installing to $(INSTALL_PATH)"
	-rm -r "$(INSTALL_PATH)/$(BUNDLE_NAME)" 2>/dev/null
	cp -Rp "$(BUILD_PATH)/$(BUNDLE_NAME)" "$(INSTALL_PATH)"
	@echo "Installed successfully. Restart LaunchBar or rescan actions to use."

release: build
	@echo "Creating release $(VERSION)..."
	@if ! command -v gh &> /dev/null; then \
		echo "Error: GitHub CLI (gh) is not installed. Install it with 'brew install gh'"; \
		exit 1; \
	fi
	@if [ -z "$$(git tag -l $(VERSION))" ]; then \
		echo "Error: Tag $(VERSION) does not exist. Create it with 'git tag $(VERSION)'"; \
		exit 1; \
	fi
	@echo "Packaging release bundle..."
	mkdir -p "$(RELEASE_PATH)"
	cd "$(BUILD_PATH)" && zip -r "../../$(RELEASE_PATH)/$(BUNDLE_NAME).zip" "$(BUNDLE_NAME)"
	@echo "Creating GitHub release..."
	gh release create $(VERSION) \
		"$(RELEASE_PATH)/$(BUNDLE_NAME).zip" \
		--title "$(VERSION)" \
		--generate-notes
	@echo "Release $(VERSION) published successfully!"

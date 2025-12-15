BUILD_PATH = .build/action
BUNDLE_NAME = Swift Evolution.lbaction
BUNDLE_ROOT = $(BUILD_PATH)/$(BUNDLE_NAME)
BUNDLE_CONTENTS = $(BUNDLE_ROOT)/Contents
SCRIPTS_PATH = $(BUNDLE_CONTENTS)/Scripts
RESOURCES_PATH = $(BUNDLE_CONTENTS)/Resources
INSTALL_PATH = $(HOME)/Library/Application Support/LaunchBar/Actions
RELEASE_PACKAGE = $(BUILD_PATH)/$(BUNDLE_NAME).zip
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning -v | awk -F\" '/\"/ {print $$2}')
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0")

.PHONY: all build clean install release sign

all: build

build: main
	@echo "$(SIGN_IDENTITY)"
	@echo "Assembling LaunchBar action bundle..."
	-rm -r "$(BUNDLE_ROOT)" 2>/dev/null
	mkdir -p "$(SCRIPTS_PATH)"
	cp .build/release/main "$(SCRIPTS_PATH)"
	mkdir -p "$(RESOURCES_PATH)"
	cp icon.png "$(RESOURCES_PATH)"
	cp Info.plist "$(BUNDLE_CONTENTS)"
	@echo "LaunchBar action built successfully at: $(BUNDLE_ROOT)"

main:
	@echo "Building main executable with Swift Package Manager..."
	swift build -c release

clean:
	swift package clean
	rm -r .build

install: build sign
	@echo "Installing to $(INSTALL_PATH)"
	-rm -r "$(INSTALL_PATH)/$(BUNDLE_NAME)" 2>/dev/null
	cp -Rp "$(BUNDLE_ROOT)" "$(INSTALL_PATH)"
	@echo "Installed successfully. Restart LaunchBar or rescan actions to use."

"$(RELEASE_PACKAGE)": build
	@echo "Packaging release bundle..."
	cd "$(BUILD_PATH)" && zip -r "$(RELEASE_PACKAGE)" "$(BUNDLE_NAME)"

release: build sign "$(RELEASE_PACKAGE)"
	@echo "Creating release $(VERSION)..."
	@if ! command -v gh &> /dev/null; then \
		echo "Error: GitHub CLI (gh) is not installed. Install it with 'brew install gh'"; \
		exit 1; \
	fi
	@if [ -z "$$(git tag -l $(VERSION))" ]; then \
		echo "Error: Tag $(VERSION) does not exist. Create it with 'git tag $(VERSION)'"; \
		exit 1; \
	fi
	@echo "Creating GitHub release..."
	gh release create $(VERSION) \
		"$(RELEASE_PACKAGE)" \
		--title "$(VERSION)" \
		--generate-notes
	@echo "Release $(VERSION) published successfully!"

sign: build
	@test -n "$(SIGN_IDENTITY)" || (echo "Set SIGN_IDENTITY to your signing identity (e.g. 'Developer ID Application: Name (TEAMID)' or 'Apple Development: Name (TEAMID)')"; exit 1)
	@echo "Codesigning bundle with $(SIGN_IDENTITY)"
	codesign --force --deep --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$(BUNDLE_ROOT)"
	codesign --verify --deep --strict --verbose=2 "$(BUNDLE_ROOT)"
	@echo "Codesign complete."

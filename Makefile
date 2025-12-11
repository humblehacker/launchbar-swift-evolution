BUILD_PATH = .build/action
BUNDLE_NAME = Swift Evolution.lbaction
BUNDLE_PATH = $(BUILD_PATH)/$(BUNDLE_NAME)/Contents
SCRIPTS_PATH = $(BUNDLE_PATH)/Scripts
RESOURCES_PATH = $(BUNDLE_PATH)/Resources
INFO_PLIST = $(BUNDLE_PATH)/Info.plist
ICON = $(RESOURCES_PATH)/Swift.png
INSTALL_PATH = $(HOME)/Library/Application Support/LaunchBar/Actions

.PHONY: all build clean install

all: build

build:
	@echo "Building se-lookup executable with Swift Package Manager..."
	swift build -c release
	@echo "Assembling LaunchBar action bundle..."
	rm -rf "$(BUNDLE_NAME)"
	mkdir -p "$(SCRIPTS_PATH)"
	cp .build/release/main "$(SCRIPTS_PATH)"
	mkdir -p "$(RESOURCES_PATH)"
	cp icon.png "$(RESOURCES_PATH)"
	cp Info.plist "$(INFO_PLIST)"
	@echo "LaunchBar action built successfully at: $(BUNDLE_NAME)"

clean:
	swift package clean
	rm -rf .build

install: build
	@echo "Installing to $(INSTALL_PATH)"
	-rm -r "$(INSTALL_PATH)/$(BUNDLE_NAME)" 2>/dev/null
	cp -Rp "$(BUILD_PATH)/$(BUNDLE_NAME)" "$(INSTALL_PATH)"
	@echo "Installed successfully. Restart LaunchBar or rescan actions to use."

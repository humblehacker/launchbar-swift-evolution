ACTION_BUILD_PATH = .build/action
MAIN_EXECUTABLE = .build/apple/Products/Release/main
BUNDLE_NAME = SwiftEvolution.lbaction
BUNDLE_ROOT = $(ACTION_BUILD_PATH)/$(BUNDLE_NAME)
PKG_ROOT = $(ACTION_BUILD_PATH)/pkg-root
PKG_SCRIPTS = $(ACTION_BUILD_PATH)/pkg-scripts
BUNDLE_CONTENTS = $(BUNDLE_ROOT)/Contents
SCRIPTS_PATH = $(BUNDLE_CONTENTS)/Scripts
RESOURCES_PATH = $(BUNDLE_CONTENTS)/Resources
DMG_NAME = Swift-Evolution.dmg
PKG_NAME = Swift-Evolution.pkg
INSTALL_PATH = $(HOME)/Library/Application Support/LaunchBar/Actions
DMG_PATH = $(ACTION_BUILD_PATH)/$(DMG_NAME)
PKG_PATH = $(ACTION_BUILD_PATH)/$(PKG_NAME)
UNSIGNED_PKG = $(PKG_PATH).unsigned
PKG_STAGE_ROOT = /tmp/SwiftEvolution-staging
NOTARY_SUBMISSION = $(ACTION_BUILD_PATH)/notarization.json
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning -v | awk -F\" '/Developer ID Application/ {print $$2; exit}')
PKG_SIGN_IDENTITY ?= $(shell security find-identity -v | awk -F\" '/Developer ID Installer/ {print $$2; exit}')
NOTARY_PROFILE ?=
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0")
SIGNED_BUNDLE := $(BUNDLE_ROOT).signed
INSTALL_STAMP := $(ACTION_BUILD_PATH)/install.stamp

.ONESHELL:

.PHONY: all clean release sign-dmg sign-pkg pkg notarize-dmg notarize-pkg

all: bundle

clean:
	swift package clean
	rm -r .build

#install: "$(INSTALL_PATH)/$(BUNDLE_NAME)"
#"$(INSTALL_PATH)/$(BUNDLE_NAME)": $(SIGNED_BUNDLE)
#	@echo "Installing to $(INSTALL_PATH)"
#	-rm -r "$(INSTALL_PATH)/$(BUNDLE_NAME)" 2>/dev/null
#	mkdir -p "$(INSTALL_PATH)"
#	cp -R "$(BUNDLE_ROOT)" "$(INSTALL_PATH)"
#	touch "$(INSTALL_PATH)/$(BUNDLE_NAME)"
#	@echo "Installed successfully. Restart LaunchBar or rescan actions to use."

install: $(INSTALL_STAMP)
$(INSTALL_STAMP): $(SIGNED_BUNDLE)
	@echo "Installing to $(INSTALL_PATH)"
	-rm -r "$(INSTALL_PATH)/$(BUNDLE_NAME)" 2>/dev/null
	mkdir -p "$(INSTALL_PATH)"
	cp -R "$(BUNDLE_ROOT)" "$(INSTALL_PATH)"
	touch "$@"
	@echo "Installed successfully. Restart LaunchBar or rescan actions to use."

sign-bundle: $(SIGNED_BUNDLE)
$(SIGNED_BUNDLE): $(BUNDLE_ROOT)
	@test -n "$(SIGN_IDENTITY)" || (echo "Set SIGN_IDENTITY to your 'Developer ID Application' signing identity"; exit 1)
	@echo "Codesigning bundle with $(SIGN_IDENTITY)"
	codesign --sign "$(SIGN_IDENTITY)" --force --options runtime --timestamp "$(BUNDLE_ROOT)/Contents/Scripts/main"
	codesign --sign "$(SIGN_IDENTITY)" --force --options runtime --timestamp "$(BUNDLE_ROOT)"
	codesign --verify --strict --verbose=2 "$(BUNDLE_ROOT)"
	touch "$@"
	@echo "Codesign complete."

bundle: $(BUNDLE_ROOT)
$(BUNDLE_ROOT): $(MAIN_EXECUTABLE) icon.png Info.plist
	@echo "$(SIGN_IDENTITY)"
	@echo "Assembling LaunchBar action bundle..."
	-rm -r "$(BUNDLE_ROOT)" 2>/dev/null
	mkdir -p "$(SCRIPTS_PATH)"
	cp $(MAIN_EXECUTABLE) "$(SCRIPTS_PATH)"
	mkdir -p "$(RESOURCES_PATH)"
	cp icon.png "$(RESOURCES_PATH)"
	cp Info.plist "$(BUNDLE_CONTENTS)"
	@echo "LaunchBar action built successfully at: $(BUNDLE_ROOT)"

main: $(MAIN_EXECUTABLE)
$(MAIN_EXECUTABLE): main.swift Package.swift
	@echo "Building main executable with Swift Package Manager..."
	swift build -c release --arch arm64 --arch x86_64

$(DMG_PATH): sign-bundle
	@echo "Creating DMG at $(DMG_PATH)..."
	@rm -f "$(DMG_PATH)"
	mkdir -p "$(ACTION_BUILD_PATH)/dmg-root"
	@rm -rf "$(ACTION_BUILD_PATH)/dmg-root/$(BUNDLE_NAME)"
	cp -Rp "$(BUNDLE_ROOT)" "$(ACTION_BUILD_PATH)/dmg-root/"
	hdiutil create -fs HFS+ -format UDZO -volname "Swift Evolution" -srcfolder "$(ACTION_BUILD_PATH)/dmg-root" "$(DMG_PATH)"
	@echo "DMG created: $(DMG_PATH)"

dmg: $(DMG_PATH)

release: notarize-dmg notarize-pkg
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
		"$(DMG_PATH)" \
		"$(PKG_PATH)" \
		--title "$(VERSION)" \
		--generate-notes
	@echo "Release $(VERSION) published successfully!"

pkg: sign-bundle
	@echo "Creating PKG at $(PKG_PATH)..."
	@rm -f "$(PKG_PATH)" "$(UNSIGNED_PKG)"
	@rm -rf "$(PKG_ROOT)" "$(PKG_SCRIPTS)"
	mkdir -p "$(PKG_ROOT)/Library/Application Support/LaunchBar/Actions"
	mkdir -p "$(PKG_SCRIPTS)"
	cp -Rp "$(BUNDLE_ROOT)" "$(PKG_ROOT)/Library/Application Support/LaunchBar/Actions/"
	sed -e "s|@BUNDLE_NAME@|$(BUNDLE_NAME)|g" \
		-e "s|@PKG_STAGE_ROOT@|$(PKG_STAGE_ROOT)|g" \
		packaging/postinstall.sh > "$(PKG_SCRIPTS)/postinstall"
	chmod +x "$(PKG_SCRIPTS)/postinstall"
	pkgbuild \
		--root "$(PKG_ROOT)" \
		--identifier com.humblehacker.LaunchBar.action.SwiftEvolution \
		--version "$(VERSION)" \
		--install-location "$(PKG_STAGE_ROOT)" \
		--scripts "$(PKG_SCRIPTS)" \
		"$(UNSIGNED_PKG)"
	@echo "Unsigned PKG created: $(UNSIGNED_PKG)"

sign-dmg: dmg
	@test -n "$(SIGN_IDENTITY)" || (echo "Set SIGN_IDENTITY to your 'Developer ID Application' signing identity"; exit 1)
	@echo "Signing DMG with $(SIGN_IDENTITY)..."
	codesign --sign "$(SIGN_IDENTITY)" --force "$(DMG_PATH)"
	codesign --verify --verbose=2 "$(DMG_PATH)"
	@echo "DMG signed."

sign-pkg: pkg
	@test -n "$(PKG_SIGN_IDENTITY)" || (echo "Set PKG_SIGN_IDENTITY to your 'Developer ID Installer' signing identity"; exit 1)
	@test -f "$(UNSIGNED_PKG)" || (echo "Unsigned PKG not found at $(UNSIGNED_PKG)"; exit 1)
	@echo "Signing PKG with $(PKG_SIGN_IDENTITY)..."
	productsign --sign "$(PKG_SIGN_IDENTITY)" --force "$(UNSIGNED_PKG)" "$(PKG_PATH)"
	pkgutil --check-signature "$(PKG_PATH)"
	@echo "PKG signed: $(PKG_PATH)"

notarize-dmg: sign-dmg
	@test -n "$(NOTARY_PROFILE)" || (echo "Set NOTARY_PROFILE to your notarytool keychain profile (stored via 'xcrun notarytool store-credentials')"; exit 1)
	@echo "Submitting $(DMG_PATH) for notarization with profile $(NOTARY_PROFILE)..."
	xcrun notarytool submit "$(DMG_PATH)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@echo "Stapling ticket to DMG..."
	xcrun stapler staple "$(DMG_PATH)"
	@echo "Validating stapled DMG..."
	xcrun stapler validate "$(DMG_PATH)"
	spctl --assess --type open --context context:primary-signature -vv "$(DMG_PATH)"
	@echo "Notarization complete. Distribute the DMG."

notarize-pkg: sign-pkg
	@test -n "$(NOTARY_PROFILE)" || (echo "Set NOTARY_PROFILE to your notarytool keychain profile (stored via 'xcrun notarytool store-credentials')"; exit 1)
	@echo "Submitting $(PKG_PATH) for notarization with profile $(NOTARY_PROFILE)..."
	xcrun notarytool submit "$(PKG_PATH)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@echo "Stapling ticket to PKG..."
	xcrun stapler staple "$(PKG_PATH)"
	@echo "Validating stapled PKG..."
	xcrun stapler validate "$(PKG_PATH)"
	pkgutil --check-signature "$(PKG_PATH)"
	spctl --assess --type install -vv "$(PKG_PATH)"
	@echo "Notarization complete. Distribute the PKG."

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Paths and names

build_root := ".justbuild"
action_build_path := build_root + "/action"
main_executable := build_root + "/apple/Products/Release/main"
bundle_name := "SwiftEvolution.lbaction"
bundle_root := action_build_path + "/" + bundle_name
pkg_root := action_build_path + "/pkg-root"
pkg_scripts := action_build_path + "/pkg-scripts"
bundle_contents := bundle_root + "/Contents"
scripts_path := bundle_contents + "/Scripts"
resources_path := bundle_contents + "/Resources"
dmg_name := "Swift-Evolution.dmg"
pkg_name := "Swift-Evolution.pkg"
install_path := env_var_or_default("INSTALL_PATH", "$HOME/Library/Application Support/LaunchBar/Actions")
dmg_path := action_build_path + "/" + dmg_name
pkg_path := action_build_path + "/" + pkg_name
unsigned_pkg := pkg_path + ".unsigned"
pkg_stage_root := "/tmp/SwiftEvolution-staging"
notary_submission := action_build_path + "/notarization.json"

# Identities and versions

sign_identity := `security find-identity -p codesigning -v | awk -F\" '/Developer ID Application/ {print $2; exit}'`
pkg_sign_identity := `security find-identity -v | awk -F\" '/Developer ID Installer/ {print $2; exit}'`
notary_profile := env_var_or_default("NOTARY_PROFILE", "")
version := `git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0"`

# Stamps

signed_bundle := bundle_root + ".signed"
install_stamp := action_build_path + "/install.stamp"
signed_dmg := dmg_path + ".signed"
signed_pkg := pkg_path + ".signed"
notarized_dmg := dmg_path + ".notarized"
notarized_pkg := pkg_path + ".notarized"

alias default := bundle

clean:
    swift package clean --build-path {{ build_root }}
    rm -rf {{ build_root }}

main:
    if [ ! -e "{{ main_executable }}" ] || [ -n "$(find main.swift Package.swift -newer "{{ main_executable }}" -print -quit)" ]; then \
      echo "Building main executable with Swift Package Manager..."; \
      swift build -c release --arch arm64 --arch x86_64 --build-path {{ build_root }}; \
    else \
      echo "main up to date at {{ main_executable }}"; \
    fi

bundle: main
    if [ ! -e "{{ bundle_root }}" ] || [ -n "$(find {{ main_executable }} icon.png Info.plist -newer "{{ bundle_root }}" -print -quit)" ]; then \
      echo "{{ sign_identity }}"; \
      echo "Assembling LaunchBar action bundle..."; \
      rm -rf "{{ bundle_root }}"; \
      mkdir -p "{{ scripts_path }}"; \
      cp "{{ main_executable }}" "{{ scripts_path }}"; \
      mkdir -p "{{ resources_path }}"; \
      cp icon.png "{{ resources_path }}"; \
      cp Info.plist "{{ bundle_contents }}"; \
      echo "LaunchBar action built successfully at: {{ bundle_root }}"; \
    else \
      echo "Bundle up to date at {{ bundle_root }}"; \
    fi

sign-bundle: bundle
    if [ -z "{{ sign_identity }}" ]; then \
      echo "Set SIGN_IDENTITY to your 'Developer ID Application' signing identity"; \
      exit 1; \
    fi
    if [ ! -e "{{ signed_bundle }}" ] || [ "{{ bundle_root }}" -nt "{{ signed_bundle }}" ]; then \
      echo "Codesigning bundle with {{ sign_identity }}"; \
      codesign --sign "{{ sign_identity }}" --force --options runtime --timestamp "{{ bundle_root }}/Contents/Scripts/main"; \
      codesign --sign "{{ sign_identity }}" --force --options runtime --timestamp "{{ bundle_root }}"; \
      codesign --verify --strict --verbose=2 "{{ bundle_root }}"; \
      touch "{{ signed_bundle }}"; \
      echo "Codesign complete."; \
    else \
      echo "Signed bundle up to date at {{ signed_bundle }}"; \
    fi

install: sign-bundle
    if [ ! -e "{{ install_stamp }}" ] || [ "{{ signed_bundle }}" -nt "{{ install_stamp }}" ]; then \
      dest="{{ install_path }}/{{ bundle_name }}"; \
      echo "Installing to {{ install_path }}"; \
      rm -rf "$$dest"; \
      mkdir -p "{{ install_path }}"; \
      cp -R "{{ bundle_root }}" "{{ install_path }}"; \
      touch "{{ install_stamp }}"; \
      echo "Installed successfully. Restart LaunchBar or rescan actions to use."; \
    else \
      echo "Install up to date (stamp at {{ install_stamp }})"; \
    fi

dmg: sign-bundle
    if [ ! -e "{{ dmg_path }}" ] || [ "{{ bundle_root }}" -nt "{{ dmg_path }}" ]; then \
      echo "Creating DMG at {{ dmg_path }}..."; \
      rm -f "{{ dmg_path }}"; \
      mkdir -p "{{ action_build_path }}/dmg-root"; \
      rm -rf "{{ action_build_path }}/dmg-root/{{ bundle_name }}"; \
      cp -Rp "{{ bundle_root }}" "{{ action_build_path }}/dmg-root/"; \
      hdiutil create -fs HFS+ -format UDZO -volname "Swift Evolution" -srcfolder "{{ action_build_path }}/dmg-root" "{{ dmg_path }}"; \
      echo "DMG created: {{ dmg_path }}"; \
    else \
      echo "DMG up to date at {{ dmg_path }}"; \
    fi

sign-dmg: dmg
    if [ -z "{{ sign_identity }}" ]; then \
      echo "Set SIGN_IDENTITY to your 'Developer ID Application' signing identity"; \
      exit 1; \
    fi
    if [ ! -e "{{ signed_dmg }}" ] || [ "{{ dmg_path }}" -nt "{{ signed_dmg }}" ]; then \
      echo "Signing DMG with {{ sign_identity }}"; \
      codesign --sign "{{ sign_identity }}" --force "{{ dmg_path }}"; \
      codesign --verify --verbose=2 "{{ dmg_path }}"; \
      touch "{{ signed_dmg }}"; \
      echo "DMG signed."; \
    else \
      echo "DMG already signed (stamp at {{ signed_dmg }})"; \
    fi

pkg: sign-bundle
    needs_pkg=0; \
    if [ ! -e "{{ unsigned_pkg }}" ]; then needs_pkg=1; fi; \
    if [ "{{ bundle_root }}" -nt "{{ unsigned_pkg }}" ] 2>/dev/null; then needs_pkg=1; fi; \
    if [ packaging/postinstall.sh -nt "{{ unsigned_pkg }}" ] 2>/dev/null; then needs_pkg=1; fi; \
    if [ "$$needs_pkg" -eq 1 ]; then \
      echo "Creating PKG at {{ pkg_path }}..."; \
      rm -f "{{ pkg_path }}" "{{ unsigned_pkg }}"; \
      rm -rf "{{ pkg_root }}" "{{ pkg_scripts }}"; \
      mkdir -p "{{ pkg_root }}/Library/Application Support/LaunchBar/Actions"; \
      mkdir -p "{{ pkg_scripts }}"; \
      cp -Rp "{{ bundle_root }}" "{{ pkg_root }}/Library/Application Support/LaunchBar/Actions/"; \
      sed -e "s|@BUNDLE_NAME@|{{ bundle_name }}|g" \
          -e "s|@PKG_STAGE_ROOT@|{{ pkg_stage_root }}|g" \
          packaging/postinstall.sh > "{{ pkg_scripts }}/postinstall"; \
      chmod +x "{{ pkg_scripts }}/postinstall"; \
      pkgbuild \
        --root "{{ pkg_root }}" \
        --identifier com.humblehacker.LaunchBar.action.SwiftEvolution \
        --version "{{ version }}" \
        --install-location "{{ pkg_stage_root }}" \
        --scripts "{{ pkg_scripts }}" \
        "{{ unsigned_pkg }}"; \
      echo "Unsigned PKG created: {{ unsigned_pkg }}"; \
    else \
      echo "Unsigned PKG up to date at {{ unsigned_pkg }}"; \
    fi

sign-pkg: pkg
    if [ -z "{{ pkg_sign_identity }}" ]; then \
      echo "Set PKG_SIGN_IDENTITY to your 'Developer ID Installer' signing identity"; \
      exit 1; \
    fi
    if [ ! -e "{{ signed_pkg }}" ] || [ "{{ unsigned_pkg }}" -nt "{{ signed_pkg }}" ]; then \
      echo "Signing PKG with {{ pkg_sign_identity }}"; \
      productsign --sign "{{ pkg_sign_identity }}" --force "{{ unsigned_pkg }}" "{{ pkg_path }}"; \
      pkgutil --check-signature "{{ pkg_path }}"; \
      touch "{{ signed_pkg }}"; \
      echo "PKG signed: {{ pkg_path }}"; \
    else \
      echo "PKG already signed (stamp at {{ signed_pkg }})"; \
    fi

notarize-dmg: sign-dmg
    if [ -z "{{ notary_profile }}" ]; then \
      echo "Set NOTARY_PROFILE to your notarytool keychain profile (stored via 'xcrun notarytool store-credentials')"; \
      exit 1; \
    fi
    if [ ! -e "{{ notarized_dmg }}" ] || [ "{{ dmg_path }}" -nt "{{ notarized_dmg }}" ]; then \
      echo "Submitting {{ dmg_path }} for notarization with profile {{ notary_profile }}..."; \
      xcrun notarytool submit "{{ dmg_path }}" --keychain-profile "{{ notary_profile }}" --wait; \
      echo "Stapling ticket to DMG..."; \
      xcrun stapler staple "{{ dmg_path }}"; \
      echo "Validating stapled DMG..."; \
      xcrun stapler validate "{{ dmg_path }}"; \
      spctl --assess --type open --context context:primary-signature -vv "{{ dmg_path }}"; \
      touch "{{ notarized_dmg }}"; \
      echo "Notarization complete. Distribute the DMG."; \
    else \
      echo "DMG already notarized (stamp at {{ notarized_dmg }})"; \
    fi

notarize-pkg: sign-pkg
    if [ -z "{{ notary_profile }}" ]; then \
      echo "Set NOTARY_PROFILE to your notarytool keychain profile (stored via 'xcrun notarytool store-credentials')"; \
      exit 1; \
    fi
    if [ ! -e "{{ notarized_pkg }}" ] || [ "{{ pkg_path }}" -nt "{{ notarized_pkg }}" ]; then \
      echo "Submitting {{ pkg_path }} for notarization with profile {{ notary_profile }}..."; \
      xcrun notarytool submit "{{ pkg_path }}" --keychain-profile "{{ notary_profile }}" --wait; \
      echo "Stapling ticket to PKG..."; \
      xcrun stapler staple "{{ pkg_path }}"; \
      echo "Validating stapled PKG..."; \
      xcrun stapler validate "{{ pkg_path }}"; \
      pkgutil --check-signature "{{ pkg_path }}"; \
      spctl --assess --type install -vv "{{ pkg_path }}"; \
      touch "{{ notarized_pkg }}"; \
      echo "Notarization complete. Distribute the PKG."; \
    else \
      echo "PKG already notarized (stamp at {{ notarized_pkg }})"; \
    fi

release: notarize-dmg notarize-pkg
    if ! command -v gh >/dev/null 2>&1; then \
      echo "Error: GitHub CLI (gh) is not installed. Install it with 'brew install gh'"; \
      exit 1; \
    fi
    if [ -z "$$(git tag -l \"{{ version }}\")" ]; then \
      echo "Error: Tag {{ version }} does not exist. Create it with 'git tag {{ version }}'"; \
      exit 1; \
    fi
    echo "Creating release {{ version }}..."; \
    gh release create {{ version }} \
      "{{ dmg_path }}" \
      "{{ pkg_path }}" \
      --title "{{ version }}" \
      --generate-notes; \
    echo "Release {{ version }} published successfully!"

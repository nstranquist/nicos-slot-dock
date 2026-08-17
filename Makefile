SHELL := /bin/zsh
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: build bundle universal run install uninstall clean test headless-smoke verify verify-universal privacy-check secrets-check source-release-check ci publish-ready package-local package-release restart restart-dev icons

APP_NAME := Nicos Slot Dock
EXECUTABLE := SlotDock
SWIFT ?= swift
APP_DIR := .build/app/$(APP_NAME).app
UNIVERSAL_ROOT := .build/universal
UNIVERSAL_BINARY := $(UNIVERSAL_ROOT)/$(EXECUTABLE)
UNIVERSAL_APP := $(UNIVERSAL_ROOT)/$(APP_NAME).app
APP_VERSION ?= 0.3.6
BUILD_NUMBER ?= 9
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app
BUNDLE_ID := com.nstranquist.nicos-slot-dock
CODE_SIGN_IDENTITY ?= -
CODE_SIGN_OPTIONS ?=
ENTITLEMENTS ?= Resources/SlotDock.entitlements
CODE_SIGN_FLAGS = --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" $(CODE_SIGN_OPTIONS)
NOTARY_PROFILE ?=
ICONSET_DIR := .build/AppIcon.iconset
ICON_BASE := .build/AppIcon-1024.png

build:
	$(SWIFT) build -c release
	@bin_dir="$$( $(SWIFT) build -c release --show-bin-path )"; \
		$(MAKE) bundle BINARY_PATH="$$bin_dir/$(EXECUTABLE)" OUTPUT_APP="$(APP_DIR)"

bundle:
	@test -n "$(BINARY_PATH)" || (echo "BINARY_PATH is required" >&2; exit 2)
	@test -n "$(OUTPUT_APP)" || (echo "OUTPUT_APP is required" >&2; exit 2)
	@test -x "$(BINARY_PATH)" || (echo "missing binary: $(BINARY_PATH)" >&2; exit 2)
	@test -f "$(ENTITLEMENTS)" || (echo "missing entitlements: $(ENTITLEMENTS)" >&2; exit 2)
	@plutil -lint "$(ENTITLEMENTS)" >/dev/null
	@mkdir -p "$(OUTPUT_APP)/Contents/MacOS" "$(OUTPUT_APP)/Contents/Resources"
	@cp "$(BINARY_PATH)" "$(OUTPUT_APP)/Contents/MacOS/$(EXECUTABLE)"
	@cp Resources/Info.plist "$(OUTPUT_APP)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(OUTPUT_APP)/Contents/Resources/AppIcon.icns"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" "$(OUTPUT_APP)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(OUTPUT_APP)/Contents/Info.plist"
	@plutil -lint "$(OUTPUT_APP)/Contents/Info.plist" >/dev/null
	@codesign $(CODE_SIGN_FLAGS) --deep "$(OUTPUT_APP)"
	@signed_entitlements="$$(mktemp -t nicos-slot-dock-entitlements.XXXXXX)"; \
		trap 'rm "$$signed_entitlements"' EXIT; \
		codesign -d --entitlements "$$signed_entitlements" --xml "$(OUTPUT_APP)" >/dev/null 2>&1; \
		entitlement="$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.automation.apple-events' "$$signed_entitlements")"; \
		[[ "$$entitlement" == "true" ]] || (echo "signed app is missing the Apple Events Automation entitlement" >&2; exit 1)
	@echo "  Signed: $(CODE_SIGN_IDENTITY)"
	@echo "  Built: $(OUTPUT_APP)"
	@echo "  Executable: $(OUTPUT_APP)/Contents/MacOS/$(EXECUTABLE)"
	@ls -lh "$(OUTPUT_APP)/Contents/MacOS/$(EXECUTABLE)"

universal:
	@mkdir -p "$(UNIVERSAL_ROOT)"
	@$(SWIFT) build -c release --arch arm64 --scratch-path "$(UNIVERSAL_ROOT)/arm64"
	@$(SWIFT) build -c release --arch x86_64 --scratch-path "$(UNIVERSAL_ROOT)/x86_64"
	@arm_bin_dir="$$( $(SWIFT) build -c release --arch arm64 --scratch-path "$(UNIVERSAL_ROOT)/arm64" --show-bin-path )"; \
		x86_bin_dir="$$( $(SWIFT) build -c release --arch x86_64 --scratch-path "$(UNIVERSAL_ROOT)/x86_64" --show-bin-path )"; \
		/usr/bin/lipo -create "$$arm_bin_dir/$(EXECUTABLE)" "$$x86_bin_dir/$(EXECUTABLE)" -output "$(UNIVERSAL_BINARY)"
	@$(MAKE) bundle BINARY_PATH="$(UNIVERSAL_BINARY)" OUTPUT_APP="$(UNIVERSAL_APP)"

run: build
	@open "$(APP_DIR)"

# Daily-driver restart: installed app if present, else the just-built bundle.
restart:
	@if [[ -d "$(INSTALLED_APP)" ]]; then \
		pkill -x "$(EXECUTABLE)" 2>/dev/null || true; \
		sleep 0.3; \
		open "$(INSTALLED_APP)"; \
		echo "  Restarted: $(INSTALLED_APP)"; \
	else \
		$(MAKE) install; \
	fi

restart-dev: build
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.3
	@open "$(APP_DIR)"
	@echo "  Restarted: $(APP_DIR)"

install: build
	@set -euo pipefail; stage="$$(mktemp -d "$(INSTALL_DIR)/.nicos-slot-dock-install.XXXXXX")"; backup="$(INSTALLED_APP).previous.$$(date +%Y%m%d%H%M%S)"; trap 'rm -rf "$$stage"; if [[ -n "$${moved:-}" && ! -e "$(INSTALLED_APP)" && -e "$$moved" ]]; then mv "$$moved" "$(INSTALLED_APP)"; fi' EXIT; ditto "$(APP_DIR)" "$$stage/$(APP_NAME).app"; if [[ -e "$(INSTALLED_APP)" ]]; then moved="$$backup"; mv "$(INSTALLED_APP)" "$$moved"; fi; mv "$$stage/$(APP_NAME).app" "$(INSTALLED_APP)"; trap - EXIT; rmdir "$$stage" 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALLED_APP)" 2>/dev/null || true
	@echo "  Installed: $(INSTALLED_APP)"
	@if pgrep -xq "$(EXECUTABLE)"; then pkill -x "$(EXECUTABLE)" || true; sleep 0.3; echo "  Restarted running instance"; fi
	@open "$(INSTALLED_APP)"

uninstall:
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@set -euo pipefail; if [[ -e "$(INSTALLED_APP)" ]]; then target="$(INSTALLED_APP).uninstalled.$$(date +%Y%m%d%H%M%S)"; mv "$(INSTALLED_APP)" "$$target"; echo "  Moved to $$target"; else echo "  Not installed"; fi

test:
	$(SWIFT) test

headless-smoke: build
	@./scripts/headless_smoke.sh

verify: test build headless-smoke
	@codesign --verify --deep --strict "$(APP_DIR)"
	@test -x "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@plutil -lint "$(APP_DIR)/Contents/Info.plist" >/dev/null
	@test "$$('/usr/libexec/PlistBuddy' -c 'Print :CFBundleIdentifier' "$(APP_DIR)/Contents/Info.plist")" = "$(BUNDLE_ID)"
	@test "$$('/usr/libexec/PlistBuddy' -c 'Print :CFBundleDisplayName' "$(APP_DIR)/Contents/Info.plist")" = "$(APP_NAME)"
	@echo "  verify ok"

verify-universal: universal
	@archs="$$(/usr/bin/lipo -archs "$(UNIVERSAL_APP)/Contents/MacOS/$(EXECUTABLE)")"; \
		[[ " $$archs " == *" arm64 "* && " $$archs " == *" x86_64 "* ]] || (echo "expected arm64 and x86_64, got: $$archs" >&2; exit 1); \
		echo "  universal architectures: $$archs"
	@codesign --verify --deep --strict "$(UNIVERSAL_APP)"

privacy-check:
	@set -euo pipefail; bad=0; user_root='/Users'; file_pattern="($$user_root/[^/]+/|@(gmail|icloud)[.]com|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)"; synthetic_home_pattern="$$user_root/(example|me|test)/"; \
		for revision in $$(git rev-list --all); do \
			if git grep -I -n -E "$$file_pattern" "$$revision" -- . \
				| sed -E "s#$$synthetic_home_pattern#/synthetic-home/#g" \
				| grep -E "$$file_pattern"; then bad=1; fi; \
		done; \
		if git log --all --format='%ae%n%ce' | grep -Eiq '(@gmail[.]com|@icloud[.]com)'; then echo "personal commit email found" >&2; bad=1; fi; \
		(( bad == 0 )); \
		echo "  privacy history check ok"

secrets-check:
	@command -v gitleaks >/dev/null || (echo "gitleaks is required" >&2; exit 2)
	@gitleaks git --redact --no-banner .

source-release-check:
	@git diff --check
	@for required in LICENSE README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md PRIVACY.md CODE_OF_CONDUCT.md docs/ARCHITECTURE.md docs/PROVENANCE.md docs/RELEASING.md .nicos/product.yaml portfolio/manifest.yaml .github/workflows/ci.yml Resources/AppIcon.icns Resources/SlotDock.entitlements; do test -f "$$required" || (echo "missing required public file: $$required" >&2; exit 1); done
	@test -z "$$(git ls-files .build)" || (echo "build output is tracked" >&2; exit 1)
	@test -z "$$(git status --porcelain)" || (echo "working tree is not clean" >&2; git status --short >&2; exit 1)
	@echo "  source release check ok"

ci: verify verify-universal privacy-check source-release-check

publish-ready: ci secrets-check
	@echo "  source publication gates ok"

# Local-only artifact. Never attach this ad-hoc-signed archive to a release.
package-local: build
	@mkdir -p .build/artifacts
	@ditto -c -k --keepParent "$(APP_DIR)" ".build/artifacts/NicosSlotDock-$(APP_VERSION)-local-adhoc.zip"
	@shasum -a 256 ".build/artifacts/NicosSlotDock-$(APP_VERSION)-local-adhoc.zip" > ".build/artifacts/NicosSlotDock-$(APP_VERSION)-local-adhoc.zip.sha256"
	@echo ".build/artifacts/NicosSlotDock-$(APP_VERSION)-local-adhoc.zip"

# Requires an installed Developer ID identity and a notarytool keychain profile.
package-release:
	@if [[ "$(CODE_SIGN_IDENTITY)" == "-" ]]; then echo "CODE_SIGN_IDENTITY must name a Developer ID Application identity" >&2; exit 2; fi
	@if [[ -z "$(NOTARY_PROFILE)" ]]; then echo "NOTARY_PROFILE is required" >&2; exit 2; fi
	@$(MAKE) universal CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" CODE_SIGN_OPTIONS="--options runtime --timestamp"
	@mkdir -p .build/artifacts
	@ditto -c -k --keepParent "$(UNIVERSAL_APP)" ".build/artifacts/NicosSlotDock-$(APP_VERSION)-notarization-upload.zip"
	@xcrun notarytool submit ".build/artifacts/NicosSlotDock-$(APP_VERSION)-notarization-upload.zip" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple "$(UNIVERSAL_APP)"
	@xcrun stapler validate "$(UNIVERSAL_APP)"
	@spctl --assess --type execute --verbose=4 "$(UNIVERSAL_APP)"
	@ditto -c -k --keepParent "$(UNIVERSAL_APP)" ".build/artifacts/NicosSlotDock-$(APP_VERSION).zip"
	@shasum -a 256 ".build/artifacts/NicosSlotDock-$(APP_VERSION).zip" > ".build/artifacts/NicosSlotDock-$(APP_VERSION).zip.sha256"
	@echo ".build/artifacts/NicosSlotDock-$(APP_VERSION).zip"

icons:
	@command -v magick >/dev/null || (echo "ImageMagick is required to regenerate the icon" >&2; exit 2)
	@mkdir -p "$(ICONSET_DIR)"
	@magick -background none assets/nicos-slot-dock.svg -resize 1024x1024 "$(ICON_BASE)"
	@sips -z 16 16 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_16x16.png" >/dev/null
	@sips -z 32 32 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_16x16@2x.png" >/dev/null
	@sips -z 32 32 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_32x32.png" >/dev/null
	@sips -z 64 64 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_32x32@2x.png" >/dev/null
	@sips -z 128 128 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_128x128.png" >/dev/null
	@sips -z 256 256 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_128x128@2x.png" >/dev/null
	@sips -z 256 256 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_256x256.png" >/dev/null
	@sips -z 512 512 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_256x256@2x.png" >/dev/null
	@sips -z 512 512 "$(ICON_BASE)" --out "$(ICONSET_DIR)/icon_512x512.png" >/dev/null
	@cp "$(ICON_BASE)" "$(ICONSET_DIR)/icon_512x512@2x.png"
	@iconutil -c icns "$(ICONSET_DIR)" -o Resources/AppIcon.icns
	@echo "  generated Resources/AppIcon.icns"

clean:
	$(SWIFT) package clean
	@rm -rf .build

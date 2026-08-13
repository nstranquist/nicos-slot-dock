.PHONY: build run install uninstall clean test headless-smoke verify package restart restart-dev

APP_NAME := Slot Dock
BUNDLE_NAME := SlotDock
EXECUTABLE := SlotDock
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).app
APP_VERSION ?= 0.3.1
BUILD_NUMBER ?= 4
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/Slot Dock.app
BUNDLE_ID := com.nstranquist.nicos-slot-dock
CODE_SIGN_IDENTITY ?= -
CODE_SIGN_FLAGS := --force --sign "$(CODE_SIGN_IDENTITY)"

build:
	swift build -c release
	@mkdir -p "$(APP_DIR)/Contents/MacOS"
	@mkdir -p "$(APP_DIR)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" "$(APP_DIR)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(APP_DIR)/Contents/Info.plist"
	@plutil -lint "$(APP_DIR)/Contents/Info.plist" >/dev/null
	@codesign $(CODE_SIGN_FLAGS) --deep "$(APP_DIR)"
	@echo "  Signed: $(CODE_SIGN_IDENTITY)"
	@echo "  Built: $(APP_DIR)"
	@echo "  Executable: $(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@ls -lh "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"

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
	@set -euo pipefail; mkdir -p "$(INSTALL_DIR)"; stage="$$(mktemp -d "$(INSTALL_DIR)/.slot-dock-install.XXXXXX")"; backup="$(INSTALLED_APP).previous.$$(date +%Y%m%d%H%M%S)"; trap 'rm -rf "$$stage"; if [[ -n "$${moved:-}" && ! -e "$(INSTALLED_APP)" && -e "$$moved" ]]; then mv "$$moved" "$(INSTALLED_APP)"; fi' EXIT; ditto "$(APP_DIR)" "$$stage/Slot Dock.app"; if [[ -e "$(INSTALLED_APP)" ]]; then moved="$$backup"; mv "$(INSTALLED_APP)" "$$moved"; fi; mv "$$stage/Slot Dock.app" "$(INSTALLED_APP)"; trap - EXIT; rmdir "$$stage" 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALLED_APP)" 2>/dev/null || true
	@echo "  Installed: $(INSTALLED_APP)"
	@if pgrep -xq "$(EXECUTABLE)"; then pkill -x "$(EXECUTABLE)" || true; sleep 0.3; echo "  Restarted running instance"; fi
	@open "$(INSTALLED_APP)"

uninstall:
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@set -euo pipefail; if [[ -e "$(INSTALLED_APP)" ]]; then target="$(INSTALLED_APP).uninstalled.$$(date +%Y%m%d%H%M%S)"; mv "$(INSTALLED_APP)" "$$target"; echo "  Moved to $$target"; else echo "  Not installed"; fi

test:
	swift test

headless-smoke: build
	@./scripts/headless_smoke.sh

verify: test build headless-smoke
	@codesign --verify --deep --strict "$(APP_DIR)"
	@test -x "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@plutil -lint "$(APP_DIR)/Contents/Info.plist" >/dev/null
	@/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(APP_DIR)/Contents/Info.plist" | grep -q 'nicos-slot-dock'
	@echo "  verify ok"

package: build
	@mkdir -p .build/artifacts
	@ditto -c -k --keepParent "$(APP_DIR)" ".build/artifacts/SlotDock-$(APP_VERSION).zip"
	@shasum -a 256 ".build/artifacts/SlotDock-$(APP_VERSION).zip" > ".build/artifacts/SlotDock-$(APP_VERSION).zip.sha256"
	@echo ".build/artifacts/SlotDock-$(APP_VERSION).zip"

clean:
	swift package clean
	@rm -rf .build

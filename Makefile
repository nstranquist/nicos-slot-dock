.PHONY: build run install uninstall clean test headless-smoke verify package

APP_NAME := Slot Dock
BUNDLE_NAME := SlotDock
EXECUTABLE := SlotDock
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).app
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
	@plutil -lint "$(APP_DIR)/Contents/Info.plist" >/dev/null
	@codesign $(CODE_SIGN_FLAGS) --deep "$(APP_DIR)" 2>/dev/null && echo "  Signed (ad-hoc)" || echo "  (codesign skipped)"
	@echo "  Built: $(APP_DIR)"
	@echo "  Executable: $(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@ls -lh "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"

run: build
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.3
	@open "$(APP_DIR)"

install: build
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.5
	@rm -rf "$(INSTALLED_APP)"
	@mkdir -p "$(INSTALL_DIR)"
	@cp -R "$(APP_DIR)" "$(INSTALLED_APP)"
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(INSTALLED_APP)" 2>/dev/null || true
	@echo "  Installed: $(INSTALLED_APP)"
	@open "$(INSTALLED_APP)"

uninstall:
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@rm -rf "$(INSTALLED_APP)"
	@echo "  Uninstalled $(APP_NAME)"

test:
	swift test

headless-smoke: build
	@./scripts/headless_smoke.sh

verify: test build
	@codesign --verify --deep --strict "$(APP_DIR)" 2>/dev/null || true
	@test -x "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@plutil -lint "$(APP_DIR)/Contents/Info.plist" >/dev/null
	@/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(APP_DIR)/Contents/Info.plist" | grep -q 'nicos-slot-dock'
	@echo "  verify ok"

package: build
	@echo "$(APP_DIR)"

clean:
	swift package clean
	@rm -rf .build

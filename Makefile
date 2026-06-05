APP_NAME := FreeFlow
BUNDLE_ID := com.freeflow.app
SIGN_IDENTITY := Free Flow Dev
BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INFO_PLIST := Sources/FreeFlow/Resources/Info.plist
ENTITLEMENTS := Sources/FreeFlow/Resources/FreeFlow.entitlements
INSTALL_DIR := /Applications

# Verbose-log opt-in (`make DEBUG=true install`). When true, defines the
# `DICTATION_VERBOSE_LOGS` swiftc flag so the source code can `#if`-guard
# `privacy: .public` on selected logging calls (errors, sizes, state
# transitions). See docs/conventions/logging.md.
DEBUG ?= false
ifeq ($(DEBUG),true)
SWIFT_DEBUG_FLAGS := -Xswiftc -D -Xswiftc DICTATION_VERBOSE_LOGS
else
SWIFT_DEBUG_FLAGS :=
endif

.PHONY: build bundle sign verify install clean test

build:
ifeq ($(DEBUG),true)
	@echo "⚠️  --debug true: building with verbose logs."
	@echo "    Error messages and diagnostic counts will be visible in os_log output"
	@echo "    (not redacted as <private>). User content like transcribed text remains private."
	@echo "    Do NOT use this build for distribution."
endif
	swift build -c release --arch arm64 $(SWIFT_DEBUG_FLAGS)

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/arm64-apple-macosx/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist

sign: bundle
	codesign --force --options runtime \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_IDENTITY)" \
		$(APP_BUNDLE)

verify: sign
	@echo "--- codesign -dv output ---"
	@codesign -dv $(APP_BUNDLE) 2>&1 | tee /tmp/freeflow-codesign.txt
	@grep -q "Identifier=$(BUNDLE_ID)" /tmp/freeflow-codesign.txt || \
		(echo "FAIL: bundle identifier is not $(BUNDLE_ID)"; exit 1)
	@echo "--- entitlements ---"
	@codesign -d --entitlements - --xml $(APP_BUNDLE) 2>/dev/null | plutil -p - || true
	@echo "OK: bundle identifier matches"

install: verify
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

test:
	swift test

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
